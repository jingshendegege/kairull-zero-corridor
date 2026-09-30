#!/usr/bin/env python3
"""05 节拍广播塔（M07_BeatTower）：节奏 Boss「节拍监察官」竞技场的 LDtk 生成/编译器。

设计合同见 godot/maps/ENEMY-HOUND-AND-BEAT-BOSS.md §B。三房：
  R1 后台走廊（两名守卫 + 货箱 + 一段钢梯，满足基础合同，也给玩家热身）
  R2 候场室（安全连接房，唯一检查点：清完后台即记录，Boss 战失败从这里重来）
  R3 节拍舞台（44×21 格竞技场；左侧判定区，右侧 Boss；击败后右端出口开启）
Boss、判定线、两条音符轨不占 LDtk 实体格，统一编进 BOSS_ARENA 常量（世界像素）。

用法：
  python gen_m07_beat_tower.py --seed --write --check   # 首次建档（拒绝覆盖已有 LDtk）
  python gen_m07_beat_tower.py --write --check          # LDtk 编辑后重新编译
  python gen_m07_beat_tower.py --dry                    # 仅内存生成+校验
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
SOURCE = ROOT / "godot/maps/m07_beat_tower.ldtk"
OUTPUT = ROOT / "godot/generated/m07_beat_tower_data.gd"
W, H, TS = 80, 25, 32
LEVEL_ID = "M07_BeatTower"
FLOOR_ROW = 23

spec = importlib.util.spec_from_file_location("_m07_schema_helpers", Path(__file__).with_name("gen_m04_chrono_freight.py"))
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)
SCHEMA = helper.seed_document()
base = helper.base
base.W, base.H, base.LEVEL_ID = W, H, LEVEL_ID
base.LAYER_SPECS = copy.deepcopy(base.LAYER_SPECS)
base.ROOM_PROFILES = dict(base.ROOM_PROFILES)
base.ROOM_PROFILES.update({"backstage": "main", "green_room": "connector", "beat_stage": "main"})


def iid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "kairull:m07:" + label))


base._iid = iid

ROOM_TABLE = [
    ("backstage", "后台走廊", "backstage", "main", [1, 14, 24, 10]),
    ("green_room", "候场室", "green_room", "connector", [25, 16, 10, 8]),
    ("beat_stage", "节拍舞台", "beat_stage", "main", [35, 3, 44, 21]),
]
ROOMS = [{"room_id": rid, "display_name": name, "decor_profile": prof, "role": role, "rect": rect,
          "primary_landmark": prof} for rid, name, prof, role, rect in ROOM_TABLE]
base.LAYER_SPECS["Rooms"] = base.LayerSpec(2, {
    i + 1: (rid.title().replace("_", ""), "#7A5A9A") for i, (rid, *_rest) in enumerate(ROOM_TABLE)}, 0.18)

# 后台走廊的 4 级钢梯：上到枪手所在的器材平台
STAIRS = [{"stair_id": "backstage_stair", "room_id": "backstage", "bottom_cell": [13, FLOOR_ROW],
           "top_cell": [17, FLOOR_ROW - 2], "direction": "right_up", "step_run_px": 32, "step_rise_px": 16,
           "steps": 4, "collision_mode": "one_way_heightfield", "enemy_spawns_allowed": False}]

# 实体：(c, 脚底行, 值) 1 出生 2 出口 3 近战 4 枪手 5 货箱
ENTITIES = [
    (3, 22, 1), (77, 22, 2),
    (7, 22, 5), (10, 22, 3), (21, 20, 4),
]

# 舞台（世界像素）：地面 y = FLOOR_ROW*32；判定线在舞台左段；Boss 脚底中点在右段
STAGE_LEFT, STAGE_RIGHT = 35 * TS, (35 + 44) * TS
FLOOR_Y = FLOOR_ROW * TS
BOSS_ARENA = {
    "room_id": "beat_stage",
    "stage_rect": [STAGE_LEFT, 4 * TS, 44 * TS, FLOOR_Y - 4 * TS],
    "floor_y": FLOOR_Y,
    "judge_x": STAGE_LEFT + 9 * TS,                 # 判定线：玩家站位（地面画两个判定环）
    "lane_ground_y": FLOOR_Y - 36,                  # 两条音符轨中心（与 Boss 号角口高度一致）
    "lane_air_y": FLOOR_Y - 140,                   # 上层轨：中间隔板（离地 104）之上，隔板顶面即上层站位
    "boss_feet": [STAGE_RIGHT - 6 * TS, FLOOR_Y],   # Boss 精灵脚底中点（atlas 面朝右，运行时水平翻转朝左）
    "player_start": [STAGE_LEFT + 4 * TS, FLOOR_Y],
    "chart": "res://assets/boss/beat_warden_chart.json",
    "music": "res://assets/bgm/final_stand.ogg",           # 用户用 Suno 生成（免费、非商用）
    "boss_atlas": "res://assets/boss/beat_warden/atlas.json",
    "exit_requires_boss": True,
}


def seed_document() -> dict:
    grids = {name: base._blank() for name in base.LAYER_SPECS}
    fill, put = base._fill, base._put
    col = grids["Collision"]
    trav = grids["Traversal"]
    fill(col, 0, 0, W - 1, H - 1, 1)
    for value, room in enumerate(ROOMS, 1):
        x, y, w, h = room["rect"]
        right, floor = x + w - 1, y + h - 1
        fill(grids["Rooms"], x, y, right, floor, value)
        fill(col, x, y + 1, right, floor - 1, 0)
        fill(trav, x, floor - 1, right, floor - 1, 1)

    def plat(x0: int, x1: int, row: int) -> None:
        fill(col, x0, row, x1, row, 2)
        fill(trav, x0, row - 1, x1, row - 1, 1)

    # R1：钢梯上端的器材平台（枪手守位）
    plat(17, 24, FLOOR_ROW - 2)
    for stair in STAIRS:
        bx, by = stair["bottom_cell"]
        tx, ty = stair["top_cell"]
        put(col, tx, ty, 2)
        for i in range(stair["steps"]):
            sx, sy = bx + i, by - 1 - i // 2
            put(grids["Architecture"], sx, sy, 6)
            put(trav, sx, sy, 3)
        for yy in range(ty, by):
            for xx in range(bx, tx):
                if grids["Traversal"][yy][xx] == 1:
                    put(trav, xx, yy, 0)
    for x, row, value in ENTITIES:
        put(grids["Entities"], x, row, value)
    # 灯：后台/候场室挂顶灯；舞台由专用背景 + 随拍灯带表现，不挂工业顶灯
    for room in ROOMS[:2]:
        x, y, w, h = room["rect"]
        for lx in range(x + 3, x + w - 2, 7):
            put(grids["Lights"], lx, y + 1, 1 + (lx // 7) % 3)

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
    fields = [("RoomMetadata", ROOMS), ("StairMetadata", STAIRS), ("BossArena", BOSS_ARENA)]
    for uid, (name, value) in enumerate(fields, 31):
        field_def = copy.deepcopy(SCHEMA["defs"]["levelFields"][0])
        field_def.update({"identifier": name, "uid": uid, "doc": "05 节拍广播塔的正式 LDtk 运行合同"})
        doc["defs"]["levelFields"].append(field_def)
        level["fieldInstances"].append({"__identifier": name, "__tile": None, "__type": "String",
            "__value": json.dumps(value, ensure_ascii=False), "defUid": uid, "realEditorValues": []})
    base.checkpoint_contract.add_single_checkpoint(doc, base.MapError)
    return doc


def validate_rooms(room_grid: list[int], metadata: list[dict]) -> list[dict]:
    """本关三房：后台走廊 / 候场室 / 44×21 舞台；唯一、互不重叠、与 IntGrid 一致。"""
    if len(metadata) != len(ROOM_TABLE):
        raise base.MapError("节拍广播塔必须为 3 房")
    used: set[tuple[int, int]] = set()
    for expected, room in enumerate(metadata, 1):
        x, y, w, h = room["rect"]
        limits = {"main": (20, 44, 8, 22), "connector": (8, 18, 6, 12)}[room["role"]]
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


def validate_arena(doc: dict) -> dict:
    level = doc["levels"][0]
    arena = base._metadata(level, "BossArena")
    layers = {l["__identifier"]: l["intGridCsv"] for l in level["layerInstances"]}
    col, ents = layers["Collision"], layers["Entities"]
    stage = next(r for r in ROOMS if r["room_id"] == arena["room_id"])
    sx, sy, sw, sh = stage["rect"]
    # 舞台地面必须是一整条实心平地（节奏战不允许坑洞），且判定线/Boss 均在舞台内
    for c in range(sx, sx + sw):
        if col[FLOOR_ROW * W + c] != 1 or any(col[r * W + c] != 0 for r in range(sy + 1, FLOOR_ROW)):
            raise base.MapError(f"舞台 c{c} 必须是平整实心地面且上方全空")
    for key in ("judge_x", "boss_feet", "player_start"):
        x = arena[key] if key == "judge_x" else arena[key][0]
        if not (sx * TS < x < (sx + sw) * TS):
            raise base.MapError(f"BossArena.{key} 不在舞台内")
    if not arena["judge_x"] + 400 < arena["boss_feet"][0]:
        raise base.MapError("判定线离 Boss 太近，音符没有足够飞行距离")
    if any(ents[r * W + c] in (3, 4) for r in range(sy, sy + sh) for c in range(sx, sx + sw)):
        raise base.MapError("舞台内不放杂兵：节奏战只有 Boss")
    return arena


def compile_document(doc: dict, source_hash: str) -> str:
    arena = validate_arena(doc)
    base.checkpoint_contract.validate(doc, base.MapError)
    result = base._validate_and_compile(doc, source_hash)
    result = result.replace("正式第一关编译数据", "05 节拍广播塔编译数据").replace("m01_protocol_quarantine", "m07_beat_tower")
    result += "\n## 节奏 Boss 舞台（世界像素）：判定线、两条音符轨、Boss 脚底位置与谱面/配乐资源路径。\n"
    result += "const BOSS_ARENA: Dictionary = " + json.dumps(arena, ensure_ascii=False, indent=2) + "\n"
    result += "const TACTICAL_OBJECTS: Array[Dictionary] = []\n"
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
            print("M07_MAP_DRY: PASS")
            return 0
        if args.seed:
            if SOURCE.exists():
                raise base.MapError("拒绝覆盖现有 M07 LDtk")
            doc = seed_document()
            compile_document(doc, "pre-write-validation")
            SOURCE.write_bytes((json.dumps(doc, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        compiled = compile_path()
        if args.write:
            OUTPUT.write_bytes(compiled.encode("utf-8"))
        if args.check and (not OUTPUT.exists() or OUTPUT.read_bytes().decode("utf-8") != compiled):
            raise base.MapError("M07 LDtk 与 generated 不同步")
        print(f"M07_MAP_RESULT: PASS | {W}x{H} | {len(ROOMS)} rooms | "
              f"{sum(1 for e in ENTITIES if e[2] in (3, 4))} guards + boss")
        return 0
    except (OSError, ValueError, KeyError, base.MapError) as exc:
        print("M07_MAP_RESULT: FAIL | " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
