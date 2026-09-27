#!/usr/bin/env python3
"""03 垂直货运井：错层双塔/贯通维修井/长程货梯的独立LDtk编译器。

只借用已有schema和通用碰撞校验，不读写M04真源。首次--seed拒绝覆盖已有LDtk。
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
SOURCE = ROOT / "godot/maps/m05_vertical_freight.ldtk"
OUTPUT = ROOT / "godot/generated/m05_vertical_freight_data.gd"
W, H, TS = 144, 114, 32
LEVEL_ID = "M05_VerticalFreight"
CROWN_CLEARANCE_REVISION = "crown_128px_upper_lane_v1"
spec = importlib.util.spec_from_file_location("_m05_schema_helpers", Path(__file__).with_name("gen_m04_chrono_freight.py"))
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)
SCHEMA = helper.seed_document()
base = helper.base
base.W, base.H, base.LEVEL_ID = W, H, LEVEL_ID
base.LAYER_SPECS = copy.deepcopy(base.LAYER_SPECS)
FLOORS = [105, 87, 69, 51, 33, 15]  # 下到上；中央/右塔地面，左塔比中央低192px。
LEFT_TITLES = ["井底冷凝库", "重载配重室", "下井检修仓", "中枢分流室", "高压泵舱", "塔冠封存库"]
RIGHT_TITLES = ["底部封锁站", "废热转运室", "冷却阀组", "中层装卸台", "上联稳压室", "塔顶撤离台"]
PROFILES = ["coolant_reservoir", "freight_crossfire", "archive_sorter", "quarantine_scanner", "coolant_reservoir", "containment_core"]


def iid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "kairull:m05:" + label))


base._iid = iid


def rooms_metadata() -> list[dict]:
    rooms = [{"room_id": "central_hub", "display_name": "中部安全枢纽", "decor_profile": "service_bay",
              "role": "connector", "rect": [67, 42, 14, 10], "primary_landmark": "service_bench"},
             {"room_id": "maintenance_spine", "display_name": "折返维修井", "decor_profile": "coolant_shaft",
              "role": "shaft", "rect": [43, 1, 24, 111], "primary_landmark": "maintenance_stairs"},
             {"room_id": "lift_spine", "display_name": "长程货梯井", "decor_profile": "coolant_shaft",
              "role": "shaft", "rect": [81, 1, 24, 111], "primary_landmark": "freight_lifts"}]
    for index, floor in enumerate(FLOORS):
        for side, x, title in [("left", 1, LEFT_TITLES[index]), ("right", 105, RIGHT_TITLES[index])]:
            surface = floor + 6 if side == "left" else floor
            height = min(17, surface)
            profile = PROFILES[index]
            # 只用一个扫描大设备，避免现美术层的profile辅助查找跨房复用。
            if side == "right" and profile == "quarantine_scanner":
                profile = "freight_crossfire"
            rooms.append({"room_id": f"{side}_{floor}", "display_name": title,
                          "decor_profile": profile, "role": "main", "rect": [x, surface - height + 1, 42 if side == "left" else 38, height],
                          "primary_landmark": profile})
    for floor in FLOORS:
        if floor == 51:
            continue
        rooms.append({"room_id": f"bridge_{floor}", "display_name": "井底缓冲桥" if floor == 105 else
                      "上层撤离桥" if floor == 15 else f"{(105 - floor) // 18 + 1}层缓冲桥",
                      "decor_profile": "relay_service", "role": "connector",
                      "rect": [67, floor - 9, 14, 10], "primary_landmark": "service_bench"})
    return rooms


ROOMS = rooms_metadata()
base.LAYER_SPECS["Rooms"] = base.LayerSpec(2, {
    index: (room["room_id"], ["#497C86", "#796C58", "#64748A", "#985A70"][index % 4])
    for index, room in enumerate(ROOMS, 1)
}, 0.18)


def stairs_metadata() -> list[dict]:
    stairs = []
    # 每个左房经一段12级钢梯接中央层；层间走错位维修台，不把对向高度场堆在同一脚点。
    for index, floor in enumerate(FLOORS):
        flights = [(50, floor + 6, 62, floor, "right_up", "room_link")]
        for bx, by, tx, ty, direction, label in flights:
            stairs.append({"stair_id": f"spine_{floor}_{label}", "room_id": "maintenance_spine",
                           "bottom_cell": [bx, by], "top_cell": [tx, ty], "direction": direction,
                           "step_run_px": 32, "step_rise_px": 16, "steps": 12,
                           "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False})
    return stairs


STAIRS = stairs_metadata() # 六段接梯72踏面；长跨层维修路线另有错位跳台，不堆对向高度场抢支撑。
LIFTS = [("lift_bottom", 86, 105, 87), ("lift_lower", 98, 87, 69),
         ("lift_upper", 86, 51, 33), ("lift_crown", 98, 33, 15)]


def owner_cell(x: int, y: int) -> str:
    matches = []
    for room in ROOMS:
        rx, ry, rw, rh = room["rect"]
        if rx <= x < rx + rw and ry <= y < ry + rh:
            matches.append(room["room_id"])
    if len(matches) != 1:
        raise base.MapError(f"位置c{x}/r{y}不属于唯一房间：{matches}")
    return matches[0]


def entity_metadata() -> list[tuple[int, int, int]]:
    entities = [(74, 105, 1), (74, 15, 2)] # 最底层安全缓冲桥出生，逐层上攀；中枢只保留检查点。
    for floor in FLOORS:
        # 左房从右端进：前排近战、后排枪手；右房反向分布，留分开的货箱射线。
        entities += [(38, floor + 6, 3), (29, floor + 6, 4), (20, floor + 6, 3), (9, floor + 6, 4),
                     (109, floor, 3), (119, floor, 4), (130, floor, 3), (139, floor, 4),
                     (41, floor + 6, 5), (24, floor + 6, 5), (107, floor, 5), (126, floor, 5)]
        if floor == 15:
            # 塔冠上廊抬至128px，扣除台面皮肤仍有116px净空；侧边64px实心踏台负责两段跳。
            entities += [(16, 17, 4), (24, 17, 3), (21, 17, 5),
                         (116, 11, 4), (128, 11, 3), (123, 11, 5)]
    return entities


ENTITIES = entity_metadata()


def tactical_metadata() -> list[dict]:
    items = []
    smoke_points = [(74, 51), (73, 69), (73, 87), (73, 105), (73, 33), (73, 15), (3, 93), (142, 33)]
    for index, (x, floor) in enumerate(smoke_points, 1):
        items.append({"id": f"smoke_{index}", "type": "smoke_pickup", "pos": [x * 32 + 16, floor * 32 - .1],
                      "room_id": owner_cell(x, floor - 1),
                      "purpose": "在层间缓冲站准备烟幕；井底/塔顶狙击区域前有明确资源选择，不在梯面撒补给",
                      "solutions": ["抛到本层枪手线，利用烟幕换位或挥箱", "保留烟雾，先走另一塔/维修路绕开火线"]})
    for index, (x, floor) in enumerate([(13, 111), (112, 87), (13, 75), (112, 51), (13, 39), (121, 15)], 1):
        items.append({"id": f"laser_{index}", "type": "laser_gate", "pos": [x * 32, floor * 32 - 54],
                      "span": 128, "height": 54, "floor_y": floor * 32,
                      "room_id": owner_cell(x, floor - 1), "purpose": "房内短束线在明确两组守军之间；不跨整个竖井",
                      "solutions": ["低姿态翻滚从54px高束线下穿过", "观察关闭窗或在预警期间时停后通行"]})
    for index, (x, floor) in enumerate([(33, 93), (132, 69), (132, 33)], 1):
        items.append({"id": f"press_{index}", "type": "press", "pos": [x * 32, floor * 32 - 192],
                      "width": 64, "floor_y": floor * 32, "room_id": owner_cell(x, floor - 1),
                      "purpose": "工业落闸前留缓冲平地，避免在电梯站台或楼梯上强迫等待",
                      "solutions": ["在清楚的回程安全窗穿过", "预警时暂停机械节拍，再接近后卫枪手"]})
    for index, (x, floor, direction, hard) in enumerate([(4, 111, 1, True), (141, 105, -1, False),
                                                      (4, 21, 1, True), (141, 15, -1, False)], 1):
        items.append({"id": f"sniper_{index}", "type": "auto_sniper", "pos": [x * 32 + 16, floor * 32 - .1],
                      "direction": [direction, 0], "range": 992, "hard_only": hard,
                      "room_id": owner_cell(x, floor - 1), "purpose": "只在井底和塔冠较难房布置，3秒跟踪/半秒锁向/3秒冷却",
                      "solutions": ["最后锁向后横移/翻滚或进入预先抛出的烟幕", "利用本层货箱/上路击杀守军，清房让炮台停机"]})
    for name, x, bottom, top in LIFTS:
        items.append({"id": name, "type": "freight_lift", "pos": [x * 32 + 16, bottom * 32],
                      "top_y": top * 32, "width": 96, "height": 12,
                      "travel_time": 3.6, "dwell": 1.2, "room_id": "lift_spine",
                      "purpose": "576px长程货梯跨完整主要楼层；开敞轨道和专用停靠开口，不穿实心楼板",
                      "solutions": ["乘货梯直接抵达上一主要楼层，省去长距离折返", "改走左側错位维修栈道和接梯，与两塔横桥构成完整备用路线"]})
    return items


def validate_rooms(room_grid: list[int], metadata: list[dict]) -> list[dict]:
    if len(metadata) != 20:
        raise base.MapError("垂直井必须有12战斗室、6短桥/枢纽、2贯通井，共20房")
    used = set()
    seen = set()
    for value, room in enumerate(metadata, 1):
        if room["room_id"] in seen or "checkpoint_cell" in room:
            raise base.MapError("房间ID重复或存在禁止的检查点")
        seen.add(room["room_id"])
        x, y, width, height = room["rect"]
        if x < 1 or y < 1 or x + width > W - 1 or y + height > H - 1:
            raise base.MapError(f"房间越界：{room['room_id']}")
        if room["role"] == "shaft":
            if not (width >= 16 and height >= 100):
                raise base.MapError("主竖井必须真实贯通六层，不能以一张高背景代替")
        elif room["role"] == "main":
            if not (30 <= width <= 42 and 15 <= height <= 20):
                raise base.MapError("战斗房尺寸超出像素相机/跳跃预算")
        elif not (10 <= width <= 18 and height == 10):
            raise base.MapError("安全桥不做成长走廊")
        actual = {(i % W, i // W) for i, raw in enumerate(room_grid) if raw == value}
        expected = {(xx, yy) for yy in range(y, y + height) for xx in range(x, x + width)}
        if actual != expected or used & expected:
            raise base.MapError(f"Rooms IntGrid/矩形不一致或重叠：{room['room_id']}")
        used |= expected
    return metadata


def validate_stairs(stairs: list[dict], room_ids: set, entity_cells: set,
                    architecture: list[int], traversal: list[int], collision: list[int]) -> list[dict]:
    if len(stairs) != 6:
        raise base.MapError("错层维修线路需要6段12级房间接梯")
    expected_cells = set()
    for stair in stairs:
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        sign = 1 if stair["direction"] == "right_up" else -1
        if stair["room_id"] not in room_ids or stair["steps"] != 12 or [tx, ty] != [bx + sign * 12, by - 6]:
            raise base.MapError("楼梯端点/房间/12级高度场不一致")
        if stair["step_rise_px"] != 16 or stair["step_run_px"] != 32:
            raise base.MapError("每级必须保持32×16px物理预算")
        cells = {(bx + i if sign > 0 else bx - i - 1, by - 1 - i // 2) for i in range(12)}
        if expected_cells & cells:
            raise base.MapError("两段钢梯语义格重叠")
        expected_cells |= cells
        interface = tx if sign > 0 else tx - 1
        if base._cell(collision, interface, ty) != 2:
            raise base.MapError("开放钢梯缺少同高接步平台")
        # 完整楼层横桥是已声明的交通层，不是拿粗平台盖住斜梯兜底；梯身不许实心盖帽。
        for x, y in cells:
            if base._cell(collision, x, y) == 1 or any(ex == x and abs(ey - y) < 3 for ex, ey in entity_cells):
                raise base.MapError(f"梯面实心盖帽/敌人占道：c{x}/r{y}")
    arch_cells = {(i % W, i // W) for i, value in enumerate(architecture) if value == 6}
    route_cells = {(i % W, i // W) for i, value in enumerate(traversal) if value == 3}
    if arch_cells != expected_cells or route_cells != expected_cells:
        raise base.MapError("6梯72踏面必须与Architecture/Traversal逐格匹配")
    return stairs


base._validate_rooms = validate_rooms
base._validate_stairs = validate_stairs


def seed_document() -> dict:
    grids = {name: base._blank() for name in base.LAYER_SPECS}
    fill, put = base._fill, base._put
    collision = grids["Collision"]
    for x0, y0, x1, y1 in [(0, 0, W - 1, 0), (0, H - 1, W - 1, H - 1),
                          (0, 0, 0, H - 1), (W - 1, 0, W - 1, H - 1)]:
        fill(collision, x0, y0, x1, y1, 1)
    arch_id = {"coolant_reservoir": 8, "freight_crossfire": 9, "archive_sorter": 4,
               "quarantine_scanner": 2, "containment_core": 10, "service_bay": 7, "relay_service": 7}
    for value, room in enumerate(ROOMS, 1):
        x, y, width, height = room["rect"]
        right, floor = x + width - 1, y + height - 1
        fill(grids["Rooms"], x, y, right, floor, value)
        fill(grids["BackdropTiles"], x, y + 1, right, floor - 1, 1)
        if room["role"] == "shaft":
            # 开敞贯通井：不生成会被货梯直接穿过去的实心顶盖或整层楼板。
            for station in FLOORS:
                for lx in [x + 1, right - 1]:
                    put(grids["Lights"], lx, station - 4, 1)
            continue
        fill(collision, x, y, right, y, 1)
        fill(collision, x, floor, right, floor, 2 if room["role"] == "connector" else 1)
        fill(grids["Traversal"], x, floor - 1, right, floor - 1, 1)
        aid = arch_id[room["decor_profile"]]
        if room["role"] == "main":
            fill(grids["Architecture"], x + 4, y + 3, x + 24, floor - 5, aid)
            fill(grids["BackdropTiles"], x + 4, y + 3, x + 24, floor - 6, 3)
            fill(grids["ForegroundTiles"], x + 1, y + 1, x + 1, y + 5, 3)
            for lx in [x + 3, x + 17, right - 3]:
                put(grids["Lights"], lx, y + 1, 1 + (value % 3))
        else:
            fill(grids["Architecture"], x + 3, y + 3, right - 3, floor - 3, aid)
            put(grids["Lights"], x + 6, y + 1, 1)
    # 中枢右侧每层有正常横桥，电梯停靠口挖出真实3格开口。
    for floor in FLOORS:
        fill(collision, 81, floor, 104, floor, 2)
        fill(grids["Traversal"], 81, floor - 1, 104, floor - 1, 1)
    for _name, center, bottom, top in LIFTS:
        for floor in [bottom, top]:
            fill(collision, center - 1, floor, center + 1, floor, 0)
            fill(grids["Traversal"], center - 1, floor - 1, center + 1, floor - 1, 0)
    # 左房入井是等高站台；通往中央的12级钢梯负责真实192px错层，不假装走平路。
    for floor in FLOORS:
        fill(collision, 43, floor + 6, 49, floor + 6, 2)
        fill(grids["Traversal"], 43, floor + 5, 49, floor + 5, 1)
        fill(collision, 62, floor, 66, floor, 2)
        fill(grids["Traversal"], 62, floor - 1, 66, floor - 1, 1)
        if floor != 15:
            # 每次升96px且站位错开，94px白发原画不被上一块台板压住；只有跳跃时主动穿单向面。
            for x0, x1, surface in [(58, 64, floor - 3), (55, 61, floor - 6), (52, 58, floor - 9)]:
                fill(collision, x0, surface, x1, surface, 2)
                fill(grids["Traversal"], x0, surface - 1, x1, surface - 1, 1)
    for stair in STAIRS:
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        sign = 1 if stair["direction"] == "right_up" else -1
        interface = tx if sign > 0 else tx - 1
        pad_start, pad_end = (62, 66) if sign > 0 else (43, 49)
        fill(collision, pad_start, ty, pad_end, ty, 2)
        fill(grids["Traversal"], pad_start, ty - 1, pad_end, ty - 1, 1)
        for i in range(12):
            x = bx + i if sign > 0 else bx - i - 1
            y = by - 1 - i // 2
            put(grids["Architecture"], x, y, 6)
            put(grids["Traversal"], x, y, 3)
    # 只有塔冠是128px双路，侧边实心踏台不伪装成可钻的64px低通道。
    for x0, x1, top, bottom in [(11, 12, 19, 21), (111, 112, 13, 15)]:
        fill(collision, x0, top, x1, bottom, 1)
        fill(grids["Traversal"], x0, bottom - 1, x1, bottom - 1, 0)
        fill(grids["Traversal"], x0, top - 1, x1, top - 1, 1)
    for x0, x1, floor in [(14, 26, 17), (114, 132, 11)]:
        fill(collision, x0, floor, x1, floor, 2)
        fill(grids["Traversal"], x0, floor - 1, x1, floor - 1, 1)
    for x, floor, value in ENTITIES:
        put(grids["Entities"], x, floor - 1, value)
    doc = copy.deepcopy(SCHEMA)
    doc.update({"iid": iid("project"), "dummyWorldIid": iid("world"), "nextUid": 120,
                "worldGridWidth": W * TS, "worldGridHeight": H * TS,
                "defaultLevelWidth": W * TS, "defaultLevelHeight": H * TS})
    doc["defs"]["layers"] = [base._layer_def(name, spec) for name, spec in base.LAYER_SPECS.items()]
    doc["defs"]["levelFields"] = []
    level = doc["levels"][0]
    level.update({"identifier": LEVEL_ID, "iid": iid("level"), "pxWid": W * TS, "pxHei": H * TS,
                  "fieldInstances": [], "layerInstances": [base._layer_instance(name, spec, grids[name])
                   for name, spec in reversed(list(base.LAYER_SPECS.items()))]})
    fields = [("RoomMetadata", ROOMS), ("StairMetadata", STAIRS), ("TacticalObjects", tactical_metadata()),
              ("EncounterBoundaries", []), ("EncounterPolicy", "same_floor_nearby"),
              ("RoomFloors", [{"center_floor": f, "left_floor": f + 6, "right_floor": f} for f in FLOORS]),
              ("CrownClearanceRevision", CROWN_CLEARANCE_REVISION)]
    for uid, (name, value) in enumerate(fields, 31):
        field_def = copy.deepcopy(SCHEMA["defs"]["levelFields"][0])
        field_def.update({"identifier": name, "uid": uid, "doc": "垂直货运井的正式LDtk运行合同"})
        doc["defs"]["levelFields"].append(field_def)
        level["fieldInstances"].append({"__identifier": name, "__tile": None, "__type": "String",
            "__value": json.dumps(value, ensure_ascii=False), "defUid": uid, "realEditorValues": []})
    base.checkpoint_contract.add_single_checkpoint(doc, base.MapError)
    return doc


def upgrade_crown_clearance(doc: dict) -> bool:
    """只修两处塔冠净空；保留所有其他层/576px主梯，版本标记防重复覆盖后续编辑。"""
    level, _ = base._level_and_layers(doc)
    if any(field["__identifier"] == "CrownClearanceRevision" for field in level["fieldInstances"]):
        if base._metadata(level, "CrownClearanceRevision") != CROWN_CLEARANCE_REVISION:
            raise base.MapError("未知塔冠净空版本，拒绝覆盖用户地图")
        return False
    layers = {layer["__identifier"]: layer["intGridCsv"] for layer in level["layerInstances"]}

    def fill(name, x0, y0, x1, y1, value):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                layers[name][y * W + x] = value

    for x0, x1, old_floor in [(13, 26, 18), (113, 132, 12)]:
        if any(layers["Collision"][old_floor * W + x] != 2 for x in range(x0, x1 + 1)):
            raise base.MapError("旧塔冠平台已经被用户修改，拒绝覆盖")
        fill("Collision", x0, old_floor, x1, old_floor, 0)
        fill("Traversal", x0, old_floor - 1, x1, old_floor - 1, 0)
    for x0, x1, top, bottom in [(11, 12, 19, 21), (111, 112, 13, 15)]:
        fill("Collision", x0, top, x1, bottom, 1)
        fill("Traversal", x0, bottom - 1, x1, bottom - 1, 0)
        fill("Traversal", x0, top - 1, x1, top - 1, 1)
    for x0, x1, floor in [(14, 26, 17), (114, 132, 11)]:
        fill("Collision", x0, floor, x1, floor, 2)
        fill("Traversal", x0, floor - 1, x1, floor - 1, 1)
    for x, old_floor, value in [(16, 18, 4), (24, 18, 3), (21, 18, 5),
                                (116, 12, 4), (128, 12, 3), (123, 12, 5)]:
        if layers["Entities"][(old_floor - 1) * W + x] != value or layers["Entities"][(old_floor - 2) * W + x] != 0:
            raise base.MapError("塔冠实体源/目标已被用户修改，拒绝覆盖")
        layers["Entities"][(old_floor - 1) * W + x] = 0
        layers["Entities"][(old_floor - 2) * W + x] = value
    field = next(field for field in level["fieldInstances"] if field["__identifier"] == "TacticalObjects")
    tactical = json.loads(field["__value"])
    laser = next(item for item in tactical if item["id"] == "laser_6")
    if laser["pos"] != [112 * 32, 15 * 32 - 54]:
        raise base.MapError("塔冠光栅位置已被用户修改，拒绝覆盖")
    laser["pos"] = [121 * 32, 15 * 32 - 54]
    field["__value"] = json.dumps(tactical, ensure_ascii=False)
    template = copy.deepcopy(doc["defs"]["levelFields"][0])
    template.update({"identifier": "CrownClearanceRevision", "uid": 37,
                     "doc": "塔冠128px上廊+64px侧踏台净空版本"})
    doc["defs"]["levelFields"].append(template)
    level["fieldInstances"].append({"__identifier": "CrownClearanceRevision", "__tile": None,
        "__type": "String", "__value": json.dumps(CROWN_CLEARANCE_REVISION), "defUid": 37,
        "realEditorValues": []})
    compile_document(doc, "crown-clearance-validation")
    return True


def validate_tactics(doc: dict) -> list[dict]:
    level, layers = base._level_and_layers(doc)
    items = base._metadata(level, "TacticalObjects")
    kinds = {kind: 0 for kind in ["smoke_pickup", "laser_gate", "press", "auto_sniper", "freight_lift"]}
    ids = set()
    for item in items:
        if item["type"] not in kinds or item["id"] in ids or len(item.get("solutions", [])) < 2 or not item.get("purpose"):
            raise base.MapError("战术对象ID/类型/用途/替代解法不合法")
        ids.add(item["id"])
        kinds[item["type"]] += 1
        x, y = item["pos"]
        if not (0 < x < W * TS and 0 < y < H * TS):
            raise base.MapError("战术对象越界")
        if owner_cell(int(x // TS), int(y // TS)) != item["room_id"]:
            raise base.MapError("战术对象不在声明房间")
        if item["type"] == "freight_lift":
            if y - item["top_y"] != 576 or item["travel_time"] != 3.6:
                raise base.MapError("本关货梯必须576px跨整层，不能回退为小升降台")
            # 平台及人物穿行的宽度内，整条井道不可存在实心顶板；站台也必须真开口。
            cx = int(x // TS)
            for row in range(int(item["top_y"] // TS) - 3, int(y // TS) + 1):
                for column in range(cx - 1, cx + 2):
                    if base._cell(layers["Collision"], column, row) == 1:
                        raise base.MapError("长程货梯竖井被实心楼板封住")
            for floor in [int(y // TS), int(item["top_y"] // TS)]:
                if any(base._cell(layers["Collision"], xx, floor) != 0 for xx in range(cx - 1, cx + 2)):
                    raise base.MapError("货梯上下站应有3格实际开口")
        elif item["type"] == "smoke_pickup":
            if base._cell(layers["Collision"], int(x // TS), int(y // TS) + 1) not in {1, 2}:
                raise base.MapError("补给必须在稳定站台，而不是悬空井道")
    if kinds != {"smoke_pickup": 8, "laser_gate": 6, "press": 3, "auto_sniper": 4, "freight_lift": 4}:
        raise base.MapError(f"战术数量偏离预算：{kinds}")
    if base._metadata(level, "EncounterBoundaries") != [] or base._metadata(level, "EncounterPolicy") != "same_floor_nearby":
        raise base.MapError("自由上下探索必须空间临近唤醒，不能重套线性记录点")
    return items


def compile_document(doc: dict, source_hash: str) -> str:
    items = validate_tactics(doc)
    base.checkpoint_contract.validate(doc, base.MapError)
    result = base._validate_and_compile(doc, source_hash)
    result = result.replace("正式第一关编译数据", "03 垂直货运井编译数据").replace("m01_protocol_quarantine", "m05_vertical_freight")
    result += "\n## 坐标为世界像素；开放竖井/停靠口与货梯由同一LDtk共同声明。\n"
    result += "const TACTICAL_OBJECTS: Array[Dictionary] = " + json.dumps(items, ensure_ascii=False, indent=2) + "\n"
    result += 'const ENCOUNTER_BOUNDARIES: Array[int] = []\nconst ENCOUNTER_POLICY := "same_floor_nearby"\n'
    result += "const ROOM_FLOORS := " + json.dumps(base._metadata(doc["levels"][0], "RoomFloors"), ensure_ascii=False) + "\n"
    return result


def move_spawn_to_bottom(doc: dict) -> bool:
    """只移动已知旧出生标记；保留所有地形/敌箱/检查点，重复执行无改动。"""
    layers = doc["levels"][0]["layerInstances"]
    entities = next(layer["intGridCsv"] for layer in layers if layer["__identifier"] == "Entities")
    old, new = 50 * W + 74, 104 * W + 74
    if entities[new] == 1 and entities.count(1) == 1:
        return False
    if entities[old] != 1 or entities[new] != 0 or entities.count(1) != 1:
        raise base.MapError("出生位置已被另改，拒绝覆盖用户地图")
    entities[old], entities[new] = 0, 1
    compile_document(doc, "bottom-spawn-validation")
    return True


def compile_path(path: Path = SOURCE) -> str:
    raw = path.read_bytes()
    return compile_document(json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", action="store_true")
    parser.add_argument("--start-at-bottom", action="store_true", help="仅将中枢出生标记移至井底安全桥，幂等且不改地形")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--revise-owned-draft", action="store_true", help="只升级尚未交付的132宽M05草稿为24格净空维修井，拒绝覆盖其他版本")
    parser.add_argument("--upgrade-crown-clearance", action="store_true", help="只抬高两塔冠上廊至128px并增加侧踏台，幂等迁移")
    parser.add_argument("--add-single-checkpoint", action="store_true", help="仅添加下半区24敌清后启用的唯一检查点，不改地形")
    args = parser.parse_args()
    try:
        if args.seed:
            if SOURCE.exists():
                raise base.MapError("拒绝覆盖现有第三关LDtk")
            doc = seed_document()
            compile_document(doc, "pre-write-validation")
            SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.revise_owned_draft:
            previous_raw = SOURCE.read_bytes()
            if hashlib.sha256(previous_raw).hexdigest() != "4ae471c5d61ea7409c0d3fb0634a9be073c0a1bc50f428e1009ae46d5ede8ccf":
                raise base.MapError("草稿已经改变，拒绝覆写任何用户后续修改")
            old = json.loads(previous_raw.decode("utf-8"))
            if old["levels"][0]["identifier"] != LEVEL_ID or old["levels"][0]["pxWid"] != 132 * TS:
                raise base.MapError("只允许迁移本轮未交付的132宽M05草稿，不覆盖其他版本")
            doc = seed_document()
            compile_document(doc, "maintenance-clearance-validation")
            SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.upgrade_crown_clearance:
            doc = json.loads(SOURCE.read_text(encoding="utf-8"))
            if upgrade_crown_clearance(doc):
                SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if args.add_single_checkpoint:
            doc = json.loads(SOURCE.read_text(encoding="utf-8"))
            if base.checkpoint_contract.add_single_checkpoint(doc, base.MapError):
                compile_document(doc, "single-checkpoint-migration-validation")
                SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        compiled = compile_path()
        if args.start_at_bottom:
            doc = json.loads(SOURCE.read_text(encoding="utf-8"))
            if move_spawn_to_bottom(doc):
                SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            compiled = compile_path()
        if args.write:
            OUTPUT.write_text(compiled, encoding="utf-8")
        if args.check and (not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != compiled):
            raise base.MapError("第三关LDtk与generated不同步")
        print("M05_MAP_RESULT: PASS | 144x114 | 6 storeys | 20 rooms | 52 enemies | 26 cargo | 8 smoke | 9 traps | 4 snipers | 4x576px lifts")
        return 0
    except (OSError, ValueError, base.MapError) as exc:
        print("M05_MAP_RESULT: FAIL | " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
