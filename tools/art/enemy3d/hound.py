"""检疫猎犬（QuarantineHound）：四足机械猎犬，冲刺飞扑型敌人。Blender 内建模 + 逐帧摆姿势渲染。

运行：blender -b --factory-startup -P hound.py -- <输出目录>
动画与帧数（合同见 godot/maps/ENEMY-HOUND-AND-BEAT-BOSS.md）：
idle 4 / alert 4 / run 6 / windup 4 / pounce 4 / recover 4 / death 6。格 160×96，脚底第 88 行。
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bl_rig as R  # noqa: E402

ANIMS = {"idle": 4, "alert": 4, "run": 6, "windup": 4, "pounce": 4, "recover": 4, "death": 6}
R.RES_X, R.RES_Y, R.BASELINE = 160, 96, 88
HIP_Z = 25.0
UPPER, LOWER = 12.0, 12.0


def build() -> None:
    R.reset_scene()
    J, P = R.joint, R.part
    J("root", None, (0, 0, HIP_Z))
    J("neck", "root", (19, 0, 5))
    J("head", "neck", (5, 0, 5))
    J("tail", "root", (-17, 0, 5))
    for side, y in (("n", -7.5), ("f", 7.5)):
        J(f"sh_{side}", "root", (15, y, -2))
        J(f"el_{side}", f"sh_{side}", (0, 0, -UPPER))
        J(f"hp_{side}", "root", (-15, y, -2))
        J(f"hk_{side}", f"hp_{side}", (0, 0, -UPPER))
    rank_side = {"f": 0, "n": 9}
    for side in ("f",):
        _legs(P, side, rank_side[side])
    # 躯干：前胸厚、后腰收，侧腹琥珀警示条
    P("tail_a", "tail", "cyl", (2.4, 13), (-5, 0, 2.5), rot=(0, 65, 0), material="plate", rank=2)
    P("tail_tip", "tail", "sph", (2.8, 2.6, 2.6), (-10.5, 0, 5.2), material="lamp_cyan", rank=2)
    P("waist", "root", "box", (22, 15, 13), (-8, 0, 0), material="plate", rank=3, bevel=3)
    P("chest", "root", "box", (22, 18, 17), (9, 0, 1), material="armor", rank=4, bevel=4)
    P("spine_plate", "root", "box", (30, 10, 3), (1, 0, 9.5), material="plate", rank=5, bevel=1)
    P("back_light", "root", "box", (3, 3, 2), (-4, 0, 11.5), material="lamp_cyan", rank=6)
    P("flank_hz", "root", "box", (14, 1.4, 3), (4, -9.2, 0), material="hazard", rank=6)
    P("flank_hz2", "root", "box", (10, 1.4, 3), (-8, -7.8, 0), material="hazard", rank=6)
    P("neck_c", "neck", "cyl", (4.8, 9), (1, 0, 1), rot=(0, 35, 0), material="plate", rank=5)
    # 头：长吻 + 下颌 + 品红眼缝 + 两只尖耳
    P("skull", "head", "box", (13, 12, 10), (1, 0, 2), material="armor", rank=7, bevel=2.5)
    P("snout", "head", "box", (10, 8, 6), (10, 0, 0), material="plate", rank=7, bevel=1.5)
    P("jaw", "head", "box", (9, 7, 3), (8.5, 0, -3.5), material="metal", rank=7, bevel=0.8)
    P("visor", "head", "box", (3, 11, 2.4), (6.2, 0, 4.2), material="lamp", rank=8)
    P("ear_n", "head", "cone", (3.2, 0.6, 7), (-2, -4, 9), rot=(0, -20, 0), material="plate", rank=8)
    P("ear_f", "head", "cone", (3.2, 0.6, 7), (-2, 4, 9), rot=(0, -20, 0), material="plate", rank=6)
    _legs(P, "n", rank_side["n"])
    R.freeze_rest()


def _legs(P, side: str, base: int) -> None:
    mat_up = "plate"
    P(f"fu_{side}", f"sh_{side}", "cone", (3.2, 4.4, UPPER), (0, 0, -UPPER / 2), material=mat_up, rank=base + 1)
    P(f"fl_{side}", f"el_{side}", "cone", (2.4, 3.2, LOWER), (0, 0, -LOWER / 2), material="metal", rank=base + 1)
    P(f"fp_{side}", f"el_{side}", "box", (7, 5, 3), (2, 0, -LOWER - 0.5), material="armor", rank=base + 2, bevel=1)
    P(f"bu_{side}", f"hp_{side}", "cone", (3.4, 5.2, UPPER), (0, 0, -UPPER / 2), material=mat_up, rank=base + 1)
    P(f"bl_{side}", f"hk_{side}", "cone", (2.4, 3.2, LOWER), (0, 0, -LOWER / 2), material="metal", rank=base + 1)
    P(f"bp_{side}", f"hk_{side}", "box", (7, 5, 3), (2, 0, -LOWER - 0.5), material="armor", rank=base + 2, bevel=1)


def root_pose(z=HIP_Z, pitch=0.0, x=0.0, roll=0.0) -> dict:
    return {"loc": (x, 0, z), "ry": pitch, "rx": roll}


def legs(p: dict, fn, fnk, ff, ffk, bn, bnk, bf, bfk) -> dict:
    """前腿肩/肘、后腿髋/膝（度，负 = 向前摆）。"""
    p["sh_n"], p["el_n"] = {"ry": fn}, {"ry": fnk}
    p["sh_f"], p["el_f"] = {"ry": ff}, {"ry": ffk}
    p["hp_n"], p["hk_n"] = {"ry": bn}, {"ry": bnk}
    p["hp_f"], p["hk_f"] = {"ry": bf}, {"ry": bfk}
    return p


def stand(p: dict) -> dict:
    return legs(p, -4, 8, 4, 6, 8, -14, 2, -10)


def pose_idle(i: int) -> dict:
    sniff = [0.0, 1.0, 0.4, -0.3][i]
    p = {"root": root_pose(HIP_Z - 0.2 * abs(sniff)), "neck": {"ry": 18 + 12 * sniff},
         "head": {"ry": 6 * sniff}, "tail": {"rz": 18 * [0, 1, 0, -1][i], "ry": -10}}
    return stand(p)


def pose_alert(i: int) -> dict:
    t = [0.0, 0.4, 0.8, 1.0][i]
    p = {"root": root_pose(HIP_Z - 3 * t, 4 * t), "neck": {"ry": 8 - 18 * t},
         "head": {"ry": -4 * t}, "tail": {"ry": -30 * t}}
    return legs(p, -10 * t, 20 * t, -4 * t, 16 * t, 14 * t, -30 * t, 10 * t, -26 * t)


RUN = [  # (前近, 前远, 后近, 后远) 肩/髋角；奔跑为"旋转式"跑姿
    (-40, -25, 30, 45), (-20, -5, 10, 25), (15, 25, -20, -10),
    (40, 45, -40, -30), (20, 30, -10, 5), (-15, -5, 20, 35),
]


def pose_run(i: int) -> dict:
    fn, ff, bn, bf = RUN[i]
    pitch = [4, 0, -4, -6, -2, 3][i]
    lift = [0.0, 1.2, 2.2, 1.2, 0.0, 0.6][i]
    p = {"root": root_pose(HIP_Z - 1 + lift, pitch), "neck": {"ry": -6}, "head": {"ry": 0},
         "tail": {"ry": -40}}

    def knee(a, front):
        return (abs(a) * 0.6 + 10) if front else -(abs(a) * 0.7 + 10)
    return legs(p, fn, knee(fn, True), ff, knee(ff, True), bn, knee(bn, False), bf, knee(bf, False))


def pose_windup(i: int) -> dict:
    t = [0.3, 0.6, 0.85, 1.0][i]
    p = {"root": root_pose(HIP_Z - 9 * t, 12 * t, -3 * t), "neck": {"ry": -16 * t}, "head": {"ry": -4},
         "tail": {"ry": -50 * t}}
    return legs(p, -24 * t, 46 * t, -18 * t, 40 * t, 40 * t, -80 * t, 34 * t, -74 * t)


def pose_pounce(i: int) -> dict:
    pitch = [-22, -10, 4, 14][i]
    z = [HIP_Z + 6, HIP_Z + 9, HIP_Z + 7, HIP_Z + 3][i]
    p = {"root": root_pose(z, pitch), "neck": {"ry": -10}, "head": {"ry": 6},
         "tail": {"ry": -70 + 10 * i}}
    fore = [-80, -85, -70, -45][i]
    hind = [70, 60, 45, 25][i]
    return legs(p, fore, 12, fore + 10, 14, hind, -8, hind - 10, -10)


def pose_recover(i: int) -> dict:
    t = [1.0, 0.7, 0.4, 0.1][i]
    p = {"root": root_pose(HIP_Z - 7 * t, -8 * t), "neck": {"ry": 20 * t}, "head": {"ry": 12 * t * (-1 if i % 2 else 1)},
         "tail": {"ry": -20}}
    return legs(p, -48 * t, 40 * t, -40 * t, 34 * t, 20 * t, -40 * t, 14 * t, -34 * t)


# 倒地：被击飞后仰 → 空中 → 砸地 → 趴倒摊平（前腿前伸、后腿后伸、头贴地），侧视角最易读
DEATH = [(-18, HIP_Z + 1), (-34, HIP_Z + 5), (-10, HIP_Z - 6), (0, 10.5), (0, 9.5), (0, 9.0)]


def pose_death(i: int) -> dict:
    pitch, z = DEATH[i]
    t = min(1.0, i / 3)
    p = {"root": {"loc": (-4 * min(i, 3), 0, z), "ry": pitch}, "neck": {"ry": 10 + 45 * t},
         "head": {"ry": 20 * t}, "tail": {"ry": -10 + 20 * t}}
    return legs(p, -30 - 55 * t, 10 - 10 * t, -20 - 60 * t, 8 - 8 * t,
                30 + 55 * t, -10 + 10 * t, 20 + 62 * t, -8 + 8 * t)


POSES = {"idle": pose_idle, "alert": pose_alert, "run": pose_run, "windup": pose_windup,
         "pounce": pose_pounce, "recover": pose_recover, "death": pose_death}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    wanted = argv[1:] or list(ANIMS)
    build()
    for anim in wanted:
        for i in range(ANIMS[anim]):
            R.pose(POSES[anim](i))
            R.render_pair(out, f"{anim}_{i}")
    R.write_parts(out, {"anims": {a: ANIMS[a] for a in wanted}, "res": [R.RES_X, R.RES_Y],
                        "baseline": R.BASELINE})
    print("HOUND_RENDER_DONE", out)


if __name__ == "__main__":
    main()
