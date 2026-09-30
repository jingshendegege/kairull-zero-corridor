#!/usr/bin/env python3
"""02 时差货运场：首次建档器＋只读 LDtk 编译合同。

--seed 只允许建立不存在的新图；日后在 LDtk 保存后 --write --check。
原第一关 helper 加载为隔离模块，只复用校验/schema，不执行任何旧图迁移。
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "godot/maps/m04_chrono_freight.ldtk"
OUTPUT = ROOT / "godot/generated/m04_chrono_freight_data.gd"
W, H, TS = 460, 36, 32
LEVEL_ID = "M04_ChronoFreight"
DEFENDER_REVISION = "chrono_defender_spacing_v1"
MULTILEVEL_REVISION = "chrono_upper_galleries_v1"

spec = importlib.util.spec_from_file_location("_m04_map_contract", Path(__file__).with_name("gen_m01_protocol_quarantine.py"))
base = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = base
spec.loader.exec_module(base)
base.W, base.H, base.LEVEL_ID = W, H, LEVEL_ID
base.LAYER_SPECS = copy.deepcopy(base.LAYER_SPECS)

# 每个战斗房都有两只明确对应弹道的货箱；连接区不堆放战斗用品。
ROOM_SPECS = [
    ("freight_entry", "卸货闸口", "safe_entry", 1, 16, 32, 0),
    ("rail_uplink", "货轨上联", "freight_crossfire", 17, 40, 32, 9),
    ("laser_inspection", "光栅校验", "quarantine_scanner", 57, 38, 27, 2),
    ("split_sorting", "双层分拣", "archive_sorter", 95, 40, 27, 4),
    ("quiet_service", "静音维修间", "service_bay", 135, 16, 27, 7),
    ("press_foundry", "冲压车间", "freight_crossfire", 151, 40, 32, 9),
    ("coolant_lower", "冷却下沉池", "coolant_reservoir", 191, 40, 32, 8),
    ("cross_cargo", "交叉转运仓", "freight_crossfire", 231, 40, 32, 9),
    ("safe_observatory", "安全观察间", "relay_service", 271, 16, 27, 7),
    ("sniper_bridge", "高架瞄准桥", "archive_sorter", 287, 40, 27, 4),
    ("pump_descent", "泵房下行线", "coolant_reservoir", 327, 40, 32, 8),
    ("uplink_rise", "上行搬运道", "freight_crossfire", 367, 40, 32, 9),
    ("terminal_crossfire", "终端封锁线", "containment_core", 407, 40, 27, 10),
    ("freight_exit", "货运气闸", "egress_lock", 447, 12, 27, 5),
]
base.LAYER_SPECS["Rooms"] = base.LayerSpec(2, {
    index: (room[0], ["#557B86", "#796C58", "#497C86", "#985A70"][index % 4])
    for index, room in enumerate(ROOM_SPECS, 1)
}, 0.18)


def iid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "kairull:m04:" + label))


base._iid = iid


def room_metadata() -> list[dict]:
    result = []
    for room_id, title, profile, x, width, bottom, architecture in ROOM_SPECS:
        role = base.ROOM_PROFILES[profile]
        height = 10 if role == "connector" else 20
        result.append({"room_id": room_id, "display_name": title,
                       "decor_profile": profile, "role": role,
                       "rect": [x, bottom - height + 1, width, height],
                       "primary_landmark": "freight_" + str(architecture)})
    return result


STAIRS = [
    ("rail_rise", "rail_uplink", 44, 32, 54, 27, "right_up"),
    ("foundry_descent", "press_foundry", 179, 32, 169, 27, "left_up"),
    ("cargo_rise", "cross_cargo", 250, 32, 260, 27, "right_up"),
    ("pump_descent", "pump_descent", 353, 32, 343, 27, "left_up"),
    ("uplink_rise", "uplink_rise", 389, 32, 399, 27, "right_up"),
]
PLATFORMS = [(104, 111, 24), (114, 130, 21), (201, 211, 29),
             (290, 298, 24), (301, 321, 21), (424, 434, 24)]
# 格坐标末项是脚下表面行；敌人在开阔平面，不在踏面和接缝生成。
ENEMIES = [
    (23, 32, 3), (34, 32, 4), (40, 32, 3),
    (62, 27, 3), (76, 27, 4), (88, 27, 3),
    (109, 24, 3), (122, 21, 4), (120, 27, 3), (129, 27, 4),
    (162, 27, 4), (166, 27, 3), (186, 32, 3), (189, 32, 4),
    (200, 32, 3), (207, 29, 4), (217, 32, 4), (222, 32, 3),
    (240, 32, 4), (247, 32, 3), (262, 27, 3), (265, 27, 4),
    (295, 27, 3), (313, 21, 4), (315, 27, 3), (324, 27, 4),
    (337, 27, 4), (340, 27, 3), (359, 32, 3), (361, 32, 4),
    (376, 32, 3), (387, 32, 4), (402, 27, 3), (404, 27, 4),
    (416, 27, 4), (429, 24, 4), (436, 27, 3), (443, 27, 4),
]
CARGO = [(20, 32), (30, 32), (59, 27), (82, 27), (98, 27), (118, 21),
         (154, 27), (182, 32), (194, 32), (214, 32), (234, 32), (244, 32),
         (290, 27), (307, 21), (330, 27), (356, 32), (370, 32), (384, 32),
         (410, 27), (426, 24)]
EXTRA_DEFENDERS = [(189, 32, 4), (217, 32, 4), (262, 27, 3),
                   (324, 27, 4), (359, 32, 3), (404, 27, 4)]
UPPER_MOVES = [((101, 27, 4), (122, 21, 4)), ((112, 24, 3), (109, 24, 3)),
               ((106, 24, 5), (118, 21, 5)), ((305, 24, 4), (313, 21, 4)),
               ((299, 24, 5), (307, 21, 5))]


def stairs_metadata() -> list[dict]:
    return [{"stair_id": key, "room_id": room, "bottom_cell": [bx, by],
             "top_cell": [tx, ty], "direction": direction,
             "step_run_px": 32, "step_rise_px": 16, "steps": 10,
             "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False}
            for key, room, bx, by, tx, ty, direction in STAIRS]


def owner(x: int) -> str:
    return next(room[0] for room in ROOM_SPECS if room[3] <= x < room[3] + room[4])


def tactical_metadata() -> list[dict]:
    result = []
    for index, (x, floor, purpose) in enumerate([
        (55, 27, "光栅后的枪手线：投到枪手脚前，烟内换位；也可留下给双层分拣"),
        (137, 27, "维修间补给：冲压车间枪手线先遮视，再利用时停过闸"),
        (227, 32, "转运前补给：交叉货箱线需要接近时烟幕覆盖低路"),
        (281, 27, "狙击桥前补给：向桥中央抛烟，可与上层维护步道互换路线"),
        (365, 32, "上行前补给：烟内挥棒起箱，不要求先等满时间能量"),
        (405, 27, "最后火线补给：对准终端狙击线抛烟，保护最后一段接近"),
    ], 1):
        result.append({"id": f"smoke_{index}", "type": "smoke_pickup",
                       "pos": [x * TS + 16, floor * TS - 0.1], "room_id": owner(x),
                       "purpose": purpose, "solutions": ["向目标线抛烟并在烟中推进", "保留烟雾，先用货箱或翻滚清线"]})
    for index, (x, floor, span, purpose) in enumerate([
        (67, 27, 128, "短光栅：翻滚低身穿过；或冻结光栅后绕/冲"),
        (210, 32, 128, "冷却池高路出口：从维护步道跳下绕过束线或贴地翻滚"),
        (377, 32, 160, "上行搬运前节奏检查：可观察关闭窗，不强迫消耗时停"),
    ], 1):
        result.append({"id": f"laser_{index}", "type": "laser_gate",
                       "pos": [x * TS, floor * TS - 54], "span": span,
                       "floor_y": floor * TS, "height": 54, "room_id": owner(x),
                       "purpose": purpose, "solutions": ["翻滚降低受击框从束线下方穿过", "警示时停/等待休止窗后直接跑过"]})
    for index, (x, floor) in enumerate([(157, 27), (331, 27)], 1):
        result.append({"id": f"press_{index}", "type": "press",
                       "pos": [x * TS, floor * TS - 192], "width": 64,
                       "floor_y": floor * TS, "room_id": owner(x),
                       "purpose": "冲压口前留平地和货箱，不在楼梯踏面叠机关",
                       "solutions": ["提前冻结冲压节拍后通过", "观察回程安全窗，直接跑或冲刺过去"]})
    for index, (x, hard_only) in enumerate([(321, True), (441, False)], 1):
        result.append({"id": f"sniper_{index}", "type": "auto_sniper",
                       "pos": [x * TS + 16, 27 * TS - 0.1], "direction": [-1, 0],
                       "range": 992, "hard_only": hard_only, "room_id": owner(x),
                       "purpose": "后段才出现的慢速预警/高速弹道，近侧有烟雾和可选上路",
                       "solutions": ["预警时抛烟，进入烟中避枪", "翻滚穿过高弹线，或用时停跨线/维护步道换高度",
                                     "杀清本房小兵后狙击机关停机，无需破坏炮台"]})
    for index, x in enumerate([112, 299], 1):
        result.append({"id": f"lift_{index}", "type": "freight_lift",
                       "pos": [x * TS + 16, 27 * TS], "top_y": 21 * TS,
                       "width": 96, "height": 12, "travel_time": 2.8, "dwell": 1.2,
                       "room_id": owner(x), "purpose": "下层货运线与192px高上廊之间的可乘货梯，绕后击飞上层货箱",
                       "solutions": ["乘升降货梯进入上层连廊，从侧面接近高位枪手",
                                     "不等电梯，沿左侧96px中继步道分两次普通跳跃上廊"]})
    return result


def seed_document() -> dict:
    grids = {name: base._blank() for name in base.LAYER_SPECS}
    fill, put = base._fill, base._put
    collision = grids["Collision"]
    for x0, y0, x1, y1 in [(0, 0, W - 1, 0), (0, H - 1, W - 1, H - 1),
                           (0, 0, 0, H - 1), (W - 1, 0, W - 1, H - 1)]:
        fill(collision, x0, y0, x1, y1, 1)
    for value, (room, raw) in enumerate(zip(room_metadata(), ROOM_SPECS), 1):
        x, y, width, height = room["rect"]
        right, bottom = x + width - 1, y + height - 1
        fill(grids["Rooms"], x, y, right, bottom, value)
        fill(collision, x, y, right, y, 1)
        fill(collision, x, bottom, right, bottom, 1)
        fill(grids["BackdropTiles"], x + 1, y + 1, right - 1, bottom - 1, 1)
        fill(grids["Traversal"], x, bottom - 1, right, bottom - 1, 1)
        # 大型单一地标+少量近景框件，避免整房重复小装饰和满屏管线。
        if raw[6]:
            fill(grids["Architecture"], x + 4, y + 3, min(right - 3, x + width // 2 + 3),
                 bottom - 5, raw[6])
            fill(grids["BackdropTiles"], x + 4, y + 3, min(right - 3, x + width // 2 + 3),
                 bottom - 6, 3 if value % 2 else 2)
        for light_x in range(x + 3, right - 1, 11):
            put(grids["Lights"], light_x, y + 1, 1 + value % 3)
        if room["role"] == "main":
            fill(grids["ForegroundTiles"], x + 1, y + 1, x + 1, y + 6, 3)
            fill(grids["ForegroundTiles"], right - 1, y + 1, right - 1, y + 7, 2)

    # 高低差全部由正式十级高度场连接；没有覆盖踏面的粗格兜底平台。
    for stair in stairs_metadata():
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        room = next(r for r in room_metadata() if r["room_id"] == stair["room_id"])
        x, y, width, _ = room["rect"]
        right_up = stair["direction"] == "right_up"
        raised_start, raised_end = (tx, x + width - 1) if right_up else (x, tx - 1)
        fill(collision, raised_start, ty, raised_end, by, 1)
        fill(grids["Traversal"], raised_start, by - 1, raised_end, by - 1, 0)
        fill(grids["Traversal"], raised_start, ty - 1, raised_end, ty - 1, 1)
        put(collision, tx if right_up else tx - 1, ty, 2)
        for i in range(10):
            sx = bx + i if right_up else bx - i - 1
            sy = by - 1 - i // 2
            put(grids["Architecture"], sx, sy, 6)
            # 梯下不能再保留虚假的主路线导航；玩家应真正走在外露踏面。
            put(grids["Traversal"], sx, by - 1, 0)
            put(grids["Traversal"], sx, sy, 3)
    for start, end, floor in PLATFORMS:
        fill(collision, start, floor, end, floor, 2)
        fill(grids["Traversal"], start, floor - 1, end, floor - 1, 1)
    # 双层房的机器移到上方一侧，桥下只暗化空腔rows22–23，不遮下路的站立头部。
    for rx, right, upper_left, upper_right in [(95, 134, 114, 130), (287, 326, 301, 321)]:
        fill(grids["Architecture"], rx, 9, right, 26, 0)
        fill(grids["Architecture"], rx + 3, 11, rx + 12, 17, 4)
        fill(grids["BackdropTiles"], upper_left, 22, upper_right, 23, 4)
        for x in [upper_left, upper_right - 2]:
            put(grids["Lights"], x, 18, 2)
    for x, floor, value in [(4, 32, 1), (454, 27, 2)] + ENEMIES:
        put(grids["Entities"], x, floor - 1, value)
    for x, floor in CARGO:
        put(grids["Entities"], x, floor - 1, 5)

    # 仅复用 JSON 外壳字段；不会读、写或迁移现有第一关 LDtk。
    doc = {
        "__header__": {"fileType": "LDtk Project JSON", "app": "LDtk", "doc": "https://ldtk.io/json",
                       "schema": "https://ldtk.io/files/JSON_SCHEMA.json", "appVersion": "1.5.3",
                       "appAuthor": "Sebastien 'deepnight' Benard", "url": "https://ldtk.io"},
        "iid": iid("project"), "jsonVersion": "1.5.3", "appBuildId": 473703,
        "nextUid": 100, "identifierStyle": "Capitalize", "toc": [], "worldLayout": "Free",
        "worldGridWidth": W * TS, "worldGridHeight": H * TS,
        "defaultLevelWidth": W * TS, "defaultLevelHeight": H * TS,
        "defaultPivotX": 0, "defaultPivotY": 0, "defaultGridSize": TS,
        "defaultEntityWidth": TS, "defaultEntityHeight": TS,
        "bgColor": "#0D151D", "defaultLevelBgColor": "#0D151D",
        "minifyJson": False, "externalLevels": False, "exportTiled": False,
        "simplifiedExport": False, "imageExportMode": "None", "exportLevelBg": True,
        "pngFilePattern": None, "backupOnSave": True, "backupLimit": 10,
        "backupRelPath": None, "levelNamePattern": "Level_%idx", "tutorialDesc": None,
        "customCommands": [], "flags": [], "worlds": [], "dummyWorldIid": iid("world"),
        "defs": {"layers": [base._layer_def(name, spec) for name, spec in base.LAYER_SPECS.items()],
                 "entities": [], "tilesets": [], "enums": [], "externalEnums": [], "levelFields": []},
        "levels": [{"identifier": LEVEL_ID, "iid": iid("level"), "uid": 1,
                    "worldX": 0, "worldY": 0, "worldDepth": 0,
                    "pxWid": W * TS, "pxHei": H * TS, "__bgColor": "#0D151D", "bgColor": None,
                    "useAutoIdentifier": False, "bgRelPath": None, "bgPos": None,
                    "bgPivotX": 0, "bgPivotY": 0, "__smartColor": "#6DE5F0", "__bgPos": None,
                    "externalRelPath": None, "fieldInstances": [], "__neighbours": [],
                    "layerInstances": [base._layer_instance(name, spec, grids[name])
                                       for name, spec in reversed(list(base.LAYER_SPECS.items()))]}],
    }
    for uid, (name, metadata) in enumerate([
        ("RoomMetadata", room_metadata()), ("StairMetadata", stairs_metadata()),
        ("TacticalObjects", tactical_metadata()), ("EncounterBoundaries", [4, 8]),
        ("DefenderRevision", DEFENDER_REVISION),
        ("MultilevelRevision", MULTILEVEL_REVISION),
    ], 31):
        doc["defs"]["levelFields"].append({
            "identifier": name, "doc": "JSON：时差货运场运行合同；保持中文用途说明。",
            "__type": "String", "uid": uid, "type": "String", "isArray": False,
            "canBeNull": False, "defaultOverride": None, "editorDisplayMode": "ValueOnly",
            "editorDisplayPos": "Above", "editorLinkStyle": "ZigZag", "editorDisplayScale": 1,
            "editorAlwaysShow": True, "editorShowInWorld": True, "editorCutLongValues": False,
            "editorTextSuffix": None, "editorTextPrefix": None, "useForSmartColor": False})
        doc["levels"][0]["fieldInstances"].append({"__identifier": name, "__tile": None,
            "__type": "String", "__value": json.dumps(metadata, ensure_ascii=False),
            "defUid": uid, "realEditorValues": []})
    base.checkpoint_contract.add_single_checkpoint(doc, base.MapError)
    return doc


def augment_defenders(doc: dict) -> bool:
    """可审计的六点加防：只添空实体格，保留LDtk其他层、字段和已有32敌位置。

    版本标记使再次运行成为只读，不能以迁移名义覆盖用户后续地图编辑。
    """
    level, _ = base._level_and_layers(doc)
    if any(field["__identifier"] == "DefenderRevision" for field in level["fieldInstances"]):
        if base._metadata(level, "DefenderRevision") != DEFENDER_REVISION:
            raise base.MapError("未知防守版本，拒绝覆盖用户地图")
        return False
    entities = next(layer for layer in level["layerInstances"] if layer["__identifier"] == "Entities")["intGridCsv"]
    for x, floor, value in EXTRA_DEFENDERS:
        index = (floor - 1) * W + x
        if entities[index] != 0:
            raise base.MapError(f"新增守点c{x}/r{floor - 1}已被用户实体占用，拒绝覆盖")
        entities[index] = value
    template = copy.deepcopy(doc["defs"]["levelFields"][0])
    template.update({"identifier": "DefenderRevision", "uid": 35,
                     "doc": "六处独立防线加兵版本；只改变Entities，不重铺已有地形。"})
    doc["defs"]["levelFields"].append(template)
    level["fieldInstances"].append({"__identifier": "DefenderRevision", "__tile": None,
        "__type": "String", "__value": json.dumps(DEFENDER_REVISION), "defUid": 35,
        "realEditorValues": []})
    # 先完整校验副本；任何新增点与货箱、地形冲突，调用方都不会写盘。
    compile_document(doc, "defender-migration-validation")
    return True


def upgrade_multilevel(doc: dict) -> bool:
    """只升级双层分拣/狙击桥：保持38敌/20箱，移动5处守点，加入两座可替代货梯。"""
    level, _ = base._level_and_layers(doc)
    if any(field["__identifier"] == "MultilevelRevision" for field in level["fieldInstances"]):
        if base._metadata(level, "MultilevelRevision") != MULTILEVEL_REVISION:
            raise base.MapError("未知多层版本，拒绝覆盖用户地图")
        return False
    layers = {layer["__identifier"]: layer["intGridCsv"] for layer in level["layerInstances"]}

    def fill(name: str, x0: int, y0: int, x1: int, y1: int, value: int) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                layers[name][y * W + x] = value

    # 仅移除旧的两条96px短平台，地面和整个房间碰撞都不重置。
    for start, end in [(104, 118), (298, 309)]:
        fill("Collision", start, 24, end, 24, 0)
        fill("Traversal", start, 23, end, 23, 0)
    for start, end, floor in PLATFORMS:
        if 95 <= start <= 134 or 287 <= start <= 326:
            fill("Collision", start, floor, end, floor, 2)
            fill("Traversal", start, floor - 1, end, floor - 1, 1)
    for old, new in UPPER_MOVES:
        ox, ofloor, value = old
        nx, nfloor, _ = new
        if layers["Entities"][(ofloor - 1) * W + ox] != value:
            raise base.MapError(f"上廊迁移旧实体c{ox}已由用户修改，拒绝覆盖")
        if layers["Entities"][(nfloor - 1) * W + nx] != 0:
            raise base.MapError(f"上廊目标实体c{nx}已被占用，拒绝覆盖")
        layers["Entities"][(ofloor - 1) * W + ox] = 0
        layers["Entities"][(nfloor - 1) * W + nx] = value
    for rx, right, upper_left, upper_right in [(95, 134, 114, 130), (287, 326, 301, 321)]:
        fill("Architecture", rx, 9, right, 26, 0)
        fill("Architecture", rx + 3, 11, rx + 12, 17, 4)
        fill("BackdropTiles", upper_left, 22, upper_right, 23, 4)
        for x in [upper_left, upper_right - 2]:
            fill("Lights", x, 18, x, 18, 2)
    field = next(f for f in level["fieldInstances"] if f["__identifier"] == "TacticalObjects")
    tactical = json.loads(field["__value"])
    tactical.extend(item for item in tactical_metadata() if item["type"] == "freight_lift")
    field["__value"] = json.dumps(tactical, ensure_ascii=False)
    template = copy.deepcopy(doc["defs"]["levelFields"][0])
    template.update({"identifier": "MultilevelRevision", "uid": 36,
                     "doc": "双层连廊/可乘货梯版本；保留普通两段跳备用路线。"})
    doc["defs"]["levelFields"].append(template)
    level["fieldInstances"].append({"__identifier": "MultilevelRevision", "__tile": None,
        "__type": "String", "__value": json.dumps(MULTILEVEL_REVISION), "defUid": 36,
        "realEditorValues": []})
    compile_document(doc, "multilevel-migration-validation")
    return True


def validate_tactical(doc: dict) -> tuple[list[dict], list[int]]:
    level, layers = base._level_and_layers(doc)
    rooms = base._metadata(level, "RoomMetadata")
    tactical = base._metadata(level, "TacticalObjects")
    boundaries = base._metadata(level, "EncounterBoundaries")
    ids = set()
    counts = {kind: 0 for kind in ("smoke_pickup", "laser_gate", "press", "auto_sniper", "freight_lift")}
    for item in tactical:
        if item.get("type") not in counts or not item.get("id") or item["id"] in ids:
            raise base.MapError("战术对象 type/id 无效或重复")
        ids.add(item["id"])
        counts[item["type"]] += 1
        if not item.get("purpose") or len(item.get("solutions", [])) < 2:
            raise base.MapError("每个战术对象必须说明用途和两种解法")
        pos = item.get("pos", [])
        if len(pos) != 2 or not (0 < pos[0] < W * TS and 0 < pos[1] < H * TS):
            raise base.MapError("战术对象世界坐标越界")
        x, y = int(pos[0] // TS), int(pos[1] // TS)
        room_value = base._cell(layers["Rooms"], x, y)
        if not room_value or rooms[room_value - 1]["room_id"] != item.get("room_id"):
            raise base.MapError("战术对象必须属于唯一声明房间")
        if item["type"] == "smoke_pickup":
            if base._cell(layers["Collision"], x, y + 1) not in {1, 2}:
                raise base.MapError("烟雾补给必须有脚下立即地面")
        if item["type"] == "laser_gate":
            if item.get("height", 0) < 48 or not 96 <= item.get("span", 0) <= 192:
                raise base.MapError("光栅必须为翻滚保留身体净空且不是超长死区")
        if item["type"] == "auto_sniper" and room_value < 10:
            raise base.MapError("狙击机关只能位于后段困难房")
        if item["type"] == "freight_lift":
            if pos[1] - item.get("top_y", pos[1]) < 192 or item.get("width", 0) < 96:
                raise base.MapError("货梯必须连接真正192px以上双层，并提供96px宽落脚面")
    if not 5 <= counts["smoke_pickup"] <= 7 or counts["auto_sniper"] > 2:
        raise base.MapError("烟雾/狙击超出稀疏预算")
    if not 4 <= counts["laser_gate"] + counts["press"] <= 6:
        raise base.MapError("机关超出稀疏预算")
    if any(field["__identifier"] == "MultilevelRevision" for field in level["fieldInstances"]) and counts["freight_lift"] != 2:
        raise base.MapError("双层版本必须保留两座可乘货梯，不能无声丢失接线")
    if len(boundaries) != 2 or any(not 0 <= index < len(rooms) for index in boundaries):
        raise base.MapError("遭遇分段需要两个有效安全间")
    for index in boundaries:
        if rooms[index]["role"] != "connector" or "checkpoint_cell" in rooms[index]:
            raise base.MapError("遭遇边界是喘息区，不是中途记录点")
    if any("checkpoint_cell" in room for room in rooms):
        raise base.MapError("本关只用CheckpointMetadata，禁止旧checkpoint_cell重复创建中途记录点")
    return tactical, boundaries


def compile_document(doc: dict, source_hash: str) -> str:
    tactical, boundaries = validate_tactical(doc)
    base.checkpoint_contract.validate(doc, base.MapError)
    result = base._validate_and_compile(doc, source_hash)
    result = result.replace("正式第一关编译数据", "02 时差货运场编译数据")
    result = result.replace("m01_protocol_quarantine", "m04_chrono_freight")
    # JSON 只有这两个轻量元数据合同；布尔值与 GDScript 同形，不需要临时资源。
    result += "\n## 坐标为世界像素；每项附用途与可选解法，不依靠遍地堆放道具。\n"
    result += "const TACTICAL_OBJECTS: Array[Dictionary] = " + json.dumps(tactical, ensure_ascii=False, indent=2) + "\n"
    result += "## 仅控制后段敌人唤醒；无治疗、复活点或存档含义。\n"
    result += "const ENCOUNTER_BOUNDARIES: Array[int] = " + json.dumps(boundaries) + "\n"
    return result


def compile_path(path: Path = SOURCE) -> str:
    raw = path.read_bytes()
    return compile_document(json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", action="store_true")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--augment-defenders", action="store_true",
                        help="只为现有新关的六处空守点增兵，幂等，不覆盖已有布局")
    parser.add_argument("--upgrade-multilevel", action="store_true",
                        help="双层分拣/狙击桥升级192px上廊和两座货梯，幂等迁移")
    parser.add_argument("--add-single-checkpoint", action="store_true",
                        help="只追加唯一中途记录点JSON元数据，不重排地图")
    args = parser.parse_args()
    try:
        if args.seed:
            if SOURCE.exists():
                raise base.MapError("拒绝覆盖已存在的时差货运场 LDtk；请使用编辑器保存")
            SOURCE.write_text(json.dumps(seed_document(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.augment_defenders:
            doc = json.loads(SOURCE.read_text(encoding="utf-8"))
            if augment_defenders(doc):
                SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.upgrade_multilevel:
            doc = json.loads(SOURCE.read_text(encoding="utf-8"))
            if upgrade_multilevel(doc):
                SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.add_single_checkpoint:
            doc = json.loads(SOURCE.read_text(encoding="utf-8"))
            if base.checkpoint_contract.add_single_checkpoint(doc, base.MapError):
                compile_document(doc, "single-checkpoint-migration-validation")
                SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        compiled = compile_path()
        if args.write:
            OUTPUT.write_text(compiled, encoding="utf-8")
        if args.check:
            if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != compiled:
                raise base.MapError("LDtk 与运行数据不同步；请先 --write")
        print("M04_MAP_RESULT: PASS | 460x36 | 14 rooms | 38 enemies | 20 cargo | 6 smoke | 5 hazards | 2 snipers | 2 lifts")
        return 0
    except (OSError, ValueError, base.MapError) as exc:
        print("M04_MAP_RESULT: FAIL | " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
