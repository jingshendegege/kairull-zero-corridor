"""三关唯一中途检查点：LDtk纯元数据迁移与几何/清场前提合同，不重建任何地图层。"""
from __future__ import annotations

import copy
import json
from typing import Any

REVISION = "one_checkpoint_per_level_v1"
FIELD = "CheckpointMetadata"
REVISION_FIELD = "SingleCheckpointRevision"
# cell沿用实体脚底约定：world=(c*32+16,(r+1)*32-0.1)，不是脚下地板格。
DEFAULTS = {
    "M01_ProtocolQuarantine": {"id": "m01_coolant_mid", "room_index": 5,
        "cell": [154, 27], "required_clear_rooms": [1, 3, 5]},
    "M04_ChronoFreight": {"id": "m04_observatory_mid", "room_index": 8,
        "cell": [278, 26], "required_clear_rooms": [1, 2, 3, 5, 6, 7]},
    "M05_VerticalFreight": {"id": "m05_hub_after_lower", "room_index": 0,
        "cell": [71, 50], "required_clear_rooms": [3, 4, 5, 6, 7, 8]},
    # 04 排风脊线：中继检修站，前三个战斗房（扇阵/天窗廊/冷却塔）全清后启用
    "M06_ExhaustRidge": {"id": "m06_relay_mid", "room_index": 4,
        "cell": [150, 34], "required_clear_rooms": [1, 2, 3]},
    # 05 节拍广播塔：候场室，清完后台走廊后启用（Boss 战失败从这里重来）
    "M07_BeatTower": {"id": "m07_green_room", "room_index": 1,
        "cell": [29, 22], "required_clear_rooms": [0]},
}


def _metadata(level: dict, name: str, error_type: type[Exception], optional: bool = False) -> Any:
    entries = [field for field in level.get("fieldInstances", []) if field.get("__identifier") == name]
    if optional and not entries:
        return None
    if len(entries) != 1 or not isinstance(entries[0].get("__value"), str):
        raise error_type(f"检查点合同缺少唯一字符串字段 {name}")
    try:
        return json.loads(entries[0]["__value"])
    except json.JSONDecodeError as exc:
        raise error_type(f"检查点字段 {name} 不是合法JSON") from exc


def _intersects(first: tuple[float, float, float, float], second: tuple[float, float, float, float]) -> bool:
    ax, ay, aw, ah = first
    bx, by, bw, bh = second
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by


