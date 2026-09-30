#!/usr/bin/env python3
"""正式第一关「协议检疫站」的 LDtk 编译器。

布局、实体与视觉语义全部来自 ``godot/maps/m01_protocol_quarantine.ldtk``；
本文件的 ``--seed`` 只负责首次建档，并拒绝覆盖已存在的 LDtk。日后改图应在
LDtk 中完成，再用 ``--write`` 编译 Godot 可接入的数据，禁止反向修改生成文件。
``--rework-combat-slice`` 是一次性、可重复安全执行的检疫厅版本迁移；不会重置其他房间。
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any
import map_checkpoint_contract as checkpoint_contract


ROOT = Path(__file__).resolve().parents[2]
LDTK_PATH = ROOT / "godot" / "maps" / "m01_protocol_quarantine.ldtk"
OUTPUT_PATH = ROOT / "godot" / "generated" / "m01_protocol_quarantine_data.gd"
LEVEL_ID = "M01_ProtocolQuarantine"
W, H, TS = 280, 30, 32
COMBAT_SLICE_REVISION = "bat_cargo_lane_v1"
CAMPAIGN_REVISION = "extended_quarantine_run_v1"
CORE_CARGO_REVISION = "core_cargo_spacing_v1"


class MapError(RuntimeError):
    """地图合同不成立；错误文本应能直接定位到 LDtk 格子。"""


@dataclass(frozen=True)
class LayerSpec:
    uid: int
    values: dict[int, tuple[str, str]]
    opacity: float = 1.0


LAYER_SPECS: dict[str, LayerSpec] = {
    "Collision": LayerSpec(1, {
        1: ("Solid", "#34455D"), 2: ("OneWay", "#8FD9E8"),
    }),
    "Rooms": LayerSpec(2, {
        1: ("SafeEntry", "#64748A"), 2: ("QuarantineHall", "#557B86"),
        3: ("MaintenanceShaft", "#43767A"), 4: ("ArchiveSorting", "#796C58"),
        5: ("ServiceCheckpoint", "#789A80"), 6: ("CoolantDescent", "#497C86"),
        7: ("FreightCrossfire", "#9B7757"), 8: ("UplinkCheckpoint", "#718F83"),
        9: ("ContainmentCore", "#985A70"), 10: ("ExitGallery", "#77545F"),
    }, 0.18),
    "Entities": LayerSpec(3, {
        1: ("PlayerSpawn", "#FFFFFF"), 2: ("Exit", "#FFD166"),
        3: ("MeleeInspector", "#28D7E5"), 4: ("Gunner", "#FF4FA3"),
        5: ("BatCargo", "#FFC16A"),
    }),
    "Architecture": LayerSpec(4, {
        1: ("EntryScanner", "#6C91A8"), 2: ("QuarantineChamber", "#86AAB2"),
        3: ("ShaftStatusDisplay", "#4DA7A0"), 4: ("ArchiveSorter", "#AF8D58"),
        5: ("ExitSeal", "#A95A69"), 6: ("OpenStair", "#91A2B5"),
        7: ("ServiceBench", "#9FC6AD"), 8: ("CoolantReservoir", "#59A7AD"),
        9: ("FreightGantry", "#B78C60"), 10: ("ContainmentCore", "#BE6D87"),
    }, 0.46),
    "BackdropTiles": LayerSpec(5, {
        1: ("WallShell", "#34495B"), 2: ("Recess", "#182734"),
        3: ("ObservationGlass", "#315A68"), 4: ("ServiceVoid", "#0D151D"),
    }, 0.34),
    "ForegroundTiles": LayerSpec(6, {
        1: ("NearBeam", "#1A2632"), 2: ("NearPipe", "#263B45"),
        3: ("HangingChain", "#34404A"), 4: ("NearGrate", "#28303C"),
    }, 0.38),
    "Lights": LayerSpec(7, {
        1: ("CyanWork", "#6DE5F0"), 2: ("AmberWork", "#FFC16A"),
        3: ("MagentaAlert", "#FF4FA3"), 4: ("RedLockdown", "#E75963"),
    }, 0.72),
    "Traversal": LayerSpec(8, {
        1: ("MainWalk", "#62E6A5"), 2: ("JumpLanding", "#F5CA68"),
        3: ("StairRise", "#78C6FF"), 4: ("RoomTransition", "#D7A5FF"),
    }, 0.42),
}

ENTITY_TO_CHAR = {1: "@", 2: ">", 3: "m", 4: "x", 5: "C"}
COLLISION_TO_CHAR = {0: ".", 1: "#", 2: "="}
ROOM_PROFILES = {
    "safe_entry": "connector",
    "quarantine_scanner": "main",
    "coolant_shaft": "shaft",
    "archive_sorter": "main",
    "egress_lock": "connector",
    "service_bay": "connector",
    "coolant_reservoir": "main",
    "freight_crossfire": "main",
    "relay_service": "connector",
    "containment_core": "main",
}


def _iid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"kairull:m01:{label}"))


def _blank() -> list[list[int]]:
    return [[0] * W for _ in range(H)]


def _fill(grid: list[list[int]], x0: int, y0: int, x1: int, y1: int, value: int) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not (0 <= x < W and 0 <= y < H):
                raise MapError(f"写出地图边界：c{x} r{y}")
            grid[y][x] = value


def _put(grid: list[list[int]], x: int, y: int, value: int) -> None:
    _fill(grid, x, y, x, y, value)


def _seed_grids() -> dict[str, list[list[int]]]:
    """只用于首次建档；五段空间不读取或复制旧 M01/M03。"""
    grids = {name: _blank() for name in LAYER_SPECS}
    collision = grids["Collision"]
    rooms = grids["Rooms"]

    # 世界外壳和五个房间。矩形尺寸是镜头/物理合同的一部分。
    _fill(collision, 0, 0, W - 1, 0, 1)
    _fill(collision, 0, H - 1, W - 1, H - 1, 1)
    _fill(collision, 0, 0, 0, H - 1, 1)
    _fill(collision, W - 1, 0, W - 1, H - 1, 1)
    room_rects = [
        (1, 1, 19, 14, 10), (2, 15, 11, 36, 18),
        (3, 51, 6, 12, 23), (4, 63, 6, 38, 18),
        (5, 101, 14, 14, 10),
    ]
    for room_id, x, y, width, height in room_rects:
        _fill(rooms, x, y, x + width - 1, y + height - 1, room_id)
        _fill(collision, x, y, x + width - 1, y, 1)
        _fill(collision, x, y + height - 1, x + width - 1, y + height - 1, 1)

    # 检疫厅用两个低基座打断长平地；主路线均能以普通跳跃通过。
    _fill(collision, 27, 26, 32, 28, 1)
    _fill(collision, 40, 27, 44, 28, 1)
    # 维护竖井不再叠加粗格单向平台；只在十级高度场尽头保留一格同高接口，
    # 让 c61 最后踏面安全接到 c63 上层地板，接口本身不算楼梯踏面。
    _put(collision, 62, 23, 2)
    # 档案厅的设备基座提供高低差，不在其边缘放敌人。
    _fill(collision, 80, 21, 87, 23, 1)
    _fill(collision, 92, 22, 96, 23, 1)

    entities = grids["Entities"]
    for x, y, value in (
        (4, 27, 1), (112, 22, 2),
        (22, 27, 3), (30, 25, 4), (46, 27, 3),
        (70, 22, 4), (83, 20, 3), (94, 21, 4),
    ):
        _put(entities, x, y, value)

    arch = grids["Architecture"]
    _fill(arch, 4, 21, 10, 26, 1)
    _fill(arch, 19, 14, 29, 23, 2)
    _fill(arch, 53, 8, 55, 23, 3)
    # 每个 32px 横向格对应一级 16px 踏面；相邻两级共享一个 IntGrid 行。
    for i in range(10):
        _put(arch, 52 + i, 27 - i // 2, 6)
    _fill(arch, 72, 9, 89, 18, 4)
    _fill(arch, 106, 16, 112, 21, 5)

    backdrop = grids["BackdropTiles"]
    for room_id, x, y, width, height in room_rects:
        _fill(backdrop, x + 1, y + 1, x + width - 2, y + height - 2, 1)
    _fill(backdrop, 6, 22, 9, 25, 2)
    _fill(backdrop, 18, 14, 31, 20, 3)
    _fill(backdrop, 52, 7, 61, 20, 4)
    _fill(backdrop, 68, 9, 96, 15, 3)
    _fill(backdrop, 106, 17, 111, 20, 2)

    foreground = grids["ForegroundTiles"]
    _fill(foreground, 13, 20, 13, 27, 1)
    _fill(foreground, 37, 12, 38, 24, 2)
    _fill(foreground, 65, 7, 65, 18, 3)
    _fill(foreground, 98, 7, 99, 21, 1)
    _fill(foreground, 103, 15, 104, 21, 4)

    lights = grids["Lights"]
    for x, y, value in (
        (5, 20, 1), (11, 20, 1),
        (19, 12, 1), (28, 12, 2), (39, 12, 1), (48, 12, 3),
        (54, 8, 1), (60, 8, 2),
        (68, 8, 2), (80, 8, 1), (92, 8, 2), (98, 8, 3),
        (106, 15, 4), (112, 15, 3),
    ):
        _put(lights, x, y, value)

    traversal = grids["Traversal"]
    _fill(traversal, 3, 27, 26, 27, 1)
    _fill(traversal, 27, 25, 32, 25, 1)
    _fill(traversal, 33, 27, 39, 27, 1)
    _fill(traversal, 40, 26, 44, 26, 1)
    _fill(traversal, 45, 27, 50, 27, 1)
    for i in range(10):
        _put(traversal, 52 + i, 27 - i // 2, 3)
    _fill(traversal, 63, 22, 79, 22, 1)
    _fill(traversal, 80, 20, 87, 20, 1)
    _fill(traversal, 88, 22, 91, 22, 1)
    _fill(traversal, 92, 21, 96, 21, 1)
    _fill(traversal, 97, 22, 112, 22, 1)
    for x, y in ((14, 27), (15, 27), (50, 27), (51, 27),
                 (62, 22), (63, 22), (100, 22), (101, 22)):
        _put(traversal, x, y, 4)
    for x, y in ((26, 27), (33, 27), (39, 27), (45, 27),
                 (51, 27), (63, 22), (79, 22), (88, 22), (91, 22), (97, 22)):
        _put(traversal, x, y, 2)
    return grids


ROOM_METADATA = [
    {"room_id": "safe_entry", "display_name": "安全入口", "decor_profile": "safe_entry",
     "role": "connector", "rect": [1, 19, 14, 10], "primary_landmark": "entry_scanner"},
    {"room_id": "quarantine_hall", "display_name": "检疫战斗厅", "decor_profile": "quarantine_scanner",
     "role": "main", "rect": [15, 11, 36, 18], "primary_landmark": "quarantine_chamber"},
    {"room_id": "maintenance_shaft", "display_name": "维护竖井", "decor_profile": "coolant_shaft",
     "role": "shaft", "rect": [51, 6, 12, 23], "primary_landmark": "shaft_status_display"},
    {"room_id": "archive_sorting", "display_name": "档案分拣厅", "decor_profile": "archive_sorter",
     "role": "main", "rect": [63, 6, 38, 18], "primary_landmark": "archive_sorter"},
    {"room_id": "exit_gallery", "display_name": "封锁出口", "decor_profile": "egress_lock",
     "role": "connector", "rect": [101, 14, 14, 10], "primary_landmark": "exit_seal"},
]

STAIR_METADATA = [{
    "stair_id": "shaft_lower_rise", "room_id": "maintenance_shaft",
    "bottom_cell": [52, 28], "top_cell": [62, 23], "direction": "right_up",
    "step_run_px": 32, "step_rise_px": 16, "steps": 10,
    "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False,
}]


def _layer_def(name: str, spec: LayerSpec) -> dict[str, Any]:
    return {
        "__type": "IntGrid", "identifier": name, "type": "IntGrid", "uid": spec.uid,
        "doc": "正式第一关语义层；由中文合同约束，未知值会使编译失败。",
        "uiColor": None, "gridSize": TS, "guideGridWid": 0, "guideGridHei": 0,
        "displayOpacity": spec.opacity, "inactiveOpacity": 0.25,
        "hideInList": False, "hideFieldsWhenInactive": False,
        "canSelectWhenInactive": True, "renderInWorldView": True,
        "pxOffsetX": 0, "pxOffsetY": 0, "parallaxFactorX": 0,
        "parallaxFactorY": 0, "parallaxScaling": True, "requiredTags": [],
        "excludedTags": [], "autoTilesKilledByOtherLayerUid": None,
        "uiFilterTags": [], "useAsyncRender": False,
        "intGridValues": [
            {"value": value, "identifier": ident, "color": color, "tile": None, "groupUid": 0}
            for value, (ident, color) in spec.values.items()
        ],
        "intGridValuesGroups": [], "autoRuleGroups": [], "autoSourceLayerDefUid": None,
        "tilesetDefUid": None, "tilePivotX": 0, "tilePivotY": 0, "biomeFieldUid": None,
    }


def _layer_instance(name: str, spec: LayerSpec, grid: list[list[int]]) -> dict[str, Any]:
    return {
        "__identifier": name, "__type": "IntGrid", "__cWid": W, "__cHei": H,
        "__gridSize": TS, "__opacity": spec.opacity, "__pxTotalOffsetX": 0,
        "__pxTotalOffsetY": 0, "__tilesetDefUid": None, "__tilesetRelPath": None,
        "iid": _iid(f"layer:{name}"), "levelId": 1, "layerDefUid": spec.uid,
        "pxOffsetX": 0, "pxOffsetY": 0, "visible": True, "optionalRules": [],
        "intGridCsv": [value for row in grid for value in row],
        "autoLayerTiles": [], "seed": 4701, "overrideTilesetUid": None,
        "gridTiles": [], "entityInstances": [],
    }


def _seed_ldtk() -> None:
    if LDTK_PATH.exists():
        raise MapError(f"拒绝覆盖现有 LDtk：{LDTK_PATH}")
    grids = _seed_grids()
    doc = {
        "__header__": {"fileType": "LDtk Project JSON", "app": "LDtk",
                       "doc": "https://ldtk.io/json", "schema": "https://ldtk.io/files/JSON_SCHEMA.json",
                       "appAuthor": "Sebastien 'deepnight' Benard", "appVersion": "1.5.3",
                       "url": "https://ldtk.io"},
        "iid": _iid("project"), "jsonVersion": "1.5.3", "appBuildId": 473703,
        "nextUid": 40, "identifierStyle": "Capitalize", "toc": [], "worldLayout": "Free",
        "worldGridWidth": W * TS, "worldGridHeight": H * TS,
        "defaultLevelWidth": W * TS, "defaultLevelHeight": H * TS,
        "defaultPivotX": 0, "defaultPivotY": 0, "defaultGridSize": TS,
        "defaultEntityWidth": TS, "defaultEntityHeight": TS,
        "bgColor": "#0D151D", "defaultLevelBgColor": "#0D151D",
        "minifyJson": False, "externalLevels": False, "exportTiled": False,
        "simplifiedExport": False, "imageExportMode": "None", "exportLevelBg": True,
        "pngFilePattern": None, "backupOnSave": True, "backupLimit": 10,
        "backupRelPath": None, "levelNamePattern": "Level_%idx", "tutorialDesc": None,
        "customCommands": [], "flags": [],
        "defs": {"layers": [_layer_def(name, spec) for name, spec in LAYER_SPECS.items()],
                 "entities": [], "tilesets": [], "enums": [], "externalEnums": [],
                 "levelFields": []},
        "levels": [{
            "identifier": LEVEL_ID, "iid": _iid("level"), "uid": 1,
            "worldX": 0, "worldY": 0, "worldDepth": 0,
            "pxWid": W * TS, "pxHei": H * TS, "__bgColor": "#0D151D",
            "bgColor": None, "useAutoIdentifier": False, "bgRelPath": None,
            "bgPos": None, "bgPivotX": 0, "bgPivotY": 0,
            "__smartColor": "#6DE5F0", "__bgPos": None, "externalRelPath": None,
            "fieldInstances": [
                {"__identifier": "RoomMetadata", "__tile": None, "__type": "String",
                 "__value": json.dumps(ROOM_METADATA, ensure_ascii=False, separators=(",", ":")),
                 "defUid": 31, "realEditorValues": []},
                {"__identifier": "StairMetadata", "__tile": None, "__type": "String",
                 "__value": json.dumps(STAIR_METADATA, ensure_ascii=False, separators=(",", ":")),
                 "defUid": 32, "realEditorValues": []},
            ],
            "layerInstances": [
                _layer_instance(name, spec, grids[name])
                for name, spec in reversed(list(LAYER_SPECS.items()))
            ], "__neighbours": [],
        }],
        "worlds": [], "dummyWorldIid": _iid("world"),
    }
    # 添加正式 level field 定义，元数据仍保存在 LDtk 本体而非生成器输出。
    doc["defs"]["levelFields"] = [
        {"identifier": "RoomMetadata", "doc": "JSON：房间 id、显示名、装饰配置与职责。",
         "__type": "String", "uid": 31, "type": "String", "isArray": False,
         "canBeNull": False, "defaultOverride": None, "editorDisplayMode": "ValueOnly",
         "editorDisplayPos": "Above", "editorLinkStyle": "ZigZag", "editorDisplayScale": 1,
         "editorAlwaysShow": True, "editorShowInWorld": True, "editorCutLongValues": False,
         "editorTextSuffix": None, "editorTextPrefix": None, "useForSmartColor": False},
        {"identifier": "StairMetadata", "doc": "JSON：开放钢梯的视觉与碰撞共同描述。",
         "__type": "String", "uid": 32, "type": "String", "isArray": False,
         "canBeNull": False, "defaultOverride": None, "editorDisplayMode": "ValueOnly",
         "editorDisplayPos": "Above", "editorLinkStyle": "ZigZag", "editorDisplayScale": 1,
         "editorAlwaysShow": True, "editorShowInWorld": True, "editorCutLongValues": False,
         "editorTextSuffix": None, "editorTextPrefix": None, "useForSmartColor": False},
    ]
    _apply_combat_slice_rework(doc)
    _apply_campaign_extension(doc)
    checkpoint_contract.add_single_checkpoint(doc, MapError)
    LDTK_PATH.parent.mkdir(parents=True, exist_ok=True)
    LDTK_PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已创建正式第一关 LDtk：{LDTK_PATH}", file=sys.stderr)


def _apply_combat_slice_rework(doc: dict[str, Any]) -> bool:
    """只迁移检疫厅；版本标记阻止再次执行时覆盖用户后续 LDtk 编辑。"""
    levels = [level for level in doc.get("levels", []) if level.get("identifier") == LEVEL_ID]
    if len(levels) != 1:
        raise MapError(f"迁移需要唯一关卡 {LEVEL_ID}")
    level = levels[0]
    fields = level.setdefault("fieldInstances", [])
    existing = [field for field in fields if field.get("__identifier") == "CombatSliceRevision"]
    if existing:
        if len(existing) != 1 or existing[0].get("__value") != COMBAT_SLICE_REVISION:
            raise MapError("CombatSliceRevision 不受支持；拒绝覆盖未知版本的用户地图")
        return False
    layers = {layer["__identifier"]: layer for layer in level["layerInstances"]}
    for name in LAYER_SPECS:
        if name not in layers or len(layers[name].get("intGridCsv", [])) != W * H:
            raise MapError(f"迁移前 {name} 格数据不完整")

    def fill(name: str, x0: int, y0: int, x1: int, y1: int, value: int) -> None:
        values = layers[name]["intGridCsv"]
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                values[y * W + x] = value

    # 货运线保持同一地面：球棒→货箱→枪手可以一眼读懂，六格翻滚不再被碎基座打断。
    fill("Collision", 15, 12, 50, 27, 0)
    # 单向维护步道提供可选高路；下方主线与货箱弹道仍开放，普通跳跃即可上台。
    fill("Collision", 41, 25, 47, 25, 2)
    fill("Entities", 15, 12, 50, 27, 0)
    for x, value in ((21, 3), (28, 5), (36, 4), (40, 5), (47, 3)):
        fill("Entities", x, 27, x, 27, value)

    # 一个扫描舱统领整个货运战斗区，地标落点与第一只可击飞货箱对齐。
    fill("Architecture", 15, 12, 50, 27, 0)
    fill("Architecture", 25, 16, 36, 25, 2)
    fill("BackdropTiles", 16, 12, 49, 27, 1)
    fill("BackdropTiles", 25, 16, 36, 24, 3)
    # 前景吊管移至两侧高处，不能挡住示范货箱或枪手的警戒动画。
    fill("ForegroundTiles", 15, 12, 50, 27, 0)
    fill("ForegroundTiles", 17, 12, 17, 20, 2)
    fill("ForegroundTiles", 49, 12, 49, 19, 3)
    fill("Lights", 15, 12, 50, 27, 0)
    for x, y, value in ((20, 23, 2), (27, 17, 1), (35, 17, 1), (44, 20, 2)):
        fill("Lights", x, y, x, y, value)
    fill("Traversal", 15, 12, 50, 27, 0)
    fill("Traversal", 15, 27, 50, 27, 1)
    fill("Traversal", 41, 24, 47, 24, 1)
    for x, y, value in ((15, 27, 4), (50, 27, 4), (41, 24, 2), (47, 24, 2)):
        fill("Traversal", x, y, x, y, value)

    definitions = doc["defs"]["layers"]
    entity_def = next(item for item in definitions if item.get("identifier") == "Entities")
    if not any(item.get("value") == 5 for item in entity_def["intGridValues"]):
        identifier, color = LAYER_SPECS["Entities"].values[5]
        entity_def["intGridValues"].append({
            "value": 5, "identifier": identifier, "color": color, "tile": None, "groupUid": 0,
        })
    field_def = copy.deepcopy(doc["defs"]["levelFields"][0])
    field_uid = max(int(doc.get("nextUid", 40)), 40)
    field_def.update({"identifier": "CombatSliceRevision", "uid": field_uid,
                      "doc": "只执行一次的检疫厅布局迁移版本；勿手动删除。"})
    doc["defs"]["levelFields"].append(field_def)
    doc["nextUid"] = field_uid + 1
    fields.append({"__identifier": "CombatSliceRevision", "__tile": None, "__type": "String",
                   "__value": COMBAT_SLICE_REVISION, "defUid": field_uid, "realEditorValues": []})
    return True


def _rework_combat_slice() -> None:
    original = LDTK_PATH.read_bytes()
    doc = json.loads(original.decode("utf-8"))
    if not _apply_combat_slice_rework(doc):
        print("检疫厅已迁移；保留之后的 LDtk 编辑，不重复重排", file=sys.stderr)
        return
    # 先在内存完整验收，任何合同错误都不能把现有 LDtk 写成半成品。
    _validate_and_compile(doc, "migration-validation")
    LDTK_PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("已迁移检疫厅：连续货运线、两只球棒货箱、可选维护步道；其他房间保持", file=sys.stderr)


def _apply_campaign_extension(doc: dict[str, Any]) -> bool:
    """保留已认可的前 63 列，只重建后段；幂等标记保护今后的 LDtk 手工编辑。"""
    level = next(item for item in doc["levels"] if item["identifier"] == LEVEL_ID)
    fields = level["fieldInstances"]
    revision_fields = [field for field in fields if field["__identifier"] == "CampaignRevision"]
    if revision_fields:
        if len(revision_fields) != 1 or revision_fields[0].get("__value") != CAMPAIGN_REVISION:
            raise MapError("CampaignRevision 不受支持，拒绝覆盖未知版本")
        return False
    old_w = int(level["pxWid"]) // TS
    if int(level["pxHei"]) != H * TS or old_w < 63:
        raise MapError("扩展前地图尺寸异常，不能安全保留已认可的前三房")
    instances = {layer["__identifier"]: layer for layer in level["layerInstances"]}
    grids: dict[str, list[int]] = {}
    for name in LAYER_SPECS:
        original = instances[name]["intGridCsv"]
        if len(original) != old_w * H:
            raise MapError(f"扩展前 {name} 数据长度异常")
        # 逐行按旧跨度读，不能把旧 116 列的一维数组误当成 280 列再切片。
        grids[name] = [original[y * old_w + x] if x < 63 else 0
                       for y in range(H) for x in range(W)]
        instances[name]["__cWid"] = W
        instances[name]["intGridCsv"] = grids[name]
    level["pxWid"] = W * TS
    doc["worldGridWidth"] = W * TS
    doc["defaultLevelWidth"] = W * TS
    for definition in doc["defs"]["layers"]:
        name = definition.get("identifier")
        if name in LAYER_SPECS:
            # 仅更新数值语义定义；保留 LDtk 图层 iid、颜色选择、编辑器属性和未知字段。
            definition["intGridValues"] = _layer_def(name, LAYER_SPECS[name])["intGridValues"]

    def fill(name: str, x0: int, y0: int, x1: int, y1: int, value: int) -> None:
        if x0 < 63 or x1 >= W or y0 < 0 or y1 >= H:
            raise MapError(f"扩展写入越界或触及已认可前三房：{name} {x0},{y0}..{x1},{y1}")
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                grids[name][y * W + x] = value

    previous_rooms = _metadata(level, "RoomMetadata")
    rooms = copy.deepcopy(previous_rooms[:3]) + [
        {"room_id": "archive_sorting", "display_name": "档案分流厅", "decor_profile": "archive_sorter",
         "role": "main", "rect": [63, 6, 40, 18], "primary_landmark": "archive_sorter"},
        {"room_id": "service_checkpoint", "display_name": "维修中继站", "decor_profile": "service_bay",
         "role": "connector", "rect": [103, 12, 16, 12], "primary_landmark": "service_bench",
         "checkpoint_cell": [111, 22]},
        {"room_id": "coolant_descent", "display_name": "冷却沉降池", "decor_profile": "coolant_reservoir",
         "role": "main", "rect": [119, 9, 42, 20], "primary_landmark": "coolant_reservoir"},
        {"room_id": "freight_crossfire", "display_name": "重载交叉仓", "decor_profile": "freight_crossfire",
         "role": "main", "rect": [161, 9, 42, 20], "primary_landmark": "freight_gantry"},
        {"room_id": "uplink_checkpoint", "display_name": "上联维修站", "decor_profile": "relay_service",
         "role": "connector", "rect": [203, 17, 16, 12], "primary_landmark": "service_bench",
         "checkpoint_cell": [215, 22]},
        {"room_id": "containment_core", "display_name": "封存核心", "decor_profile": "containment_core",
         "role": "main", "rect": [219, 5, 42, 19], "primary_landmark": "containment_core"},
        {"room_id": "exit_gallery", "display_name": "撤离气闸", "decor_profile": "egress_lock",
         "role": "connector", "rect": [261, 12, 18, 12], "primary_landmark": "exit_seal"},
    ]
    fill("Collision", 63, 0, W - 1, 0, 1)
    fill("Collision", 63, H - 1, W - 1, H - 1, 1)
    fill("Collision", W - 1, 0, W - 1, H - 1, 1)
    for value, room in enumerate(rooms[3:], 4):
        x, y, width, height = room["rect"]
        fill("Rooms", x, y, x + width - 1, y + height - 1, value)
        fill("Collision", x, y, x + width - 1, y, 1)
        fill("Collision", x, y + height - 1, x + width - 1, y + height - 1, 1)
        fill("BackdropTiles", x + 1, y + 1, x + width - 2, y + height - 2, 1)

    # 分流厅：下层运货线与上层巡检线都布敌，玩家可先清任一路再绕回另一层。
    fill("Collision", 75, 20, 90, 20, 2)
    fill("Collision", 94, 22, 98, 22, 1)
    # 沉降池：入口高台接向右下行钢梯；地面没有假坑，下降后转成低处货运战。
    fill("Collision", 119, 23, 122, 23, 1)
    fill("Collision", 123, 23, 123, 23, 2)
    # 重载仓：64px 高货台切开两条射线，两侧有宽阔落点，不靠闪现才过得去。
    fill("Collision", 175, 26, 183, 28, 1)
    fill("Collision", 165, 25, 171, 25, 2)
    # 上联中继：独立钢梯连接低地面和安全补给点；检查点不直接放在战斗场中。
    fill("Collision", 214, 23, 214, 23, 2)
    fill("Collision", 215, 23, 218, 23, 1)
    # 核心：中段设备台和右侧维护步道形成双层包抄，不是加长的纯平走廊。
    fill("Collision", 233, 21, 240, 23, 1)
    fill("Collision", 245, 20, 252, 20, 2)

    for x, y, value in [
        (69, 22, 3), (84, 22, 4), (82, 19, 3), (89, 19, 4),
        (76, 22, 5), (85, 19, 5),
        (120, 22, 3), (142, 27, 3), (156, 27, 4), (148, 27, 5),
        (172, 27, 4), (179, 25, 3), (190, 27, 4), (198, 27, 3),
        (164, 27, 5), (176, 25, 5), (186, 27, 5),
        (225, 22, 3), (231, 22, 4), (236, 20, 3), (239, 20, 4),
        (249, 22, 4), (256, 22, 3),
        (228, 22, 5), (234, 20, 5), (243, 22, 5), (274, 22, 2),
    ]:
        fill("Entities", x, y, x, y, value)

    for x0, y0, x1, y1, value in [
        (73, 9, 92, 17, 4), (108, 17, 114, 21, 7),
        (136, 13, 154, 25, 8), (169, 12, 194, 22, 9),
        (215, 19, 217, 21, 7), (230, 8, 249, 18, 10), (267, 15, 275, 21, 5),
    ]:
        fill("Architecture", x0, y0, x1, y1, value)
    for x0, y0, x1, y1, value in [
        (70, 10, 94, 16, 3), (106, 16, 115, 21, 2),
        (135, 12, 157, 23, 3), (168, 12, 195, 20, 2),
        (207, 18, 217, 21, 2), (229, 7, 251, 18, 3), (266, 14, 276, 21, 2),
    ]:
        fill("BackdropTiles", x0, y0, x1, y1, value)
    for x0, y0, x1, y1, value in [
        (65, 7, 65, 15, 3), (100, 7, 100, 16, 1),
        (137, 10, 137, 17, 2), (159, 10, 159, 17, 3),
        (163, 10, 163, 18, 1), (200, 10, 200, 17, 3),
        (221, 6, 221, 13, 2), (258, 6, 258, 15, 1), (277, 13, 277, 18, 4),
    ]:
        fill("ForegroundTiles", x0, y0, x1, y1, value)
    for x, y, value in [
        (68, 18, 2), (77, 10, 2), (88, 10, 1), (98, 18, 2),
        (107, 15, 1), (114, 15, 2), (121, 16, 2), (141, 14, 1), (153, 14, 1),
        (165, 21, 2), (175, 13, 2), (188, 13, 1), (199, 21, 2),
        (206, 19, 1), (216, 18, 2), (224, 17, 2), (235, 9, 4),
        (246, 9, 1), (256, 17, 3), (265, 15, 1), (276, 15, 2),
    ]:
        fill("Lights", x, y, x, y, value)

    stairs = copy.deepcopy(_metadata(level, "StairMetadata"))
    stairs += [
        {"stair_id": "coolant_descent", "room_id": "coolant_descent",
         "bottom_cell": [134, 28], "top_cell": [124, 23], "direction": "left_up",
         "step_run_px": 32, "step_rise_px": 16, "steps": 10,
         "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False},
        {"stair_id": "uplink_rise", "room_id": "uplink_checkpoint",
         "bottom_cell": [204, 28], "top_cell": [214, 23], "direction": "right_up",
         "step_run_px": 32, "step_rise_px": 16, "steps": 10,
         "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False},
    ]
    for stair in stairs[1:]:
        x, y = stair["bottom_cell"]
        right_up = stair["direction"] == "right_up"
        for i in range(stair["steps"]):
            column = x + i if right_up else x - i - 1
            row = y - 1 - i // 2
            fill("Architecture", column, row, column, row, 6)
            fill("Traversal", column, row, column, row, 3)

    # 走线语义同时标出高低两路；不把空中插值点冒充稳定站立点。
    for x0, x1, row in [
        (63, 93, 22), (94, 98, 21), (99, 118, 22), (75, 90, 19),
        (119, 123, 22), (134, 174, 27), (175, 183, 25), (184, 203, 27),
        (165, 171, 24), (214, 232, 22), (233, 240, 20), (241, 278, 22),
        (245, 252, 19),
    ]:
        fill("Traversal", x0, row, x1, row, 1)
    for x, y in [(75, 19), (90, 19), (94, 21), (98, 21), (165, 24), (171, 24),
                 (175, 25), (183, 25), (233, 20), (240, 20), (245, 19), (252, 19)]:
        fill("Traversal", x, y, x, y, 2)
    for x, y in [(63, 22), (102, 22), (103, 22), (118, 22), (119, 22),
                 (160, 27), (161, 27), (202, 27), (203, 27), (218, 22),
                 (219, 22), (260, 22), (261, 22)]:
        fill("Traversal", x, y, x, y, 4)
    for identifier, value in [("RoomMetadata", rooms), ("StairMetadata", stairs)]:
        field = next(item for item in fields if item["__identifier"] == identifier)
        field["__value"] = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    field_def = copy.deepcopy(doc["defs"]["levelFields"][0])
    field_uid = int(doc["nextUid"])
    field_def.update({"identifier": "CampaignRevision", "uid": field_uid,
                      "doc": "扩展流程版本；再次运行不会覆盖用户后续 LDtk 编辑。"})
    doc["defs"]["levelFields"].append(field_def)
    doc["nextUid"] = field_uid + 1
    fields.append({"__identifier": "CampaignRevision", "__tile": None, "__type": "String",
                   "__value": CAMPAIGN_REVISION, "defUid": field_uid, "realEditorValues": []})
    return True


def _extend_campaign() -> None:
    doc = json.loads(LDTK_PATH.read_text(encoding="utf-8"))
    if not _apply_campaign_extension(doc):
        print("扩展流程已迁移；保留之后的 LDtk 编辑", file=sys.stderr)
        return
    _validate_and_compile(doc, "extension-validation")
    LDTK_PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("已扩展为 280×30 / 10 房间 / 20 敌 / 11 货箱；前 63 列完整保留", file=sys.stderr)


def _apply_core_cargo_spacing_fix(doc: dict[str, Any]) -> bool:
    """仅把核心入口货箱移开敌人身体；不重跑整关布局迁移。"""
    level = next(item for item in doc["levels"] if item["identifier"] == LEVEL_ID)
    fields = level["fieldInstances"]
    revisions = [field for field in fields if field["__identifier"] == "CoreCargoRevision"]
    if revisions:
        if len(revisions) != 1 or revisions[0].get("__value") != CORE_CARGO_REVISION:
            raise MapError("CoreCargoRevision 未知，拒绝覆盖后续编辑")
        return False
    if int(level["pxWid"]) != W * TS:
        raise MapError("核心货箱间距修复要求先扩展完整流程")
    values = next(item for item in level["layerInstances"]
                  if item["__identifier"] == "Entities")["intGridCsv"]
    old_index, new_index = 22 * W + 226, 22 * W + 228
    if (values[old_index], values[new_index]) == (5, 0):
        values[old_index], values[new_index] = 0, 5
    elif (values[old_index], values[new_index]) != (0, 5):
        raise MapError("核心 c226/c228 已被用户修改，拒绝覆盖或复制货箱")
    field_uid = int(doc["nextUid"])
    field_def = copy.deepcopy(doc["defs"]["levelFields"][0])
    field_def.update({"identifier": "CoreCargoRevision", "uid": field_uid,
                      "doc": "核心货箱c226→c228的单点间距修复；勿删除版本标记。"})
    doc["defs"]["levelFields"].append(field_def)
    doc["nextUid"] = field_uid + 1
    fields.append({"__identifier": "CoreCargoRevision", "__tile": None, "__type": "String",
                   "__value": CORE_CARGO_REVISION, "defUid": field_uid, "realEditorValues": []})
    return True


def _fix_core_cargo_spacing() -> None:
    doc = json.loads(LDTK_PATH.read_text(encoding="utf-8"))
    if not _apply_core_cargo_spacing_fix(doc):
        print("核心货箱间距已修复；保留后续 LDtk 编辑", file=sys.stderr)
        return
    _validate_and_compile(doc, "cargo-spacing-validation")
    LDTK_PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("仅修复核心货箱 c226→c228：左右各三格，出生不重叠", file=sys.stderr)


def _level_and_layers(doc: dict[str, Any]) -> tuple[dict[str, Any], dict[str, list[int]]]:
    levels = [level for level in doc.get("levels", []) if level.get("identifier") == LEVEL_ID]
    if len(levels) != 1:
        raise MapError(f"必须恰好有一个关卡 {LEVEL_ID}")
    level = levels[0]
    if (level.get("pxWid"), level.get("pxHei")) != (W * TS, H * TS):
        raise MapError(f"关卡尺寸必须为 {W}x{H} 格，TS={TS}")
    # IntGrid 数值不变时，语义标识也必须与编译合同一致；避免 LDtk 仍显示旧地标名，
    # 而生成数据已经悄悄换成新名称。
    definitions = doc.get("defs", {}).get("layers", [])
    def_by_name = {item.get("identifier"): item for item in definitions}
    if set(def_by_name) != set(LAYER_SPECS):
        raise MapError("LDtk layer definitions 与语义层合同不一致")
    for name, spec in LAYER_SPECS.items():
        actual_identifiers = {
            int(item.get("value", -1)): str(item.get("identifier", ""))
            for item in def_by_name[name].get("intGridValues", [])
        }
        expected_identifiers = {
            value: identifier for value, (identifier, _color) in spec.values.items()
        }
        if actual_identifiers != expected_identifiers:
            raise MapError(f"{name} IntGrid 标识与编译合同不一致")
    instances = level.get("layerInstances")
    if not isinstance(instances, list):
        raise MapError("LDtk 未内嵌 layerInstances")
    by_name = {layer.get("__identifier"): layer for layer in instances}
    if set(by_name) != set(LAYER_SPECS):
        missing = sorted(set(LAYER_SPECS) - set(by_name))
        extra = sorted(set(by_name) - set(LAYER_SPECS))
        raise MapError(f"语义层不一致；缺少={missing} 多余={extra}")
    layers: dict[str, list[int]] = {}
    for name, spec in LAYER_SPECS.items():
        layer = by_name[name]
        if layer.get("__gridSize") != TS or layer.get("__cWid") != W or layer.get("__cHei") != H:
            raise MapError(f"{name} 必须为 {W}x{H}、{TS}px IntGrid")
        values = layer.get("intGridCsv")
        if not isinstance(values, list) or len(values) != W * H:
            raise MapError(f"{name} 数据长度必须为 {W * H}")
        known = set(spec.values) | {0}
        for index, raw in enumerate(values):
            if not isinstance(raw, int) or raw not in known:
                raise MapError(f"{name} 未知值 {raw!r} @ c{index % W} r{index // W}")
        layers[name] = values
    return level, layers


def _metadata(level: dict[str, Any], identifier: str) -> Any:
    fields = level.get("fieldInstances", [])
    matches = [field for field in fields if field.get("__identifier") == identifier]
    if len(matches) != 1 or not isinstance(matches[0].get("__value"), str):
        raise MapError(f"缺少唯一字符串字段 {identifier}")
    try:
        return json.loads(matches[0]["__value"])
    except json.JSONDecodeError as exc:
        raise MapError(f"{identifier} 不是合法 JSON：{exc}") from exc


def _cell(values: list[int], x: int, y: int) -> int:
    if not (0 <= x < W and 0 <= y < H):
        return 1
    return values[y * W + x]


def _validate_rooms(room_grid: list[int], room_meta: Any) -> list[dict[str, Any]]:
    if not isinstance(room_meta, list) or not (5 <= len(room_meta) <= len(LAYER_SPECS["Rooms"].values)):
        raise MapError("RoomMetadata 房间数量超出正式语义合同")
    seen_ids: set[str] = set()
    rooms: list[dict[str, Any]] = []
    occupied: set[tuple[int, int]] = set()
    for expected_value, raw in enumerate(room_meta, 1):
        if not isinstance(raw, dict):
            raise MapError("RoomMetadata 项必须是对象")
        required = {"room_id", "display_name", "decor_profile", "role", "rect", "primary_landmark"}
        if not required.issubset(raw) or set(raw) - required - {"checkpoint_cell"}:
            raise MapError(f"RoomMetadata 字段不完整：{raw.get('room_id', '?')}")
        room_id = raw["room_id"]
        if not isinstance(room_id, str) or not room_id or room_id in seen_ids:
            raise MapError(f"room_id 必须唯一且非空：{room_id!r}")
        seen_ids.add(room_id)
        profile = raw["decor_profile"]
        if ROOM_PROFILES.get(profile) != raw["role"]:
            raise MapError(f"房间 {room_id} 的 decor_profile/role 不受支持")
        rect = raw["rect"]
        if not (isinstance(rect, list) and len(rect) == 4 and all(isinstance(v, int) for v in rect)):
            raise MapError(f"房间 {room_id} rect 必须是四整数")
        x, y, width, height = rect
        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > W or y + height > H:
            raise MapError(f"房间 {room_id} 越界")
        role = raw["role"]
        if role == "main" and not (30 <= width <= 42 and 15 <= height <= 20):
            raise MapError(f"主战斗房 {room_id} 尺寸必须为 30–42 x 15–20 格")
        if role == "connector" and not (10 <= width <= 18 and 8 <= height <= 12):
            raise MapError(f"连接区 {room_id} 尺寸必须为 10–18 x 8–12 格")
        if role == "shaft" and not (10 <= width <= 16 and 18 <= height <= 24):
            raise MapError(f"竖井 {room_id} 尺寸必须为 10–16 x 18–24 格")
        if "checkpoint_cell" in raw:
            checkpoint = raw["checkpoint_cell"]
            if (role != "connector" or not isinstance(checkpoint, list) or len(checkpoint) != 2
                    or not all(isinstance(value, int) for value in checkpoint)):
                raise MapError(f"检查点 {room_id} 必须属于安全连接房，坐标为两整数")
            if not (x <= checkpoint[0] < x + width and y <= checkpoint[1] < y + height):
                raise MapError(f"检查点 {room_id} 不在所属房间内")
        expected_cells = {(cx, cy) for cy in range(y, y + height) for cx in range(x, x + width)}
        if occupied & expected_cells:
            raise MapError(f"房间 {room_id} 与前一房间重叠")
        occupied |= expected_cells
        actual_cells = {(cx, cy) for cy in range(H) for cx in range(W)
                        if _cell(room_grid, cx, cy) == expected_value}
        if actual_cells != expected_cells:
            raise MapError(f"Rooms IntGrid 与 {room_id} 的 rect 不一致")
        rooms.append(raw)
    unknown_ids = set(room_grid) - set(range(0, len(rooms) + 1))
    if unknown_ids:
        raise MapError(f"Rooms 出现未知房间编号：{sorted(unknown_ids)}")
    return rooms


def _validate_stairs(stairs: Any, room_ids: set[str],
                     entity_cells: set[tuple[int, int]],
                     architecture: list[int], traversal: list[int],
                     collision: list[int]) -> list[dict[str, Any]]:
    if not isinstance(stairs, list) or not stairs:
        raise MapError("StairMetadata 至少需要一段正式楼梯")
    ids: set[str] = set()
    expected_semantic_cells: set[tuple[int, int]] = set()
    for stair in stairs:
        required = {"stair_id", "room_id", "bottom_cell", "top_cell", "direction",
                    "step_run_px", "step_rise_px", "steps", "collision_mode",
                    "enemy_spawns_allowed"}
        if not isinstance(stair, dict) or set(stair) != required:
            raise MapError("StairMetadata 字段不完整")
        if stair["stair_id"] in ids or stair["room_id"] not in room_ids:
            raise MapError(f"楼梯 id 重复或 room_id 未知：{stair.get('stair_id')}")
        ids.add(stair["stair_id"])
        if stair["direction"] not in {"right_up", "left_up"}:
            raise MapError(f"楼梯方向未知：{stair['direction']}")
        if (stair["step_run_px"], stair["step_rise_px"]) != (32, 16):
            raise MapError("正式开放钢梯步级必须为 32x16px")
        if stair["steps"] <= 0 or stair["steps"] % 2 != 0:
            raise MapError("楼梯级数必须为正偶数，确保回到 32px 网格")
        if stair["collision_mode"] != "one_way_heightfield" or stair["enemy_spawns_allowed"] is not False:
            raise MapError("首版楼梯必须使用单向高度场并禁止敌人刷在踏板")
        bottom = stair["bottom_cell"]
        top = stair["top_cell"]
        if not (isinstance(bottom, list) and isinstance(top, list)
                and len(bottom) == 2 and len(top) == 2
                and all(isinstance(value, int) for value in bottom + top)):
            raise MapError(f"楼梯 {stair['stair_id']} 的端点必须是二维整数格")
        x0, y0 = bottom
        x1, y1 = top
        direction_sign = 1 if stair["direction"] == "right_up" else -1
        expected_top = [x0 + direction_sign * stair["steps"],
                        y0 - stair["steps"] // 2]
        if top != expected_top:
            raise MapError(
                f"楼梯 {stair['stair_id']} 端点与 10 级 32x16 步级不一致："
                f"期望 {expected_top}，实际 {top}")
        stair_cells = {
            (x0 + i if direction_sign > 0 else x0 - i - 1,
             y0 - 1 - i // 2)
            for i in range(stair["steps"])
        }
        if expected_semantic_cells & stair_cells:
            raise MapError(f"楼梯 {stair['stair_id']} 与另一楼梯语义格重叠")
        expected_semantic_cells |= stair_cells
        min_x, max_x = sorted((x0, x1))
        min_y, max_y = sorted((y0, y1))
        if any(min_x <= x <= max_x and min_y <= y <= max_y for x, y in entity_cells):
            raise MapError(f"楼梯 {stair['stair_id']} 范围内禁止实体刷点")
        # 正式高度场必须保持开放；同一竖井不得再叠加旧 OneWay 粗平台。
        # top_cell 表示楼梯高端边界；向左升时外侧接口在边界左边一格，不覆盖踏面。
        interface_x = x1 if direction_sign > 0 else x1 - 1
        if _cell(collision, interface_x, y1) != 2:
            raise MapError(f"楼梯 {stair['stair_id']} 缺少上端 OneWay 接口 c{interface_x} r{y1}")
        for y in range(min_y, max_y + 1):
            for x in range(min_x, max_x + 1):
                # top_cell 是楼梯结束后的同高接口，不覆盖最后一级 c61 踏面。
                if _cell(collision, x, y) == 2 and (x, y) != (interface_x, y1):
                    raise MapError(f"楼梯 {stair['stair_id']} 范围残留 OneWay：c{x} r{y}")

    open_stair_value = next(
        value for value, (name, _color) in LAYER_SPECS["Architecture"].values.items()
        if name == "OpenStair")
    actual_semantic_cells = {
        (index % W, index // W)
        for index, value in enumerate(architecture) if value == open_stair_value
    }
    if actual_semantic_cells != expected_semantic_cells:
        missing = sorted(expected_semantic_cells - actual_semantic_cells)
        extra = sorted(actual_semantic_cells - expected_semantic_cells)
        raise MapError(f"Architecture.OpenStair 与 StairMetadata 不一致；缺少={missing} 多余={extra}")
    stair_rise_value = next(
        value for value, (name, _color) in LAYER_SPECS["Traversal"].values.items()
        if name == "StairRise")
    actual_traversal_cells = {
        (index % W, index // W)
        for index, value in enumerate(traversal) if value == stair_rise_value
    }
    if actual_traversal_cells != expected_semantic_cells:
        raise MapError("Traversal.StairRise 必须与正式开放楼梯语义格逐格一致")
    return stairs


def _validate_and_compile(doc: dict[str, Any], source_hash: str) -> str:
    level, layers = _level_and_layers(doc)
    collision = layers["Collision"]
    rooms = _validate_rooms(layers["Rooms"], _metadata(level, "RoomMetadata"))
    entities: list[dict[str, Any]] = []
    entity_cells: set[tuple[int, int]] = set()
    for index, value in enumerate(layers["Entities"]):
        if value == 0:
            continue
        x, y = index % W, index // W
        if (x, y) in entity_cells:
            raise MapError(f"实体格重复：c{x} r{y}")
        entity_cells.add((x, y))
        room_value = _cell(layers["Rooms"], x, y)
        if room_value <= 0 or room_value > len(rooms):
            raise MapError(f"实体不在唯一房间内：c{x} r{y}")
        # 52px 玩家/敌人至少需要三格清空；出生后下一物理帧即可落地。
        if _cell(collision, x, y + 1) not in {1, 2}:
            raise MapError(f"实体脚下不是立即地面：c{x} r{y}")
        for clear_y in (y, y - 1, y - 2):
            # 单向步道只承接下落，不是顶棚；允许主路线和货箱从它下方经过。
            if _cell(collision, x, clear_y) == 1:
                raise MapError(f"实体净空不足三格：c{x} r{y}")
        entities.append({"kind": LAYER_SPECS["Entities"].values[value][0],
                         "cell": [x, y], "room_id": rooms[room_value - 1]["room_id"]})
    counts = {value: layers["Entities"].count(value) for value in ENTITY_TO_CHAR}
    if counts[1] != 1 or counts[2] != 1:
        raise MapError(f"PlayerSpawn/Exit 必须各唯一一个，当前 {counts[1]}/{counts[2]}")
    if counts[3] < 1 or counts[4] < 1:
        raise MapError("正式第一关必须同时包含近战巡检员与枪手")
    if counts[5] < 1:
        raise MapError("正式第一关必须包含可被球棒击飞的 BatCargo")
    for cargo in [entity for entity in entities if entity["kind"] == "BatCargo"]:
        cargo_x, cargo_y = cargo["cell"]
        for enemy in [entity for entity in entities if entity["kind"] in {"Gunner", "MeleeInspector"}]:
            enemy_x, enemy_y = enemy["cell"]
            enemy_width = 44 if enemy["kind"] == "Gunner" else 42
            # 使用正式身体尺寸：箱32×36，敌人高96；一格距离仍可能横向重叠5–6px。
            if (abs(cargo_x - enemy_x) * TS < (32 + enemy_width) * 0.5
                    and cargo_y * TS > enemy_y * TS - 96
                    and cargo_y * TS - 36 < enemy_y * TS):
                raise MapError(f"货箱与敌人出生包围盒重叠：{cargo['cell']} / {enemy['cell']}")

    for room in rooms:
        if "checkpoint_cell" not in room:
            continue
        x, y = room["checkpoint_cell"]
        if _cell(collision, x, y + 1) not in {1, 2} or any(
                _cell(collision, x, yy) != 0 for yy in (y, y - 1, y - 2)):
            raise MapError(f"检查点 {room['room_id']} 必须落在三格净空的稳定地面")
        if any(entity["room_id"] == room["room_id"] and entity["kind"] in {"Gunner", "MeleeInspector"}
               for entity in entities):
            raise MapError(f"检查点房间 {room['room_id']} 不允许布置敌人")

    stairs = _validate_stairs(
        _metadata(level, "StairMetadata"),
        {room["room_id"] for room in rooms}, entity_cells,
        layers["Architecture"], layers["Traversal"], collision)
    checkpoints = checkpoint_contract.validate(doc, MapError, required=False)

    # 所有主路线格都必须有三格净空并紧邻可站立表面。
    traversal = layers["Traversal"]
    for index, value in enumerate(traversal):
        if value == 0:
            continue
        x, y = index % W, index // W
        if value == 3:
            # 半格高度场由 StairMetadata 验证，不能用整格碰撞层判断落地。
            continue
        if _cell(collision, x, y + 1) not in {1, 2}:
            raise MapError(f"Traversal 悬空：c{x} r{y}")
        if any(_cell(collision, x, clear_y) == 1 for clear_y in (y, y - 1, y - 2)):
            raise MapError(f"Traversal 净空不足三格：c{x} r{y}")

    def standable(x: int, y: int) -> bool:
        return (_cell(collision, x, y + 1) in {1, 2}
                and _cell(collision, x, y) == 0
                and all(_cell(collision, x, yy) != 1 for yy in (y - 1, y - 2)))

    # 保守运动图只使用跑跳预算，不计闪现或翻滚。
    start = next(tuple(entity["cell"]) for entity in entities if entity["kind"] == "PlayerSpawn")
    stands: list[tuple[float, float]] = [
        (float(x), float(y))
        for y in range(H - 1) for x in range(W) if standable(x, y)
    ]
    # 楼梯脚底高度含半格，换算成与普通站立格相同的“脚下表面-1格”坐标。
    for stair in stairs:
        x0, bottom_row = stair["bottom_cell"]
        direction_sign = 1 if stair["direction"] == "right_up" else -1
        for i in range(stair["steps"]):
            cell_x = x0 + i if direction_sign > 0 else x0 - i - 1
            surface_row = bottom_row - (i + 1) * 0.5
            stands.append((float(cell_x), surface_row - 1.0))
    seen = {start}
    queue = [start]
    while queue:
        x, y = queue.pop(0)
        for nx, ny in stands:
            if (nx, ny) in seen:
                continue
            dx, rise = abs(nx - x), y - ny
            if rise >= 0:
                if rise <= 1.0:
                    max_dx = 6
                elif rise <= 2.0:
                    max_dx = 5
                elif rise <= 3.0:
                    max_dx = 3
                else:
                    max_dx = -1
                allowed = dx <= max_dx
            else:
                allowed = -rise <= 8 and dx <= 6
            if allowed:
                seen.add((nx, ny))
                queue.append((nx, ny))
    unreachable = [entity for entity in entities if tuple(entity["cell"]) not in seen]
    if unreachable:
        raise MapError(f"普通跑跳不可达实体：{unreachable}")
    for room in rooms:
        if "checkpoint_cell" in room and tuple(room["checkpoint_cell"]) not in seen:
            raise MapError(f"普通跑跳不可达检查点：{room['room_id']}")
    for checkpoint in checkpoints:
        if tuple(checkpoint["cell"]) not in seen:
            raise MapError(f"普通跑跳不可达唯一运行时检查点：{checkpoint['id']}")
    for index, value in enumerate(traversal):
        if value and value != 3 and (index % W, index // W) not in seen:
            raise MapError(f"普通跑跳不可达 Traversal：c{index % W} r{index // W}")

    # 输出合成 ASCII 仅供旧运行时未来接线；LDtk 仍是唯一真源。
    rows: list[str] = []
    for y in range(H):
        chars: list[str] = []
        for x in range(W):
            char = COLLISION_TO_CHAR[_cell(collision, x, y)]
            entity_value = _cell(layers["Entities"], x, y)
            if entity_value:
                if char != ".":
                    raise MapError(f"实体与碰撞重叠：c{x} r{y}")
                char = ENTITY_TO_CHAR[entity_value]
            chars.append(char)
        rows.append("".join(chars))

    semantic_layers: dict[str, list[list[int]]] = {}
    semantic_ids: dict[str, dict[str, int]] = {}
    for name in ("Architecture", "BackdropTiles", "ForegroundTiles", "Lights", "Traversal"):
        semantic_layers[name] = [
            [index % W, index // W, value]
            for index, value in enumerate(layers[name]) if value
        ]
        semantic_ids[name] = {
            ident: value for value, (ident, _color) in LAYER_SPECS[name].values.items()
        }

    def gd(value: Any, indent: int = 0) -> str:
        pad = "\t" * indent
        if value is None:
            return "null"
        if value is True:
            return "true"
        if value is False:
            return "false"
        if isinstance(value, str):
            return json.dumps(value, ensure_ascii=False)
        if isinstance(value, (int, float)):
            return str(value)
        if isinstance(value, list):
            if not value:
                return "[]"
            return "[\n" + ",\n".join(pad + "\t" + gd(item, indent + 1) for item in value) + "\n" + pad + "]"
        if isinstance(value, dict):
            if not value:
                return "{}"
            return "{\n" + ",\n".join(
                pad + "\t" + gd(key) + ": " + gd(item, indent + 1)
                for key, item in value.items()) + "\n" + pad + "}"
        raise TypeError(type(value))

    lines = [
        "extends RefCounted", "",
        "## 正式第一关编译数据；唯一布局真源为 godot/maps/m01_protocol_quarantine.ldtk。",
        "## 由 playground/tools/gen_m01_protocol_quarantine.py 生成，禁止手改。",
        f'const SOURCE_SHA256 := "{source_hash}"',
        f"const TILE_SIZE := {TS}", f"const MAP_WIDTH := {W}", f"const MAP_HEIGHT := {H}",
        'const MAP_TEXT := """', *rows, '"""', "",
        "const ROOMS := " + gd(rooms), "",
        "const ENTITIES := " + gd(entities), "",
        "const STAIRS := " + gd(stairs), "",
        "## 每关唯一中途记录；旧房间checkpoint_cell仅保留历史布局，不重复启用。",
        "const CHECKPOINTS: Array[Dictionary] = " + gd(checkpoints), "",
        "## 稀疏层三元组的 value 语义；运行时无需反查 Python。",
        "const SEMANTIC_IDS := " + gd(semantic_ids), "",
        "const SEMANTIC_LAYERS := " + gd(semantic_layers), "",
    ]
    return "\n".join(lines)


def compile_path(path: Path = LDTK_PATH) -> str:
    raw = path.read_bytes()
    try:
        doc = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MapError(f"LDtk JSON 无法读取：{exc}") from exc
    checkpoint_contract.validate(doc, MapError)
    return _validate_and_compile(doc, hashlib.sha256(raw).hexdigest())


def _write(output: str) -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(output, encoding="utf-8", newline="\n")
    print(f"已编译：{OUTPUT_PATH}", file=sys.stderr)


def _check(output: str) -> None:
    if not OUTPUT_PATH.exists():
        raise MapError(f"缺少生成文件：{OUTPUT_PATH}")
    actual = OUTPUT_PATH.read_text(encoding="utf-8")
    if actual != output:
        raise MapError("生成数据与 LDtk 不一致；请运行 --write")
    print("--check 通过：生成数据逐字节一致", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", action="store_true", help="首次创建 LDtk；绝不覆盖")
    parser.add_argument("--rework-combat-slice", action="store_true",
                        help="一次性迁移检疫厅为球棒货运战斗线；重复运行不覆盖后续编辑")
    parser.add_argument("--extend-campaign", action="store_true",
                        help="保留前63列并扩展后段为完整十房流程；重复执行不覆盖后续编辑")
    parser.add_argument("--fix-core-cargo-spacing", action="store_true",
                        help="只将核心入口货箱c226移到c228，避免出生重叠；幂等执行")
    parser.add_argument("--add-single-checkpoint", action="store_true",
                        help="只添加唯一中途检查点元数据；保留全部图层和后续编辑，幂等")
    parser.add_argument("--write", action="store_true", help="编译独立 Godot 数据脚本")
    parser.add_argument("--check", action="store_true", help="精确校验生成文件")
    args = parser.parse_args()
    try:
        if args.seed:
            _seed_ldtk()
        if not LDTK_PATH.exists():
            raise MapError(f"缺少 {LDTK_PATH}；首次运行请加 --seed")
        if args.rework_combat_slice:
            _rework_combat_slice()
        if args.extend_campaign:
            _extend_campaign()
        if args.fix_core_cargo_spacing:
            _fix_core_cargo_spacing()
        if args.add_single_checkpoint:
            doc = json.loads(LDTK_PATH.read_text(encoding="utf-8"))
            if checkpoint_contract.add_single_checkpoint(doc, MapError):
                _validate_and_compile(doc, "single-checkpoint-migration-validation")
                LDTK_PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        output = compile_path()
        if args.write:
            _write(output)
        if args.check:
            _check(output)
        if not args.write and not args.check:
            sys.stdout.write(output)
        print("地图校验通过：正式房间、混合敌人、检查点与球棒货箱，普通跑跳贯通", file=sys.stderr)
        return 0
    except MapError as exc:
        print(f"地图校验失败：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
