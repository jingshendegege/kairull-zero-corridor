"""重载装卸工（替换 FreightInspector 美术）：驼背重装近战兵 + 液压长柄钩。

运行：blender -b --factory-startup -P loader.py -- <输出目录>
动画与帧数与 freight_inspector.gd 合同一致：idle 4 / alert 5 / run 8 / windup 4 / attack 6 / recover 4 / death 6。
alert/recover 在游戏里只显示首帧与末帧；attack 逻辑 8 tick、有效窗 tick 2–6 对应画面第 1–3 帧的挥击。
双手用两段 IK 贴住钩柄；前摇/挥击时钩尖炽热发光（危险预告）。
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bl_rig as R  # noqa: E402

ANIMS = {"idle": 4, "alert": 5, "run": 8, "windup": 4, "attack": 6, "recover": 4, "death": 6}
SHOULDER_Z = 22.0
L1, L2 = 11.0, 12.0
R.RES_X = 160            # 挥钩前伸较远，画布加宽
R.RES_Y = 128            # 前摇把钩举过头顶，画布加高
R.BASELINE = 120


def build() -> None:
    R.reset_scene()
    J, P = R.joint, R.part
    J("root", None, (0, 0, 37))
    J("spine", "root", (0, 0, 4))
    J("neck", "spine", (4, 0, 25))
    J("head", "neck", (2, 0, 3))
    J("sh_n", "spine", (0, -15, SHOULDER_Z))
    J("el_n", "sh_n", (0, 0, -L1))
    J("sh_f", "spine", (0, 15, SHOULDER_Z))
    J("el_f", "sh_f", (0, 0, -L1))
    J("tool", "spine", (10, -10, 8))
    J("hip_n", "root", (0, -7, 0))
    J("kn_n", "hip_n", (0, 0, -15))
    J("an_n", "kn_n", (0, 0, -15))
    J("hip_f", "root", (0, 7, 0))
    J("kn_f", "hip_f", (0, 0, -15))
    J("an_f", "kn_f", (0, 0, -15))

    # 远侧
    P("far_thigh", "hip_f", "cyl", (6.8, 15), (0, 0, -7.5), material="cloth", rank=1)
    P("far_shin", "kn_f", "cyl", (6.2, 15), (0, 0, -7.5), material="armor", rank=1)
    P("far_boot", "an_f", "box", (17, 12, 9), (3.5, 0, -3.5), material="boot", rank=1, bevel=2)
    P("far_upper", "sh_f", "cyl", (5.4, L1), (0, 0, -L1 / 2), material="cloth", rank=0)
    P("far_fore", "el_f", "cyl", (5.6, L2), (0, 0, -L2 / 2), material="armor", rank=0)
    P("far_hand", "el_f", "sph", (4.6, 4.4, 4.6), (0, 0, -L2), material="glove", rank=0)
    P("far_pad", "sh_f", "box", (13, 9, 7), (0, 2, 2), material="plate", rank=0, bevel=2)
    # 背架
    P("rack", "spine", "box", (7, 26, 24), (-15.5, 0, 12), material="plate", rank=1, bevel=1.5)
    # 背后两根排气管 + 手臂液压管
    P("exhaust_a", "spine", "cyl", (2.4, 9), (-17, -6, 25.5), material="plate", rank=1)
    P("exhaust_b", "spine", "cyl", (2.4, 7), (-17, 6, 24.5), material="plate", rank=1)
    P("exhaust_cap", "spine", "cyl", (3, 2), (-17, -6, 30.5), material="hazard", rank=2)
    # 躯干（宽厚、驼背）
    P("pelvis", "root", "box", (19, 25, 11), (0, 0, 0), material="cloth", rank=2, bevel=2)
    P("chest", "spine", "box", (25, 30, 26), (2, 0, 12), material="armor", rank=3, bevel=5)
    P("chest_panel", "spine", "box", (4, 18, 9), (12.8, 0, 13), material="hazard", rank=4, bevel=1.5)
    P("collar", "neck", "cyl", (8.5, 5), (0, 0, -1), material="cloth", rank=4)
    # 头：焊接式头盔 + 青色窄缝 + 顶部品红信标
    P("helmet", "head", "sph", (10, 10, 9.5), (0, 0, 6), material="armor", rank=6, segments=12)
    P("face", "head", "box", (6, 14, 11), (7, 0, 4), material="mask", rank=7, bevel=2)
    P("slit", "head", "box", (2.4, 12, 2.4), (10.2, 0, 7), material="visor", rank=8)
    P("breather", "head", "cyl", (3.2, 5), (10.5, 0, 0), rot=(0, 90, 0), material="hazard", rank=8)
    P("beacon_base", "head", "cyl", (3.6, 2.4), (-1, 0, 15.6), material="metal", rank=7)
    P("beacon", "head", "sph", (3.2, 3.2, 3.4), (-1, 0, 18.4), material="lamp", rank=8, segments=8)
    # 近侧腿
    P("near_thigh", "hip_n", "cyl", (7, 15), (0, 0, -7.5), material="cloth", rank=5)
    P("near_knee", "kn_n", "sph", (5.6, 5.6, 5), (3.4, 0, 0.5), material="plate", rank=6)
    P("near_shin", "kn_n", "cyl", (6.4, 15), (0, 0, -7.5), material="armor", rank=5)
    P("near_boot", "an_n", "box", (17.5, 12.5, 9.5), (3.5, 0, -3.5), material="boot", rank=6, bevel=2)
    # 液压长柄钩（近侧）
    P("shaft", "tool", "cyl", (2.8, 42), (15, 0, 0), rot=(0, 90, 0), material="metal", rank=10)
    P("grip", "tool", "cyl", (3.3, 9), (4, 0, 0), rot=(0, 90, 0), material="mask", rank=10)
    P("band", "tool", "cyl", (3.5, 3.4), (22, 0, 0), rot=(0, 90, 0), material="hazard", rank=10)
    P("piston", "tool", "box", (17, 4.4, 4.4), (26, 0, 4.2), material="metal", rank=10, bevel=0.6)
    P("hook_neck", "tool", "box", (7.5, 7.5, 17), (37, 0, -5.5), material="metal", rank=10, bevel=1)
    P("hook_base", "tool", "box", (14, 7.5, 6.5), (32.5, 0, -13.5), material="metal", rank=10, bevel=1)
    P("hook_tip", "tool", "box", (5.5, 7.5, 10), (27, 0, -9), rot=(0, -20, 0), material="metal", rank=10, bevel=1)
    P("hook_hot", "tool", "box", (6.1, 7.9, 6.6), (26.6, 0, -7.2), rot=(0, -20, 0), material="hot", rank=11)
    P("hook_hot2", "tool", "box", (14.6, 7.9, 2), (32.5, 0, -16.2), material="hot", rank=11)
    # 近侧手臂（在武器前）
    P("near_pad", "sh_n", "box", (14, 9.5, 7.5), (0, -2, 2), material="plate", rank=12, bevel=2)
    P("near_upper", "sh_n", "cyl", (5.6, L1), (0, 0, -L1 / 2), material="cloth", rank=11)
    P("near_fore", "el_n", "cyl", (5.8, L2), (0, 0, -L2 / 2), material="armor", rank=12)
    P("near_piston", "el_n", "cyl", (1.6, L2 + 4), (-4.5, -4, -L2 / 2 + 2), material="metal", rank=13)
    P("near_hand", "el_n", "sph", (5.2, 5, 5.2), (0, 0, -L2), material="glove", rank=13)
    R.freeze_rest()


# ---------------------------------------------------------------- IK 与姿势
def _theta(dx: float, dz: float) -> float:
    """rest 朝下的肢体转到方向 (dx,dz) 所需的 ry（度）。"""
    return math.degrees(math.atan2(-dx, -dz))


def ik_arm(target_x: float, target_z: float, bend: float = 1.0) -> tuple[float, float]:
    """脊柱空间内：肩在 (0, SHOULDER_Z)，手到达 (target_x, target_z)。返回 (肩 ry, 肘 ry)。"""
    dx, dz = target_x, target_z - SHOULDER_Z
    d = min(max(math.hypot(dx, dz), 1e-3), L1 + L2 - 0.05)
    a = math.degrees(math.acos(max(-1.0, min(1.0, (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d)))))
    base = _theta(dx, dz)
    sh = base + bend * a
    # 肘点
    ex = -math.sin(math.radians(sh)) * L1
    ez = -math.cos(math.radians(sh)) * L1
    el_world = _theta(dx - ex, dz - ez)
    return sh, el_world - sh


def grip_point(tool_loc, tool_ry: float, along: float) -> tuple[float, float]:
    t = math.radians(tool_ry)
    return tool_loc[0] + along * math.cos(t), tool_loc[2] - along * math.sin(t)


def with_hands(p: dict, tool_loc, tool_ry: float, near_at=3.0, far_at=13.0) -> dict:
    p["tool"] = {"ry": tool_ry, "loc": tool_loc}
    nx, nz = grip_point(tool_loc, tool_ry, near_at)
    fx, fz = grip_point(tool_loc, tool_ry, far_at)
    s, e = ik_arm(nx, nz, 1.0)
    p["sh_n"], p["el_n"] = {"ry": s}, {"ry": e}
    s, e = ik_arm(fx, fz, 1.0)
    p["sh_f"], p["el_f"] = {"ry": s}, {"ry": e}
    return p


def legs(p: dict, hn, kn, an, hf, kf, af) -> dict:
    p["hip_n"], p["kn_n"], p["an_n"] = {"ry": hn}, {"ry": kn}, {"ry": an}
    p["hip_f"], p["kn_f"], p["an_f"] = {"ry": hf}, {"ry": kf}, {"ry": af}
    return p


def base(z=36.0, lean=14.0, head=-8.0, x=0.0) -> dict:
    return {"root": {"loc": (x, 0, z)}, "spine": {"ry": lean}, "head": {"ry": head}}


GUARD_TOOL = ((9, -10, 6), 38.0)


def pose_idle(i: int) -> dict:
    b = [0.0, 0.4, 0.8, 1.0][i]
    p = base(36.0 - b, 14 + b * 1.5)
    loc, ry = GUARD_TOOL
    with_hands(p, (loc[0], loc[1], loc[2] - b * 0.5), ry + b)
    return legs(p, -14, 20, -6, 16, 16, -30)


def pose_alert(i: int) -> dict:
    t = [0.0, 0.3, 0.6, 0.85, 1.0][i]
    p = base(36.0 - 1.5 * t, 14 + 8 * t, -8 + 6 * t)
    loc, ry = GUARD_TOOL
    with_hands(p, (loc[0] + 2 * t, loc[1], loc[2] + 4 * t), ry - 30 * t)
    return legs(p, -14 - 6 * t, 20 + 10 * t, -6, 16 + 4 * t, 16 + 6 * t, -30)


RUN_LEG = [(-34, 10, 6), (-18, 14, -2), (4, 22, -10), (22, 34, -18),
           (30, 64, -24), (10, 94, -28), (-22, 76, -10), (-36, 30, 8)]
RUN_BOB = [0.0, 0.8, 1.6, 0.8, 0.0, 0.8, 1.6, 0.8]


def pose_run(i: int) -> dict:
    p = base(35.0 + RUN_BOB[i], 24, -14)
    sw = [0, 1, 2, 1, 0, -1, -2, -1][i]
    with_hands(p, (7, -10, 7), 58 + 3 * sw)   # 钩子斜拖在身前下方
    hn, kn, an = RUN_LEG[i]
    hf, kf, af = RUN_LEG[(i + 4) % 8]
    return legs(p, hn, kn, an, hf, kf, af)


# 前摇：钩子抡到头后上方，重心后坐
WINDUP_KEYS = [((8, -10, 12), -20.0, 8, 36.0), ((4, -10, 22), -80.0, 0, 35.0),
               ((0, -10, 30), -118.0, -8, 34.5), ((-2, -10, 33), -132.0, -12, 34.0)]


def pose_windup(i: int) -> dict:
    loc, ry, lean, z = WINDUP_KEYS[i]
    p = base(z, lean, -4)
    with_hands(p, loc, ry)
    return legs(p, -24, 30, -8, 26, 22, -34)


# 挥击：头后 → 过顶 → 砸向前下方（第 1–3 帧为有效窗）→ 随势
ATTACK_KEYS = [((0, -10, 32), -125.0, -6, 34.0, 0), ((8, -10, 30), -60.0, 10, 33.0, 2),
               ((14, -10, 18), 10.0, 26, 31.5, 5), ((14, -10, 8), 48.0, 32, 30.5, 7),
               ((12, -10, 4), 62.0, 34, 30.0, 8), ((11, -10, 4), 64.0, 32, 30.5, 8)]


def pose_attack(i: int) -> dict:
    loc, ry, lean, z, x = ATTACK_KEYS[i]
    p = base(z, lean, 4, x)
    with_hands(p, loc, ry)
    return legs(p, -40, 26, 10, 30, 30, -38)   # 近腿大步前踏


def pose_recover(i: int) -> dict:
    t = [0.0, 0.35, 0.7, 1.0][i]
    loc0, ry0 = (12, -10, 4), 64.0
    loc1, ry1 = GUARD_TOOL
    loc = tuple(a + (b - a) * t for a, b in zip(loc0, loc1))
    p = base(30.5 + 5.5 * t, 32 - 18 * t, 4 - 12 * t, 8 * (1 - t))
    with_hands(p, loc, ry0 + (ry1 - ry0) * t)
    return legs(p, -40 + 26 * t, 26 - 6 * t, 10 - 16 * t, 30 - 14 * t, 30 - 14 * t, -38 + 8 * t)


# 倒地：被打得后仰 → 侧身砸地（背架转到身后）
DEATH_ROOT = [(-16, 0.0, 37.0), (-42, -3.0, 32.0), (-70, -6.0, 26.0), (-92, -8.0, 21.0),
              (-88, -8.0, 22.5), (-90, -8.0, 21.0)]
DEATH_T = [0.12, 0.35, 0.65, 0.92, 1.0, 1.0]


def pose_death(i: int) -> dict:
    ang, x, z = DEATH_ROOT[i]
    t = DEATH_T[i]
    p = {"root": {"loc": (x, 0, z), "ry": ang},
         "spine": {"ry": 14 - 18 * t, "rz": -70 * t}, "head": {"ry": -8 - 12 * t, "rz": 10 * t}}
    loc, ry = GUARD_TOOL
    with_hands(p, (loc[0] + 4 * t, loc[1], loc[2] + 6 * t), ry + 50 * t)
    return legs(p, -14 - 16 * t, 20 + 34 * t, -6 - 10 * t, 16 - 18 * t, 16 - 10 * t, -30 + 20 * t)


POSES = {"idle": pose_idle, "alert": pose_alert, "run": pose_run, "windup": pose_windup,
         "attack": pose_attack, "recover": pose_recover, "death": pose_death}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    wanted = argv[1:] or list(ANIMS)
    build()
    for anim in wanted:
        for i in range(ANIMS[anim]):
            R.pose(POSES[anim](i))
            hot = anim == "windup" and i >= 2 or anim == "attack" and i <= 3
            R.set_visible(["hook_hot", "hook_hot2"], hot)
            R.render_pair(out, f"{anim}_{i}")
    R.write_parts(out, {"anims": {a: ANIMS[a] for a in wanted}, "res": [R.RES_X, R.RES_Y],
                        "baseline": R.BASELINE})
    print("LOADER_RENDER_DONE", out)


if __name__ == "__main__":
    main()
