"""节拍监察官（BEAT WARDEN）：节奏 Boss，巨型舞台音箱机甲。Blender 内建模 + 逐帧摆姿势渲染。

运行：blender -b --factory-startup -P beat_warden.py -- <输出目录>
造型：带轮舞台底座 → 紫黑音箱柜（近侧大低音喇叭，中心品红灯随拍闪）→ 前方两支黄铜号角
（下=地面轨发射口，上=空中轨发射口）→ 两条锤臂敲号角"击鼓发射"→ 分体头罩（决战时张开露出青色核心）。
面朝 +X（右），游戏内放在舞台右侧并水平翻转朝左。合同见 godot/maps/ENEMY-HOUND-AND-BEAT-BOSS.md §B。
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bl_rig as R  # noqa: E402

ANIMS = {"idle": 4, "fire_ground": 3, "fire_air": 3, "hurt": 3, "expose": 4, "core": 4, "death": 6}
R.RES_X, R.RES_Y, R.BASELINE = 288, 272, 262
BODY_Z = 34.0                     # 音箱柜底面离地高度（坐在底座上）
GROUND_LANE_Z, AIR_LANE_Z = 36.0, 108.0   # 两条音符轨中心离地高度（与运行时一致）


def _part(name, parent, shape, size, loc=(0, 0, 0), rot=(0, 0, 0), material="armor", rank=0, bevel=0.0,
          segments=16):
    """bl_rig.part 的包装：bl_rig 的倒角宽度作用在缩放前的单位立方体上，大盒体会被削成多面体；
    这里把"像素倒角"换算成局部宽度（按最长边），保持大柜体方正。"""
    if shape == "box" and bevel > 0:
        bevel = bevel / max(size)
    return R.part(name, parent, shape, size, loc, rot, material, rank, bevel, segments)


def build() -> None:
    R.reset_scene()
    J, P = R.joint, _part
    J("root", None, (0, 0, 0))
    # ---- 底座：舞台功放箱 + 四个滚轮 + 琥珀警示边 + 地面轨号角
    P("wheel_fb", "root", "cyl", (13, 8), (-52, 30, 13), rot=(90, 0, 0), material="rubber", rank=1)
    P("wheel_ff", "root", "cyl", (13, 8), (52, 30, 13), rot=(90, 0, 0), material="rubber", rank=1)
    P("pedestal", "root", "box", (150, 64, 30), (0, 0, 19), material="plate", rank=3, bevel=3)
    P("ped_hz", "root", "box", (140, 2, 5), (0, -32.5, 30), material="hazard", rank=4)
    P("ped_grill", "root", "box", (60, 2, 12), (-30, -32.5, 17), material="rubber", rank=4)
    P("ped_lamp", "root", "box", (8, 2, 5), (26, -33, 17), material="lamp_cyan", rank=5)
    P("wheel_nb", "root", "cyl", (13, 8), (-52, -32, 13), rot=(90, 0, 0), material="rubber", rank=6)
    P("wheel_nf", "root", "cyl", (13, 8), (52, -32, 13), rot=(90, 0, 0), material="rubber", rank=6)
    P("hub_nb", "root", "cyl", (5, 9), (-52, -33, 13), rot=(90, 0, 0), material="metal", rank=7)
    P("hub_nf", "root", "cyl", (5, 9), (52, -33, 13), rot=(90, 0, 0), material="metal", rank=7)
    J("horn_g", "root", (72, 0, GROUND_LANE_Z))
    P("horn_g_neck", "horn_g", "cyl", (7, 16), (0, 0, 0), rot=(0, 90, 0), material="plate", rank=5)
    P("horn_g_bell", "horn_g", "cone", (7, 17, 20), (18, 0, 0), rot=(0, 90, 0), material="brass", rank=6)
    P("horn_g_mouth", "horn_g", "cyl", (14, 1.2), (28.5, 0, 0), rot=(0, 90, 0), material="rubber", rank=7)
    # ---- 音箱柜（随拍上下弹）
    J("body", "root", (0, 0, BODY_Z))
    P("cab", "body", "box", (96, 60, 122), (0, 0, 61), material="cab", rank=5, bevel=4)
    P("cab_trim_t", "body", "box", (98, 62, 5), (0, 0, 120), material="plate", rank=6, bevel=1)
    P("cab_trim_b", "body", "box", (98, 62, 5), (0, 0, 3), material="plate", rank=6, bevel=1)
    P("cab_hz", "body", "box", (4, 2, 90), (-44, -30.8, 62), material="hazard", rank=6)
    J("woofer", "body", (-2, -30, 44))
    P("woof_ring", "woofer", "cyl", (31, 4), (0, -1.5, 0), rot=(90, 0, 0), material="metal", rank=7, segments=24)
    P("woof_cone", "woofer", "cone", (27, 9, 7), (0, -2, 0), rot=(-90, 0, 0), material="rubber", rank=8, segments=24)
    P("woof_cap", "woofer", "sph", (8, 3, 8), (0, -4.5, 0), material="lamp", rank=9)
    J("tweeter", "body", (-2, -30, 98))
    P("tw_ring", "tweeter", "cyl", (15, 4), (0, -1.5, 0), rot=(90, 0, 0), material="metal", rank=7, segments=20)
    P("tw_cone", "tweeter", "cone", (12, 4, 5), (0, -2, 0), rot=(-90, 0, 0), material="rubber", rank=8, segments=20)
    P("tw_cap", "tweeter", "sph", (4, 2, 4), (0, -4, 0), material="lamp_cyan", rank=9)
    for i, z in enumerate((78, 84, 90)):          # 前面板 VU 灯条
        P(f"vu_{i}", "body", "box", (2, 20 - 4 * i, 3), (48.5, -8, z), material="lamp_cyan" if i else "lamp", rank=6)
    J("horn_a", "body", (50, 0, AIR_LANE_Z - BODY_Z))
    P("horn_a_neck", "horn_a", "cyl", (7, 12), (2, 0, 0), rot=(0, 90, 0), material="plate", rank=6)
    P("horn_a_bell", "horn_a", "cone", (7, 17, 20), (18, 0, 0), rot=(0, 90, 0), material="brass", rank=7)
    P("horn_a_mouth", "horn_a", "cyl", (14, 1.2), (28.5, 0, 0), rot=(0, 90, 0), material="rubber", rank=8)
    # ---- 头：分体头罩（前/后两半，底部铰接），内部核心
    J("head", "body", (0, 0, 122))
    P("neck", "head", "cyl", (16, 8), (0, 0, 3), material="plate", rank=6)
    J("core", "head", (0, 0, 20))
    P("core_orb", "core", "sph", (15, 15, 15), (0, 0, 0), material="core", rank=5)
    P("core_ring", "core", "cyl", (18, 3), (0, 0, -9), material="metal", rank=4)
    J("shell_f", "head", (3, 0, 6))
    P("shell_f_box", "shell_f", "box", (24, 46, 32), (12, 0, 15), material="cab", rank=8, bevel=4)
    P("visor_side", "shell_f", "box", (18, 1.6, 5), (13, -23.2, 20), material="lamp", rank=9)
    P("visor_front", "shell_f", "box", (1.6, 36, 5), (24.2, 0, 20), material="lamp", rank=9)
    P("shell_f_trim", "shell_f", "box", (25, 47, 3), (12, 0, 2), material="plate", rank=9, bevel=0.8)
    J("shell_b", "head", (-3, 0, 6))
    P("shell_b_box", "shell_b", "box", (24, 46, 32), (-12, 0, 15), material="cab", rank=8, bevel=4)
    P("shell_b_trim", "shell_b", "box", (25, 47, 3), (-12, 0, 2), material="plate", rank=9, bevel=0.8)
    P("mast", "shell_b", "cyl", (1.6, 30), (-14, 0, 44), material="metal", rank=7)
    P("dish", "shell_b", "cone", (9, 2, 3), (-14, 0, 44), rot=(0, -30, 0), material="plate", rank=7)
    P("mast_tip", "shell_b", "sph", (3, 3, 3), (-14, 0, 60), material="lamp", rank=8)
    # ---- 两条锤臂：远侧（先画）与近侧
    for side, y, base in (("f", 38.0, 0), ("n", -38.0, 10)):
        J(f"sh_{side}", "body", (30, y, 104))
        J(f"el_{side}", f"sh_{side}", (0, 0, -30))
        J(f"mal_{side}", f"el_{side}", (0, 0, -28))
        P(f"pad_{side}", f"sh_{side}", "sph", (11, 9, 11), (0, 0, 0), material="plate", rank=base + 2)
        P(f"ua_{side}", f"sh_{side}", "cyl", (6, 30), (0, 0, -15), material="metal", rank=base + 1)
        P(f"elb_{side}", f"el_{side}", "sph", (6, 6, 6), (0, 0, 0), material="plate", rank=base + 2)
        P(f"fa_{side}", f"el_{side}", "box", (11, 11, 28), (0, 0, -14), material="cab", rank=base + 2, bevel=2)
        P(f"mal_head_{side}", f"mal_{side}", "cyl", (10, 18), (0, 0, -4), rot=(90, 0, 0), material="metal", rank=base + 3)
        P(f"mal_cap_{side}", f"mal_{side}", "cyl", (10.5, 3), (0, -9 if side == "n" else 9, -4), rot=(90, 0, 0),
          material="rubber", rank=base + 4)
    R.freeze_rest()


def arms(p: dict, n_sh, n_el, f_sh, f_el, n_mal=0.0, f_mal=0.0) -> dict:
    """肩/肘 ry（度；负 = 向前抬）。"""
    p["sh_n"], p["el_n"], p["mal_n"] = {"ry": n_sh}, {"ry": n_el}, {"ry": n_mal}
    p["sh_f"], p["el_f"], p["mal_f"] = {"ry": f_sh}, {"ry": f_el}, {"ry": f_mal}
    return p


def body(z=0.0, pitch=0.0, x=0.0) -> dict:
    return {"loc": (x, 0, BODY_Z + z), "ry": pitch}


def rest(p: dict) -> dict:
    return arms(p, -10, -55, -6, -50)


def pose_idle(i: int) -> dict:
    # 0 = 拍点（下沉 + 喇叭外推）→ 1 回弹 → 2 最高 → 3 回落
    bob = [-3.0, 0.0, 1.5, 0.5][i]
    push = [-3.0, -1.0, 0.0, 0.0][i]
    p = {"body": body(bob), "woofer": {"loc": (-2, -30 + push, 44)}, "tweeter": {"loc": (-2, -30 + push * 0.5, 98)},
         "head": {"ry": [2, 0, -1, 0][i]}}
    return arms(p, -10 + bob * 2, -55 - bob * 2, -6 - bob, -50 + bob)


def pose_fire_ground(i: int) -> dict:
    # 近侧锤臂：高举 → 砸向底座号角 → 回弹；地面号角后坐
    n = [(-160, -10, 30), (-25, -20, -40), (-35, -40, -10)][i]
    p = {"body": body([0, -2, -1][i], [-3, 5, 2][i]), "horn_g": {"loc": (72 - [0, 4, 1][i], 0, GROUND_LANE_Z)},
         "woofer": {"loc": (-2, -30 - [0, 3, 1][i], 44)}}
    return arms(p, n[0], n[1], -6, -50, n[2])


def pose_fire_air(i: int) -> dict:
    # 远侧锤臂：后拉 → 前冲砸上号角 → 回收
    f = [(-170, 10, 30), (-100, -10, -40), (-110, -30, -10)][i]
    p = {"body": body([1, -1, 0][i], [-2, 4, 1][i]), "horn_a": {"loc": (50 - [0, 4, 1][i], 0, AIR_LANE_Z - BODY_Z)},
         "tweeter": {"loc": (-2, -30 - [0, 2, 1][i], 98)}}
    return arms(p, -14, -58, f[0], f[1], 0, f[2])


def pose_hurt(i: int) -> dict:
    t = [1.0, 0.6, 0.25][i]
    p = {"body": body(-2 * t, 9 * t, -3 * t), "head": {"ry": 10 * t}, "shell_f": {"ry": -8 * t},
         "woofer": {"loc": (-2, -30 + 2 * t, 44)}}
    return arms(p, 20 * t - 10, -40 * t - 55, 22 * t - 6, -40 * t - 50)


def _open(t: float) -> dict:
    return {"shell_f": {"ry": 62 * t, "loc": (3 + 6 * t, 0, 6)}, "shell_b": {"ry": -62 * t, "loc": (-3 - 6 * t, 0, 6)},
            "core": {"loc": (0, 0, 20 + 6 * t)}}


def pose_expose(i: int) -> dict:
    # 降台露核：柜体沉入底座 → 头罩向两侧掀开 → 核心升起；双臂张开护核
    t = [0.2, 0.5, 0.8, 1.0][i]
    p = {"body": body(-22 * t), "head": {"ry": 0}, **_open(t)}
    return arms(p, -10 - 35 * t, -55 + 40 * t, -6 - 30 * t, -50 + 30 * t)


def pose_core(i: int) -> dict:
    bob = [-2.0, 0.0, 1.0, 0.0][i]
    p = {"body": body(-22 + bob), **_open(1.0), "woofer": {"loc": (-2, -30 + [-3, -1, 0, 0][i], 44)}}
    p["core"] = {"loc": (0, 0, 26 + bob * 1.5)}
    return arms(p, -45 + bob * 2, -15, -36 - bob, -20)


def pose_death(i: int) -> dict:
    # 过载：核心暴露下抽搐 → 柜体前倾砸地 → 头罩脱落、臂垂下
    t = min(1.0, i / 4)
    p = {"body": body(-22 - 18 * t, [4, -6, 12, 20, 24, 25][i], 6 * t), **_open(1.0 - 0.4 * t)}
    p["head"] = {"loc": (10 * t, 0, 122 - 30 * t), "ry": 40 * t}
    p["core"] = {"loc": (0, 0, 26 - 20 * t)}
    return arms(p, -45 + 60 * t, -15 + 10 * t, -36 + 50 * t, -20 + 15 * t, 40 * t, -30 * t)


POSES = {"idle": pose_idle, "fire_ground": pose_fire_ground, "fire_air": pose_fire_air, "hurt": pose_hurt,
         "expose": pose_expose, "core": pose_core, "death": pose_death}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    wanted = argv[1:] or list(ANIMS)
    build()
    extra = {}
    for anim in wanted:
        for i in range(ANIMS[anim]):
            R.pose(POSES[anim](i))
            R.render_pair(out, f"{anim}_{i}")
            if anim == "idle" and i == 1:          # 静止姿态下两支号角口的像素坐标 → 音符出生点
                import bpy
                for key, obj in (("horn_ground_px", "horn_g_mouth"), ("horn_air_px", "horn_a_mouth")):
                    extra[key] = R.world_to_pixel(bpy.data.objects[obj].matrix_world.translation)
            if anim == "core" and i == 1:
                import bpy
                extra["core_px"] = R.world_to_pixel(bpy.data.objects["core_orb"].matrix_world.translation)
    R.write_parts(out, {"anims": {a: ANIMS[a] for a in wanted}, "res": [R.RES_X, R.RES_Y],
                        "baseline": R.BASELINE, **extra})
    print("BEAT_WARDEN_RENDER_DONE", out)


if __name__ == "__main__":
    main()