def validate(doc: dict, error_type: type[Exception] = ValueError, *, required: bool = True) -> list[dict]:
    """完整站立净空、静态支撑和条件安全；没有激活前提的开局点不能冒充中途记录。"""
    level = doc["levels"][0]
    checkpoints = _metadata(level, FIELD, error_type, optional=not required)
    if checkpoints is None:
        return [] # 仅给首次旧seed/其他迁移的中间内存文档使用；正式compile_path要求存在。
    definitions = [entry for entry in doc["defs"]["levelFields"] if entry.get("identifier") == FIELD]
    instance = next(entry for entry in level["fieldInstances"] if entry.get("__identifier") == FIELD)
    if (len(definitions) != 1 or definitions[0].get("__type") != "String"
            or definitions[0].get("uid") != instance.get("defUid")):
        raise error_type("检查点字段schema定义/uid必须唯一匹配，拒绝重复或半迁移状态")
    revision = _metadata(level, REVISION_FIELD, error_type, optional=True)
    if revision is not None and revision != REVISION:
        raise error_type("未知单检查点版本，拒绝编译未识别的用户迁移")
    if not isinstance(checkpoints, list) or len(checkpoints) != 1:
        raise error_type("每张正式地图必须恰好一个运行时检查点")
    checkpoint = checkpoints[0]
    if not isinstance(checkpoint, dict) or set(checkpoint) != {"id", "room_index", "cell", "required_clear_rooms"}:
        raise error_type("检查点只接受id/room_index/cell/required_clear_rooms字段")
    if not isinstance(checkpoint["id"], str) or not checkpoint["id"].strip():
        raise error_type("检查点需要稳定非空id")
    rooms = _metadata(level, "RoomMetadata", error_type)
    room_index = checkpoint["room_index"]
    if type(room_index) is not int or not 0 <= room_index < len(rooms):
        raise error_type("检查点room_index越界")
    cell = checkpoint["cell"]
    if not isinstance(cell, list) or len(cell) != 2 or any(type(v) is not int for v in cell):
        raise error_type("检查点cell必须是两个整数")
    x, y = cell
    width, height = level["pxWid"] // 32, level["pxHei"] // 32
    if not (1 <= x < width - 1 and 2 <= y < height - 1):
        raise error_type("检查点位置越出稳定站立范围")
    layers = {layer["__identifier"]: layer["intGridCsv"] for layer in level["layerInstances"]}
    if layers["Rooms"][y * width + x] != room_index + 1:
        raise error_type("检查点位置与room_index不属于同一个房间")
    prerequisites = checkpoint["required_clear_rooms"]
    if (not isinstance(prerequisites, list) or not prerequisites
            or any(type(index) is not int or not 0 <= index < len(rooms) for index in prerequisites)
            or len(set(prerequisites)) != len(prerequisites)):
        raise error_type("检查点必须有不重复的有效required_clear_rooms，不能开局无条件存档")
    expected = DEFAULTS.get(level["identifier"])
    if expected is not None and sorted(prerequisites) != expected["required_clear_rooms"]:
        raise error_type("检查点清场前提必须保留约定半程战斗房，不得跳过未清区域")
    enemy_counts = [0] * len(rooms)
    for index, value in enumerate(layers["Entities"]):
        if value in (3, 4):
            owner = layers["Rooms"][index] - 1
            if 0 <= owner < len(rooms):
                enemy_counts[owner] += 1
    if any(rooms[index]["role"] != "main" or enemy_counts[index] == 0 for index in prerequisites):
        raise error_type("检查点required_clear_rooms只能引用真实有敌战斗房")
    own_room = rooms[room_index]
    if own_room["role"] not in ("connector", "main"):
        raise error_type("检查点不能设在楼梯井/货梯井")
    if own_room["role"] == "main" and room_index not in prerequisites:
        raise error_type("战斗房检查点必须要求本房全清后才安全激活")
    if own_room["role"] == "connector" and enemy_counts[room_index]:
        raise error_type("检查点安全连接房不允许布置敌人")
    collision = layers["Collision"]
    for cx in range(x - 1, x + 2):
        if collision[(y + 1) * width + cx] not in (1, 2):
            raise error_type("检查点必须有三格宽稳定静态地面，不能靠移动货梯支撑")
        if any(collision[cy * width + cx] != 0 for cy in (y, y - 1, y - 2)):
            raise error_type("检查点必须有三格高完整站立净空")
    feet_x, feet_y = x * 32 + 16, (y + 1) * 32
    beacon_bounds = (feet_x - 24, feet_y - 94, 48, 94)
    for index, kind in enumerate(layers["Entities"]):
        if not kind:
            continue
        ex, ey = (index % width) * 32 + 16, (index // width + 1) * 32
        entity_width, entity_height = (44, 96) if kind in (3, 4) else (32, 36) if kind == 5 else (22, 82)
        if _intersects(beacon_bounds, (ex - entity_width / 2, ey - entity_height, entity_width, entity_height)):
            raise error_type("检查点与玩家/敌人/货箱/出口实体出生包围盒重叠")
    stairs = _metadata(level, "StairMetadata", error_type)
    for stair in stairs:
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        stair_bounds = (min(bx, tx) * 32, ty * 32 - 94, abs(tx - bx) * 32, (by - ty) * 32 + 94)
        if _intersects(beacon_bounds, stair_bounds):
            raise error_type("检查点不能落在楼梯踏面或其站立通道")
    tactical = _metadata(level, "TacticalObjects", error_type, optional=True) or []
    for item in tactical:
        kind = item["type"]
        px, py = item["pos"]
        bounds = None
        if kind == "freight_lift":
            span = item.get("width", 96)
            bounds = (px - span / 2 - 8, item["top_y"] - 94, span + 16, py - item["top_y"] + 114)
        elif kind == "laser_gate":
            bounds = (px, py - 3, item.get("span", 160), 6)
        elif kind == "press":
            bounds = (px, py, item.get("width", 64), item["floor_y"] - py)
        elif kind == "auto_sniper":
            bounds = (px - 23, py - 78, 46, 78)
        elif kind == "smoke_pickup":
            bounds = (px - 10, py - 20, 20, 20)
        if bounds is not None and _intersects(beacon_bounds, bounds):
            raise error_type(f"检查点不能与机关/货梯轨道/补给实体重叠：{item.get('id', kind)}")
    return copy.deepcopy(checkpoints)


def _append_field(doc: dict, name: str, value: Any, error_type: type[Exception]) -> None:
    """只追加level字段定义/实例和nextUid，不触碰IntGrid或现有用户字段。"""
    definitions = doc["defs"]["levelFields"]
    if any(entry.get("identifier") == name for entry in definitions):
        raise error_type(f"检查点字段 {name} 只有旧schema而无匹配实例，拒绝追加重复定义")
    uid = max([int(doc.get("nextUid", 0)), *(int(field["uid"]) + 1 for field in definitions)])
    definitions.append({"identifier": name, "doc": "JSON：唯一中途检查点及清场前提；不修改地图几何。",
        "__type": "String", "uid": uid, "type": "String", "isArray": False,
        "canBeNull": False, "defaultOverride": None, "editorDisplayMode": "ValueOnly",
        "editorDisplayPos": "Above", "editorLinkStyle": "ZigZag", "editorDisplayScale": 1,
        "editorAlwaysShow": True, "editorShowInWorld": True, "editorCutLongValues": False,
        "editorTextSuffix": None, "editorTextPrefix": None, "useForSmartColor": False})
    doc["levels"][0]["fieldInstances"].append({"__identifier": name, "__tile": None,
        "__type": "String", "__value": json.dumps(value, ensure_ascii=False), "defUid": uid, "realEditorValues": []})
    doc["nextUid"] = uid + 1


def add_single_checkpoint(doc: dict, error_type: type[Exception] = ValueError) -> bool:
    """幂等迁移：已有字段尊重用户位置；已标记版本只校验，绝不重排旧地图。"""
    level = doc["levels"][0]
    previous = _metadata(level, REVISION_FIELD, error_type, optional=True)
    if previous is not None:
        if previous != REVISION:
            raise error_type("未知单检查点版本，拒绝覆盖用户迁移")
        validate(doc, error_type)
        return False
    if level["identifier"] not in DEFAULTS:
        raise error_type("没有为该地图声明唯一检查点，拒绝猜测位置")
    if _metadata(level, FIELD, error_type, optional=True) is None:
        _append_field(doc, FIELD, [copy.deepcopy(DEFAULTS[level["identifier"]])], error_type)
    validate(doc, error_type)
    _append_field(doc, REVISION_FIELD, REVISION, error_type)
    return True
