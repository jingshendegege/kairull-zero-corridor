"""检疫步枪兵（替换 GruntGunner 美术）：Blender 内建模 + 逐帧摆姿势渲染。

运行：blender -b --factory-startup -P rifleman.py -- <输出目录> [动画名 ...]
动画与帧数与 grunt.gd 合同一致：idle 3 / alert 4 / run 8 / aim 5 / fire 4 / death 6。
后摇 recover 按用户既定规则复用 idle，不另做。
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bl_rig as R  # noqa: E402

ANIMS = {"idle": 3, "alert": 4, "run": 8, "aim": 5, "fire": 4, "death": 6}


def build() -> None:
    R.reset_scene()
    J, P = R.joint, R.part
    J("root", None, (0, 0, 40))
    J("spine", "root", (0, 0, 3))
    J("neck", "spine", (2, 0, 27))
    J("head", "neck", (1.5, 0, 3.5))
    J("sh_n", "spine", (0, -14, 22))
    J("el_n", "sh_n", (0, 0, -11))
    J("sh_f", "spine", (0, 14, 22))
    J("el_f", "sh_f", (0, 0, -11))
    J("gun", "spine", (9, -12, 12))
    J("hip_n", "root", (0, -7, 0))
    J("kn_n", "hip_n", (0, 0, -16))
    J("an_n", "kn_n", (0, 0, -16))
    J("hip_f", "root", (0, 7, 0))
    J("kn_f", "hip_f", (0, 0, -16))
    J("an_f", "kn_f", (0, 0, -16))

    # 远侧肢体
    P("far_thigh", "hip_f", "cone", (6.6, 8.2, 16), (0, 0, -8), material="pants", rank=1)
    P("far_knee", "kn_f", "box", (6, 11, 9), (4.4, 0, -1), rot=(0, -12, 0), material="armor", rank=1, bevel=1.8)
    P("far_shin", "kn_f", "cone", (6, 7.4, 16), (0, 0, -8), material="pants", rank=1)
    P("far_boot", "an_f", "box", (19, 12, 10), (3.5, 0, -4), material="boot", rank=1, bevel=2.4)
    P("far_upper", "sh_f", "cone", (5.2, 6.4, 11), (0, 0, -5.5), material="cloth", rank=0)
    P("far_fore", "el_f", "box", (10, 10, 12), (0.5, 0, -6), material="cloth", rank=0, bevel=2.5)
    P("far_hand", "el_f", "box", (9, 9, 8), (0.8, 0, -13.5), material="glove", rank=0, bevel=2)
    P("far_pad", "sh_f", "box", (14, 10, 8), (0, 1.5, 1.5), rot=(10, 0, 0), material="armor", rank=0, bevel=2.8)
    # 背部过滤罐
    P("tank", "spine", "cyl", (6.2, 21), (-16, 3, 13), material="metal", rank=1)
    P("tank_top", "spine", "sph", (6.2, 6.2, 3.2), (-16, 3, 23.5), material="metal", rank=1)
    P("tank_band", "spine", "cyl", (6.6, 3), (-16, 3, 16), material="amber", rank=1)
    # 躯干：深蓝制服 + 炭黑防弹背心 + 三个琥珀挂包 + 斜挎带
    P("pelvis", "root", "box", (19, 23, 12), (0, 0, 0), material="pants", rank=2, bevel=2.5)
    P("jacket", "spine", "box", (22, 27, 27), (1, 0, 12), material="cloth", rank=3, bevel=4)
    P("vest", "spine", "box", (25, 25, 19), (2, 0, 14), material="armor", rank=4, bevel=3)
    P("strap", "spine", "box", (26, 3.2, 3.2), (2.5, -12.6, 14), rot=(0, -40, 0), material="amber", rank=6)
    P("pouch_a", "spine", "box", (6.5, 7.5, 8), (14.5, -7, 6.5), material="amber", rank=6, bevel=1.4)
    P("pouch_b", "spine", "box", (6.5, 7.5, 8), (14.5, 1.5, 6.5), material="amber", rank=6, bevel=1.4)
    P("pouch_c", "spine", "box", (6, 7, 7), (-1, -13.6, 4), material="amber", rank=6, bevel=1.4)
    P("radio", "spine", "box", (5, 4, 9), (-6, -13, 20), material="metal", rank=5, bevel=1)
    P("antenna", "spine", "cyl", (0.8, 10), (-7, -13, 29), material="metal", rank=5)
    P("collar", "neck", "cyl", (8, 5), (0, 0, -0.5), material="cloth", rank=5)
    # 头：头盔 + 防毒面具 + 目镜 + 品红指示灯
    P("helmet", "head", "sph", (11.5, 11.5, 10), (0, 0, 7.5), material="armor", rank=7, segments=12)
    P("helmet_rim", "head", "cyl", (12.4, 2.6), (0, 0, 3.4), material="armor", rank=7)
    P("mask", "head", "sph", (7, 8.5, 7.2), (8, 0, 1.5), material="mask", rank=8, segments=10)
    P("snout", "head", "cyl", (4.4, 6.5), (13.5, 0, -0.8), rot=(0, 90, 0), material="mask", rank=8)
    P("filter", "head", "cyl", (4.4, 3.4), (17.2, 0, -1.2), rot=(0, 90, 0), material="amber", rank=9)
    P("goggle", "head", "box", (4, 17, 4.6), (9.2, 0, 7.6), material="visor", rank=9)
    P("goggle_frame", "head", "box", (3, 18, 6.4), (8.4, 0, 7.6), material="mask", rank=8)
    P("lamp", "head", "box", (3.4, 3.4, 3.4), (-2, -6, 17.8), material="lamp", rank=10)
    # 近侧腿（屈膝）
    P("near_thigh", "hip_n", "cone", (6.8, 8.4, 16), (0, 0, -8), material="pants", rank=5)
    P("near_knee", "kn_n", "box", (6.2, 11.5, 9.5), (4.6, 0, -1), rot=(0, -12, 0), material="armor", rank=6, bevel=1.8)
    P("near_shin", "kn_n", "cone", (6.2, 7.6, 16), (0, 0, -8), material="pants", rank=5)
    P("near_boot", "an_n", "box", (19.5, 12.5, 10.5), (3.5, 0, -4), material="boot", rank=6, bevel=2.4)
    P("near_lace", "an_n", "box", (6, 12.9, 2.4), (5.5, 0, -0.5), material="amber", rank=7)
    # 步枪（近侧，挡在胸前）
    P("gun_body", "gun", "box", (24, 5.5, 9), (7, 0, 0), material="gun", rank=11, bevel=1)
    P("gun_guard", "gun", "box", (11, 6, 6.5), (23, 0, 0.5), material="gun", rank=11, bevel=1)
    P("gun_barrel", "gun", "cyl", (2, 10), (32.5, 0, 1), rot=(0, 90, 0), material="gun", rank=11)
    P("gun_mag", "gun", "box", (5.5, 4.5, 11), (8, 0, -8.5), rot=(0, -14, 0), material="gun", rank=11, bevel=0.8)
    P("gun_stock", "gun", "box", (12, 5, 7.5), (-10.5, 0, -1.5), material="gun", rank=11, bevel=1)
    P("gun_sight", "gun", "box", (7, 3, 3.4), (7, 0, 6), material="gun", rank=11)
    P("gun_light", "gun", "box", (2.6, 3, 2.4), (18, 0, 5), material="visor", rank=12)
    P("flash_a", "gun", "sph", (8, 4.5, 4.4), (43, 0, 1), material="flash", rank=15, segments=8)
    P("flash_b", "gun", "sph", (3.2, 4.5, 8), (40, 0, 1), material="flash", rank=15, segments=8)
    # 近侧手臂
    P("near_pad", "sh_n", "box", (15, 10.5, 8.5), (0, -1.5, 1.5), rot=(-10, 0, 0), material="armor", rank=13, bevel=2.8)
    P("near_upper", "sh_n", "cone", (5.4, 6.6, 11), (0, 0, -5.5), material="cloth", rank=12)
    P("near_fore", "el_n", "box", (10.5, 10.5, 12), (0.5, 0, -6), material="cloth", rank=13, bevel=2.5)
    P("near_hand", "el_n", "box", (9.5, 9.5, 8.5), (0.8, 0, -13.5), material="glove", rank=14, bevel=2)
    R.freeze_rest()


# ---------------------------------------------------------------- 姿势
def lerp(a, b, t):
    return a + (b - a) * t


def blend(p0: dict, p1: dict, t: float) -> dict:
    out = {}
    for k in set(p0) | set(p1):
        a, b = p0.get(k, {}), p1.get(k, {})
        d = {}
        for c in ("rx", "ry", "rz"):
            if c in a or c in b:
                d[c] = lerp(a.get(c, 0.0), b.get(c, 0.0), t)
        if "loc" in a or "loc" in b:
            la = a.get("loc", R.JOINTS[k]["_rest"])
            lb = b.get("loc", R.JOINTS[k]["_rest"])
            d["loc"] = tuple(lerp(x, y, t) for x, y in zip(la, lb))
        out[k] = d
    return out


def root_at(z=46.0, x=0.0):
    return {"loc": (x, 0, z)}


# 低持枪待机：枪口朝前下，双手托枪
READY = {
    "root": root_at(38.5),
    "spine": {"ry": 6},
    "head": {"ry": -4},
    "gun": {"ry": 16},
    "sh_n": {"ry": 22}, "el_n": {"ry": -95},
    "sh_f": {"ry": -38}, "el_f": {"ry": -52},
    "hip_n": {"ry": -20}, "kn_n": {"ry": 30}, "an_n": {"ry": -10},
    "hip_f": {"ry": 16}, "kn_f": {"ry": 22}, "an_f": {"ry": -38},
}
# 抵肩瞄准：枪水平、头贴枪
AIM = {
    "root": root_at(37.5),
    "spine": {"ry": 10},
    "head": {"ry": 6},
    "gun": {"ry": 0, "loc": (10, -12, 18)},
    "sh_n": {"ry": 38}, "el_n": {"ry": -125},
    "sh_f": {"ry": -62}, "el_f": {"ry": -30},
    "hip_n": {"ry": -20}, "kn_n": {"ry": 24}, "an_n": {"ry": -4},
    "hip_f": {"ry": 22}, "kn_f": {"ry": 14}, "an_f": {"ry": -36},
}


def pose_idle(i: int) -> dict:
    p = blend(READY, READY, 0)
    breathe = [0.0, 0.6, 1.0][i]
    p["root"] = root_at(38.5 - breathe)
    p["spine"] = {"ry": 6 + breathe * 1.5}
    p["gun"] = {"ry": 16 + breathe * 2}
    return p


def pose_alert(i: int) -> dict:
    t = [0.0, 0.35, 0.75, 1.0][i]
    p = blend(READY, AIM, t * 0.55)
    p["head"] = {"ry": -4 - 10 * math.sin(t * math.pi)}
    return p


# 跑步关键帧（近腿相位）：0 触地前伸 / 2 支撑过身 / 4 后蹬 / 6 收腿前摆；远腿相差半周期
RUN_LEG = [  # (hip, knee, ankle)
    (-34, 8, 4), (-18, 12, -2), (4, 18, -10), (22, 30, -18),
    (30, 62, -26), (10, 96, -30), (-22, 78, -12), (-36, 30, 6),
]
RUN_BOB = [0.0, 0.8, 1.6, 0.8, 0.0, 0.8, 1.6, 0.8]


def pose_run(i: int) -> dict:
    p = blend(READY, READY, 0)
    hn, kn, an = RUN_LEG[i]
    hf, kf, af = RUN_LEG[(i + 4) % 8]
    p["root"] = root_at(36.5 + RUN_BOB[i], 0)
    p["spine"] = {"ry": 15}
    p["head"] = {"ry": -9}
    swing = [0, 1, 2, 1, 0, -1, -2, -1][i]
    p["gun"] = {"ry": 22 + 2 * swing}
    p["hip_n"], p["kn_n"], p["an_n"] = {"ry": hn}, {"ry": kn}, {"ry": an}
    p["hip_f"], p["kn_f"], p["an_f"] = {"ry": hf}, {"ry": kf}, {"ry": af}
    p["sh_n"] = {"ry": 22 + 3 * swing}
    p["sh_f"] = {"ry": -38 - 3 * swing}
    return p


def pose_aim(i: int) -> dict:
    t = [0.0, 0.3, 0.6, 0.85, 1.0][i]
    return blend(blend(READY, AIM, 0.55), AIM, t)


def pose_fire(i: int) -> dict:
    kick = [0.25, 1.0, 0.55, 0.15][i]   # 第 2 帧（i=1）出膛，对齐 grunt.gd FIRE_SHOT_TICK
    p = blend(AIM, AIM, 0)
    p["gun"] = {"ry": -7 * kick, "loc": (10 - 3.5 * kick, -12, 18 + kick)}
    p["spine"] = {"ry": 10 - 5 * kick}
    p["head"] = {"ry": 6 - 5 * kick}
    p["sh_n"] = {"ry": 38 + 6 * kick}
    return p


# 仰面平躺的终态（根关节转 -90°：局部"下"= 世界 +X，局部"后"= 世界向下）
LYING = {
    "spine": {"ry": -4, "rz": -72}, "head": {"ry": -18, "rz": 10},   # 躯干侧转朝镜头，背罐转到身后
    "gun": {"ry": 88, "loc": (16, -12, 10)},
    "sh_n": {"ry": 14}, "el_n": {"ry": -12},
    "sh_f": {"ry": 20}, "el_f": {"ry": -8},
    "hip_n": {"ry": -28}, "kn_n": {"ry": 52}, "an_n": {"ry": -18},   # 近腿膝盖微拱
    "hip_f": {"ry": -2}, "kn_f": {"ry": 6}, "an_f": {"ry": -10},     # 远腿伸直
}
# 倒地过程：中弹后仰踉跄 → 失衡 → 砸地 → 回弹 → 摊平
DEATH_ROOT = [(-14, 0.0, 41.0), (-40, -3.0, 36.0), (-70, -6.0, 27.0), (-92, -8.0, 20.0),
              (-88, -8.0, 21.5), (-90, -8.0, 20.0)]
DEATH_BLEND = [0.12, 0.35, 0.65, 0.92, 1.0, 1.0]


def pose_death(i: int) -> dict:
    ang, x, z = DEATH_ROOT[i]
    p = blend(READY, LYING, DEATH_BLEND[i])
    p["root"] = {"loc": (x, 0, z), "ry": ang}
    if i in (1, 2):  # 失衡时双臂甩开
        p["sh_n"] = {"ry": -40 if i == 1 else -20}
        p["el_n"] = {"ry": -30}
        p["sh_f"] = {"ry": -60 if i == 1 else -30}
        p["gun"] = {"ry": 40 if i == 1 else 70, "loc": (10, -11, 16 if i == 1 else 13)}
    return p


POSES = {"idle": pose_idle, "alert": pose_alert, "run": pose_run, "aim": pose_aim,
         "fire": pose_fire, "death": pose_death}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    wanted = argv[1:] or list(ANIMS)
    build()
    muzzle = {}
    for anim in wanted:
        for i in range(ANIMS[anim]):
            R.pose(POSES[anim](i))
            R.set_visible(["flash_a", "flash_b"], anim == "fire" and i == 1)
            R.render_pair(out, f"{anim}_{i}")
            if anim == "fire" and i == 1:
                import bpy
                bpy.context.view_layer.update()
                tip = bpy.data.objects["gun_barrel"].matrix_world @ R.mathutils.Vector((0, 0, 7))
                muzzle = {"fire_0_px": R.world_to_pixel(tip)}  # 键名沿用：出膛帧枪口
    R.write_parts(out, {"anims": {a: ANIMS[a] for a in wanted}, "res": [R.RES_X, R.RES_Y],
                        "baseline": R.BASELINE, **muzzle})
    print("RIFLEMAN_RENDER_DONE", out)


if __name__ == "__main__":
    main()
