#!/usr/bin/env python3
"""04 排风脊线（M06_ExhaustRidge）：屋顶跑酷关的 LDtk 生成/编译器。

设计合同见 godot/maps/M06-EXHAUST-RIDGE.md。沿用 M01/M04 的语义层与编译校验，
只做本关需要的扩展：11 房、房门实体 D（最终竞技场清场锁）、新机关 updraft_fan / glass_panel / dash_node。
所有跑酷捷径（弹射扇、冲刺节点、破窗、冲刺连杀）都另有"普通跑跳"可达的备用路线，
编译器保守可达性检查不计冲刺/翻滚/弹射，保证不会卡关。

用法：
  python gen_m06_exhaust_ridge.py --seed --write --check   # 首次建档（拒绝覆盖已有 LDtk）
  python gen_m06_exhaust_ridge.py --write --check          # LDtk 编辑后重新编译
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
SOURCE = ROOT / "godot/maps/m06_exhaust_ridge.ldtk"
OUTPUT = ROOT / "godot/generated/m06_exhaust_ridge_data.gd"
W, H, TS = 330, 37, 32
LEVEL_ID = "M06_ExhaustRidge"

spec = importlib.util.spec_from_file_location("_m06_schema_helpers", Path(__file__).with_name("gen_m04_chrono_freight.py"))
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)
SCHEMA = helper.seed_document()
base = helper.base
base.W, base.H, base.LEVEL_ID = W, H, LEVEL_ID
base.LAYER_SPECS = copy.deepcopy(base.LAYER_SPECS)
base.ENTITY_TO_CHAR = dict(base.ENTITY_TO_CHAR)
base.ENTITY_TO_CHAR[6] = "D"                      # 房门：所属房间有活敌时锁定（RoomDoor）
base.LAYER_SPECS["Entities"] = base.LayerSpec(3, {
    **base.LAYER_SPECS["Entities"].values, 6: ("RoomDoor", "#E75963")})
base.ROOM_PROFILES = dict(base.ROOM_PROFILES)
base.ROOM_PROFILES.update({"roof_hatch": "connector", "fan_array": "main", "skylight_gallery": "main",
                           "cooling_towers": "main", "sniper_mast": "main", "exhaust_shaft": "shaft",
                           "sky_bridge": "main", "drop_chute": "shaft", "pump_arena": "main",
                           "extraction_crane": "connector"})


def iid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "kairull:m06:" + label))


base._iid = iid

# (room_id, 显示名, decor_profile, role, rect[x,y,w,h])；地面统一在 row 35
ROOM_TABLE = [
    ("roof_hatch", "屋顶检修口", "roof_hatch", "connector", [1, 25, 16, 11]),
    ("fan_array", "排风扇阵列", "fan_array", "main", [17, 15, 42, 21]),
    ("skylight_gallery", "玻璃天窗廊", "skylight_gallery", "main", [59, 15, 42, 21]),
    ("cooling_towers", "冷却塔跳台", "cooling_towers", "main", [101, 13, 42, 23]),
    ("relay_station", "中继检修站", "relay_service", "connector", [143, 25, 15, 11]),
    ("sniper_mast", "狙击桅杆", "sniper_mast", "main", [158, 13, 42, 23]),
    ("exhaust_shaft", "排气竖井", "exhaust_shaft", "shaft", [200, 1, 16, 35]),
    ("sky_bridge", "高空索桥", "sky_bridge", "main", [216, 1, 42, 20]),
    ("drop_chute", "坠落通道", "drop_chute", "shaft", [258, 1, 14, 35]),
    ("pump_arena", "封锁泵站", "pump_arena", "main", [272, 15, 42, 21]),
    ("extraction", "撤离塔吊", "extraction_crane", "connector", [314, 25, 15, 11]),
]
SKY_ROOMS = {"roof_hatch", "fan_array", "skylight_gallery", "cooling_towers", "relay_station",
             "sniper_mast", "sky_bridge", "pump_arena", "extraction"}
ROOMS = [{"room_id": rid, "display_name": name, "decor_profile": prof, "role": role, "rect": rect,
          "primary_landmark": prof} for rid, name, prof, role, rect in ROOM_TABLE]
base.LAYER_SPECS["Rooms"] = base.LayerSpec(2, {
    i + 1: (rid.title().replace("_", ""), "#5A7890") for i, (rid, *_rest) in enumerate(ROOM_TABLE)}, 0.18)
ROOM_INDEX = {r["room_id"]: i for i, r in enumerate(ROOMS)}

# 楼梯：狙击桅杆前的 10 级右上钢梯（本关唯一楼梯，基础合同要求至少一段）
STAIRS = [{"stair_id": "mast_stair", "room_id": "sniper_mast", "bottom_cell": [176, 35],
           "top_cell": [186, 30], "direction": "right_up", "step_run_px": 32, "step_rise_px": 16,
           "steps": 10, "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False}]

# 实体：(c, 脚底行, 值) 1 出生 2 出口 3 近战 4 枪手 5 货箱 6 房门
ENTITIES = [
    (4, 34, 1), (325, 34, 2),
    # 排风扇阵列：地面两近战一货箱，上层步道枪手+近战
    (27, 34, 3), (40, 34, 3), (32, 34, 5), (44, 28, 4), (52, 28, 3),
    # 玻璃天窗廊：上层廊道玻璃后一枪一近战；地面一近战一枪手一货箱
    (76, 28, 4), (88, 28, 3), (80, 34, 3), (92, 34, 4), (66, 34, 5),
    # 冷却塔跳台：塔顶一枪一近战，地面一近战一枪手
    (120, 24, 4), (138, 23, 3), (118, 34, 3), (134, 34, 4),
    # 狙击桅杆：近战、玻璃后枪手、桅杆脚枪手
    (164, 34, 3), (174, 34, 4), (194, 34, 4), (161, 34, 5),
    # 高空索桥：桥段连杀（近战/枪手/近战）+ 桥下基座两名
    (231, 13, 3), (243, 13, 4), (254, 13, 3), (236, 19, 4), (248, 19, 3),
    # 封锁泵站（终局竞技场）：六名混合 + 出口侧房门
    (280, 34, 3), (290, 34, 4), (298, 34, 3), (306, 34, 4), (288, 28, 4), (303, 28, 3), (284, 34, 5),
    (311, 34, 6),
]


def owner(x: int, y: int) -> str:
    hits = [r["room_id"] for r in ROOMS if r["rect"][0] <= x < r["rect"][0] + r["rect"][2]
            and r["rect"][1] <= y < r["rect"][1] + r["rect"][3]]
    if len(hits) != 1:
        raise base.MapError(f"c{x}/r{y} 不属于唯一房间：{hits}")
    return hits[0]


def px(c: float) -> float:
    return c * TS


def tactical_metadata() -> list[dict]:
    items: list[dict] = []

    def add(item: dict, cx: int, cy: int) -> None:
        item["room_id"] = owner(cx, cy)
        items.append(item)

    # 弹射扇：pos = [扇心 x, 地表 y]；地表是扇所在格的顶边
    fans = [("fan_tutorial", 10, 35, 256), ("fan_array_a", 22, 35, 224), ("fan_array_b", 47, 35, 224),
            ("fan_towers", 106, 35, 320), ("fan_mast", 172, 35, 288), ("fan_shaft", 203, 35, 400),
            ("fan_arena_a", 277, 35, 224), ("fan_arena_b", 294, 35, 224)]
    for fid, c, floor, h in fans:
        add({"id": fid, "type": "updraft_fan", "pos": [px(c) + 16, px(floor)], "width": 64,
             "launch_height": h, "purpose": "排风弹射：一步上到高层捷径，比备用台阶路线更快",
             "solutions": ["踩上扇面直接弹起", "不踩扇走旁边的普通台阶/楼梯"]}, c, floor - 1)
    # 可破玻璃：rect 像素；竖向 1×4 格
    glass = [("glass_gallery_1", 70, 25), ("glass_gallery_2", 82, 25), ("glass_gallery_3", 94, 25),
             ("glass_mast_cover", 170, 31)]
    for gid, c, top in glass:
        add({"id": gid, "type": "glass_panel", "pos": [px(c), px(top)], "rect": [px(c), px(top), 32, 128],
             "purpose": "磨砂检疫玻璃：挡视线/子弹，冲刺或翻滚撞碎穿过",
             "solutions": ["冲刺/翻滚破窗突入，玻璃后敌人来不及反应", "挥棒敲碎，或从下层绕行"]}, c, top + 1)
    # 冲刺节点：悬空，冲刺冷却中触碰即刷新
    nodes = [("node_towers_1", 108.5, 26.5), ("node_towers_2", 125.5, 24.0), ("node_bridge_1", 226.5, 12.5),
             ("node_bridge_2", 238.0, 12.5), ("node_bridge_3", 249.0, 12.5), ("node_shaft", 213.5, 14.0)]
    for nid, cx, cy in nodes:
        add({"id": nid, "type": "dash_node", "pos": [px(cx), px(cy)], "respawn": 2.0,
             "purpose": "空中续冲：跨越需要二次冲刺的缺口",
             "solutions": ["冲刺→碰节点→再冲刺", "从下层基座走台阶绕行"]}, int(cx), int(cy))
    # 烟雾补给
    for sid, c, floor in [("smoke_hatch", 13, 35), ("smoke_relay", 146, 35), ("smoke_arena", 274, 35)]:
        add({"id": sid, "type": "smoke_pickup", "pos": [px(c) + 16, px(floor) - 0.1],
             "purpose": "在狙击/竞技场前准备烟幕", "solutions": ["投烟断狙击视线", "保留到终局竞技场"]}, c, floor - 1)
    # 光栅（低身翻滚可过）与压机
    for lid, c, floor in [("laser_gallery", 72, 35), ("laser_bridge", 226, 20)]:
        add({"id": lid, "type": "laser_gate", "pos": [px(c), px(floor) - 54], "span": 96, "height": 54,
             "floor_y": px(floor), "purpose": "下层慢路线上的节拍光栅",
             "solutions": ["翻滚从 54px 束线下穿过", "等关闭窗或走上层捷径"]}, c, floor - 1)
    for pid, c, floor in [("press_towers_1", 112, 35), ("press_towers_2", 128, 35), ("press_arena", 296, 35)]:
        add({"id": pid, "type": "press", "pos": [px(c), px(floor) - 192], "width": 64, "floor_y": px(floor),
             "purpose": "工业落闸：下层慢路线的节拍", "solutions": ["看回程安全窗穿过", "走塔顶跳台绕开"]}, c, floor - 1)
    # 狙击：桅杆顶（row 27 平台）朝左
    add({"id": "sniper_mast", "type": "auto_sniper", "pos": [px(196) + 16, px(27) - 0.1], "direction": [-1, 0],
         "range": 800, "hard_only": False,
         "purpose": "桅杆狙击：压迫正面冲锋；清房后停机",
         "solutions": ["躲在货箱/玻璃后推进，或投烟断视线", "弹射扇直上桅杆顶一棒打掉"]}, 196, 26)
    return items


def seed_document() -> dict:
    grids = {name: base._blank() for name in base.LAYER_SPECS}
    fill, put = base._fill, base._put
    col = grids["Collision"]
    trav = grids["Traversal"]
    fill(col, 0, 0, W - 1, H - 1, 1)                        # 先全实心，再挖房间
    for value, room in enumerate(ROOMS, 1):
        x, y, w, h = room["rect"]
        right, floor = x + w - 1, y + h - 1
        fill(grids["Rooms"], x, y, right, floor, value)
        fill(col, x, y + 1, right, floor - 1, 0)            # 顶行与底行保留实心：顶棚 / 地面
        if room["role"] == "shaft":
            fill(col, x, y + 1, right, floor - 1, 0)
        fill(trav, x, floor - 1, right, floor - 1, 1)

    def plat(x0: int, x1: int, row: int, one_way: bool = True) -> None:
        fill(col, x0, row, x1, row, 2 if one_way else 1)
        fill(trav, x0, row - 1, x1, row - 1, 1)

    def block(x0: int, y0: int, x1: int, y1: int) -> None:
        fill(col, x0, y0, x1, y1, 1)
        fill(trav, x0, y0 - 1, x1, y0 - 1, 1)
        fill(trav, x0, y0, x1, y1, 0)

    # 室外屋顶：室外房间上方一直挖空到世界顶边（row 0 保留边界），露出夜空；竖井在屋顶线以上补外墙
    for room in ROOMS:
        if room["room_id"] in SKY_ROOMS:
            x, y, w, h = room["rect"]
            fill(col, x, 1, x + w - 1, y, 0)
    fill(col, 200, 1, 200, 13, 1)        # 排气竖井左外墙（狙击桅杆屋顶线以上）
    fill(col, 271, 1, 271, 15, 1)        # 坠落通道右外墙（泵站屋顶线以上）

    # R1 屋顶检修口：教学扇 + 备用台阶 → 上层步道
    plat(7, 9, 32)
    plat(12, 16, 29)
    # R2 排风扇阵列：上层步道（6 格缺口可普通跳过）+ 右端备用台阶
    plat(17, 30, 29)
    plat(37, 58, 29)
    plat(54, 56, 32)
    # R3 玻璃天窗廊：封闭上层廊道（顶棚 row24，地板单向 row29）
    plat(59, 100, 29)
    fill(col, 62, 24, 97, 24, 1)
    # R4 冷却塔跳台：塔顶单向跳台
    plat(101, 106, 29)
    plat(111, 114, 27)
    plat(119, 122, 25)
    plat(128, 131, 27)
    plat(134, 142, 24)
    # R6 狙击桅杆：地面掩体箱 + 钢梯上端平台 + 桅杆顶
    block(168, 33, 169, 34)
    block(182, 33, 183, 34)
    plat(186, 189, 30)
    fill(col, 192, 28, 193, 34, 1)                          # 桅杆柱
    fill(trav, 192, 34, 193, 34, 0)
    plat(190, 199, 27)
    # R7 排气竖井：之字单向台阶（普通跳）+ 井底弹射扇直达 L4
    plat(211, 214, 32)
    plat(206, 209, 29)
    plat(210, 213, 26)
    plat(204, 208, 23)
    plat(209, 215, 20)
    # R8 高空索桥：基座地面 row20；上层桥段 row14（需冲刺连杀的缺口），每段下方备用台阶
    for bx0, bx1 in [(218, 222), (230, 233), (242, 245), (252, 257)]:
        plat(bx0, bx1, 14)
        plat(bx0 - 3, bx0 - 1, 17)
    # R9 坠落通道：两级缓降台
    plat(259, 264, 26)
    plat(265, 270, 31)
    # R10 封锁泵站：两块上层平台 + 台阶；出口侧房门上方封墙
    plat(284, 292, 29)
    plat(281, 283, 32)
    plat(300, 306, 29)
    plat(297, 299, 32)
    fill(col, 311, 16, 312, 31, 1)
    fill(trav, 311, 34, 312, 34, 1)
    # 楼梯语义
    for stair in STAIRS:
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        put(col, tx, ty, 2)
        for i in range(stair["steps"]):
            sx, sy = bx + i, by - 1 - i // 2
            put(grids["Architecture"], sx, sy, 6)
            put(trav, sx, sy, 3)
    # 楼梯范围内的地面走线让给高度场
    for stair in STAIRS:
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        for yy in range(ty, by):
            for xx in range(bx, tx):
                if grids["Traversal"][yy][xx] == 1:
                    put(trav, xx, yy, 0)
    # 实体
    for x, row, value in ENTITIES:
        put(grids["Entities"], x, row, value)
    # 美术语义（首版最小集：室外天空处不铺墙壳，由 M06 专用背景绘制）
    for value, room in enumerate(ROOMS, 1):
        if room["room_id"] in SKY_ROOMS:
            continue                      # 露天房间不挂天花板灯（灯光由屋顶设备/信标美术表达）
        x, y, w, h = room["rect"]
        for lx in range(x + 3, x + w - 2, 9):
            put(grids["Lights"], lx, y + 1, 1 + (lx // 9) % 3)

    doc = copy.deepcopy(SCHEMA)
    doc.update({"iid": iid("project"), "dummyWorldIid": iid("world"), "nextUid": 140,
                "worldGridWidth": W * TS, "worldGridHeight": H * TS,
                "defaultLevelWidth": W * TS, "defaultLevelHeight": H * TS})
    doc["defs"]["layers"] = [base._layer_def(name, s) for name, s in base.LAYER_SPECS.items()]
    doc["defs"]["levelFields"] = []
    level = doc["levels"][0]
    level.update({"identifier": LEVEL_ID, "iid": iid("level"), "pxWid": W * TS, "pxHei": H * TS,
                  "fieldInstances": [], "layerInstances": [base._layer_instance(name, s, grids[name])
                   for name, s in reversed(list(base.LAYER_SPECS.items()))]})
    fields = [("RoomMetadata", ROOMS), ("StairMetadata", STAIRS), ("TacticalObjects", tactical_metadata()),
              ("EncounterBoundaries", [4, 6]), ("EncounterPolicy", "linear_flow")]
    for uid, (name, value) in enumerate(fields, 31):
        field_def = copy.deepcopy(SCHEMA["defs"]["levelFields"][0])
        field_def.update({"identifier": name, "uid": uid, "doc": "04 排风脊线的正式 LDtk 运行合同"})
        doc["defs"]["levelFields"].append(field_def)
        level["fieldInstances"].append({"__identifier": name, "__tile": None, "__type": "String",
            "__value": json.dumps(value, ensure_ascii=False), "defUid": uid, "realEditorValues": []})
    base.checkpoint_contract.add_single_checkpoint(doc, base.MapError)
    return doc


def validate_rooms(room_grid: list[int], metadata: list[dict]) -> list[dict]:
    """本关房型尺寸放宽（跑酷长房/竖井），其余与基础合同一致：唯一、互不重叠、与 IntGrid 一致。"""
    if len(metadata) != len(ROOM_TABLE):
        raise base.MapError("排风脊线必须为 11 房")
    used: set[tuple[int, int]] = set()
    for expected, room in enumerate(metadata, 1):
        x, y, w, h = room["rect"]
        limits = {"main": (30, 44, 15, 24), "connector": (10, 18, 8, 12), "shaft": (10, 16, 18, 36)}[room["role"]]
        if not (limits[0] <= w <= limits[1] and limits[2] <= h <= limits[3]):
            raise base.MapError(f"{room['room_id']} 尺寸超出本关房型范围")
        if base.ROOM_PROFILES.get(room["decor_profile"]) != room["role"]:
            raise base.MapError(f"{room['room_id']} decor_profile/role 不匹配")
        cells = {(cx, cy) for cy in range(y, y + h) for cx in range(x, x + w)}
        if used & cells:
            raise base.MapError(f"{room['room_id']} 与其他房间重叠")
        used |= cells
        actual = {(i % W, i // W) for i, v in enumerate(room_grid) if v == expected}
        if actual != cells:
            raise base.MapError(f"Rooms IntGrid 与 {room['room_id']} rect 不一致")
    return metadata


base._validate_rooms = validate_rooms

NEW_KINDS = {"updraft_fan", "glass_panel", "dash_node"}
OLD_KINDS = {"smoke_pickup", "laser_gate", "press", "auto_sniper", "freight_lift"}


def validate_tactics(doc: dict) -> list[dict]:
    level = doc["levels"][0]
    items = base._metadata(level, "TacticalObjects")
    ids = [i["id"] for i in items]
    if len(ids) != len(set(ids)):
        raise base.MapError("TacticalObjects id 重复")
    layers = {l["__identifier"]: l["intGridCsv"] for l in level["layerInstances"]}
    col = layers["Collision"]
    room_ids = {r["room_id"] for r in ROOMS}
    for item in items:
        if item["type"] not in NEW_KINDS | OLD_KINDS:
            raise base.MapError(f"未知机关类型 {item['type']}")
        if item["room_id"] not in room_ids:
            raise base.MapError(f"{item['id']} room_id 未知")
        if item["type"] == "updraft_fan":
            c, r = int(item["pos"][0] // TS), int(item["pos"][1] // TS)
            if col[r * W + c] != 1 or col[(r - 1) * W + c] != 0:
                raise base.MapError(f"{item['id']} 扇面必须嵌在实心地表且上方开敞")
        if item["type"] == "glass_panel":
            gx, gy, gw, gh = item["rect"]
            for cy in range(int(gy // TS), int((gy + gh) // TS)):
                for cx in range(int(gx // TS), int((gx + gw) // TS)):
                    if col[cy * W + cx] != 0:
                        raise base.MapError(f"{item['id']} 玻璃范围内碰撞必须为空")
            if col[int((gy + gh) // TS) * W + int(gx // TS)] == 0:
                raise base.MapError(f"{item['id']} 玻璃底部必须落在地面/平台上")
        if item["type"] == "dash_node":
            c, r = int(item["pos"][0] // TS), int(item["pos"][1] // TS)
            if col[r * W + c] == 1:
                raise base.MapError(f"{item['id']} 冲刺节点不能嵌进实心")
    return items


def compile_document(doc: dict, source_hash: str) -> str:
    items = validate_tactics(doc)
    base.checkpoint_contract.validate(doc, base.MapError)
    result = base._validate_and_compile(doc, source_hash)
    result = result.replace("正式第一关编译数据", "04 排风脊线编译数据").replace("m01_protocol_quarantine", "m06_exhaust_ridge")
    level = doc["levels"][0]
    result += "\n## 坐标为世界像素；弹射扇/玻璃/冲刺节点为本关新增机关（runtime: updraft_fan.gd 等）。\n"
    result += "const TACTICAL_OBJECTS: Array[Dictionary] = " + json.dumps(items, ensure_ascii=False, indent=2) + "\n"
    result += "const ENCOUNTER_BOUNDARIES: Array[int] = " + json.dumps(base._metadata(level, "EncounterBoundaries")) + "\n"
    result += 'const ENCOUNTER_POLICY := "' + base._metadata(level, "EncounterPolicy") + '"\n'
    return result


def compile_path(path: Path = SOURCE) -> str:
    raw = path.read_bytes()
    return compile_document(json.loads(raw.decode("utf-8")), hashlib.sha256(raw).hexdigest())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", action="store_true")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dry", action="store_true", help="只在内存中生成并编译校验，不写任何文件")
    args = parser.parse_args()
    try:
        if args.dry:
            compile_document(seed_document(), "dry-run")
            print("M06_MAP_DRY: PASS")
            return 0
        if args.seed:
            if SOURCE.exists():
                raise base.MapError("拒绝覆盖现有 M06 LDtk")
            doc = seed_document()
            compile_document(doc, "pre-write-validation")
            SOURCE.write_bytes((json.dumps(doc, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        compiled = compile_path()
        if args.write:
            OUTPUT.write_bytes(compiled.encode("utf-8"))
        if args.check and (not OUTPUT.exists() or OUTPUT.read_bytes().decode("utf-8") != compiled):
            raise base.MapError("M06 LDtk 与 generated 不同步")
        enemies = sum(1 for e in ENTITIES if e[2] in (3, 4))
        print(f"M06_MAP_RESULT: PASS | {W}x{H} | {len(ROOMS)} rooms | {enemies} enemies | "
              f"{len(tactical_metadata())} tactical objects")
        return 0
    except (OSError, ValueError, base.MapError) as exc:
        print("M06_MAP_RESULT: FAIL | " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
