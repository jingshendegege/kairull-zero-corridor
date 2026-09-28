"""旧机关重画：狙击炮台 / 光栅发射柱 / 压机 / 货梯台面 / 烟雾罐（原创像素画，逐像素几何，幂等）。

输出 godot/assets/maps/hazards/*.png。随状态变化的灯色、蓄力条、瞄准线与光束仍由代码绘制，
精灵上对应位置留深色灯槽。所有精灵面朝右，原点约定写在各函数注释里。
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "godot/assets/maps/hazards"

EDGE, DEEP = "#0b1017", "#151d27"
STEEL = ["#9aa8b5", "#6d7c8a", "#4b5764", "#323b46", "#222933"]
NAVY = ["#4a5f96", "#33446e", "#243152", "#172039"]
AMBER, AMBER_D = "#e6a13c", "#8a5a1e"
CYAN = "#7ff1e8"
GLASS = ["#3a6f86", "#244b5e", "#16303e"]


def hx(c: str, a: int = 255):
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), a)


class C:
    def __init__(self, w: int, h: int):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()
        self.w, self.h = w, h

    def r(self, x0, y0, x1, y1, col):
        for y in range(max(0, y0), min(self.h, y1 + 1)):
            for x in range(max(0, x0), min(self.w, x1 + 1)):
                self.px[x, y] = hx(col)

    def p(self, x, y, col):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = hx(col)

    def plate(self, x0, y0, x1, y1, ramp=STEEL):
        """带黑轮廓、左上受光边、右下暗边的钢板块。"""
        self.r(x0, y0, x1, y1, EDGE)
        self.r(x0 + 1, y0 + 1, x1 - 1, y1 - 1, ramp[2])
        self.r(x0 + 1, y0 + 1, x1 - 1, y0 + 1, ramp[0])
        self.r(x0 + 1, y0 + 1, x0 + 1, y1 - 1, ramp[1])
        self.r(x1 - 1, y0 + 2, x1 - 1, y1 - 1, ramp[3])
        self.r(x0 + 2, y1 - 1, x1 - 1, y1 - 1, ramp[3])

    def hazard(self, x0, y0, x1, y1, flip=False):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                k = (x - y) if flip else (x + y)
                self.p(x, y, AMBER if k % 6 < 3 else AMBER_D)

    def bolt(self, x, y):
        self.p(x, y, STEEL[0])
        self.p(x + 1, y + 1, STEEL[3])


def sniper_base() -> Image.Image:
    """48×60，原点=底边中点（x=24,y=60）。转台顶面在第 14 行 → 游戏内 y=-46，正好顶住机头底部；
    三脚架 + 装甲立柱 + 琥珀警示环。"""
    c = C(48, 60)
    for side in (-1, 1):                           # 两条斜支腿：从立柱肩部斜落到两侧脚垫
        for y in range(32, 56):
            t = (y - 32) / 24
            xa = int(round(24 + side * (6 + 13 * t)))
            c.r(xa - 2, y, xa + 2, y, EDGE)
            c.r(xa - 1, y, xa + 1, y, STEEL[2])
            c.p(xa - side, y, STEEL[1])
    c.plate(1, 54, 13, 59)                         # 脚垫
    c.plate(34, 54, 46, 59)
    c.plate(16, 20, 31, 59, NAVY)                  # 中央立柱
    c.hazard(17, 30, 30, 33)
    c.r(18, 40, 29, 40, NAVY[3])
    c.plate(12, 14, 35, 22)                        # 转台
    c.r(14, 17, 33, 17, STEEL[3])
    for x in (15, 22, 29):
        c.bolt(x, 19)
    return c.img


def sniper_head(dead: bool = False) -> Image.Image:
    """44×32 面朝右，原点=转台中心（x=18,y=30）。装甲机头 + 瞄准镜筒 + 顶部状态灯槽（代码填色）。"""
    c = C(44, 32)
    c.plate(2, 8, 34, 30, NAVY)                    # 机头外壳
    c.r(4, 22, 32, 22, NAVY[3])
    c.plate(8, 2, 26, 9)                           # 顶部瞄准镜
    c.r(26, 4, 30, 7, EDGE)                        # 镜筒前端
    c.r(27, 5, 29, 6, GLASS[0])
    c.r(12, 0, 18, 2, EDGE)                        # 灯槽（代码画状态色）
    c.r(13, 1, 17, 1, DEEP)
    c.r(24, 12, 33, 20, EDGE)                      # 枪管基座
    c.r(25, 13, 32, 19, STEEL[3])
    c.r(25, 13, 32, 13, STEEL[1])
    for x in range(5, 22, 4):                      # 散热格栅
        c.r(x, 13, x + 1, 19, EDGE)
    c.hazard(5, 24, 20, 27, flip=True)
    c.r(6, 11, 21, 11, STEEL[1])
    if dead:                                       # 损毁：裂缝 + 熄灭 + 焦黑
        for i in range(12):
            c.p(9 + i, 10 + i // 2, EDGE)
            c.p(10 + i, 10 + i // 2, "#2a1a14")
        c.r(26, 4, 30, 7, EDGE)
        c.r(24, 12, 33, 20, "#1b1e22")
        for x, y in ((14, 14), (16, 17), (22, 25), (8, 20)):
            c.p(x, y, "#5a3a22")
    return c.img


def sniper_barrel() -> Image.Image:
    """26×8 面朝右，原点=左端中点（x=0,y=4）；长度 26 = tactical_hazard.muzzle_position 的前伸量，枪口即出弹点。"""
    c = C(26, 8)
    c.r(0, 2, 25, 5, EDGE)
    c.r(1, 3, 24, 4, STEEL[2])
    c.r(1, 3, 24, 3, STEEL[0])
    c.r(6, 1, 14, 6, EDGE)
    c.r(7, 2, 13, 5, STEEL[3])
    for x in range(8, 13, 2):
        c.r(x, 2, x, 5, STEEL[1])
    c.r(20, 1, 25, 6, EDGE)
    c.r(21, 2, 24, 5, STEEL[2])
    c.p(23, 3, STEEL[0])
    return c.img


def laser_post() -> Image.Image:
    """14×36，原点=光束中心线左端对齐（x=7,y=18）。发射柱 + 中央镜头槽（代码填状态色）。"""
    c = C(14, 36)
    c.plate(1, 0, 12, 35, NAVY)
    c.r(3, 3, 10, 3, STEEL[1])
    c.hazard(2, 27, 11, 33)
    c.r(3, 13, 10, 22, EDGE)                       # 镜头框
    c.r(4, 14, 9, 21, GLASS[2])
    c.r(5, 15, 8, 20, DEEP)                        # 镜头（代码填色）
    c.bolt(3, 6)
    c.bolt(9, 6)
    return c.img


def press_head() -> Image.Image:
    """64×18，原点=左上（安装在压机顶部）。液压缸盖 + 两个缸体接口 + 中央状态灯槽。"""
    c = C(64, 18)
    c.plate(2, 0, 61, 15)
    c.r(4, 12, 59, 12, STEEL[3])
    c.hazard(4, 3, 14, 9)
    c.hazard(49, 3, 59, 9, flip=True)
    c.r(27, 4, 36, 9, EDGE)                        # 灯槽
    c.r(28, 5, 35, 8, DEEP)
    for x in (18, 44):
        c.r(x - 3, 14, x + 3, 17, EDGE)
        c.r(x - 2, 15, x + 2, 16, STEEL[1])
    for x in (6, 22, 40, 56):
        c.bolt(x, 11)
    return c.img


def press_plate() -> Image.Image:
    """64×24 压板：厚钢块 + 底缘琥珀警示齿 + 螺栓。"""
    c = C(64, 24)
    c.plate(0, 0, 63, 23)
    c.r(2, 5, 61, 5, STEEL[3])
    c.hazard(2, 16, 61, 21)
    for x in range(4, 62, 10):
        c.bolt(x, 9)
    c.r(2, 22, 61, 22, EDGE)
    return c.img


def lift_deck() -> Image.Image:
    """96×16 货梯台面：格栅板 + 两端琥珀护边 + 端部小灯。原点=左上（与平台顶面对齐）。"""
    c = C(96, 16)
    c.plate(0, 0, 95, 13)
    c.r(1, 1, 94, 1, "#c4dde0")
    for x in range(6, 90, 4):                      # 格栅
        c.r(x, 4, x + 1, 10, EDGE)
    c.hazard(1, 11, 14, 13)
    c.hazard(81, 11, 94, 13, flip=True)
    for x in (3, 92):
        c.r(x - 1, 5, x + 1, 8, EDGE)
        c.p(x, 6, CYAN)
        c.p(x, 7, "#2f8f96")
    c.r(10, 14, 85, 15, DEEP)                      # 台底加强筋
    return c.img


def smoke_canister() -> Image.Image:
    """14×20，原点=中心（x=7,y=11）。烟雾罐：灰绿罐身 + 青色环带 + 顶部安全栓。"""
    c = C(14, 20)
    c.r(2, 4, 11, 19, EDGE)
    c.r(3, 5, 10, 18, "#9fc4b8")
    c.r(3, 5, 4, 18, "#d3eee4")
    c.r(9, 6, 10, 18, "#6f958a")
    c.r(3, 10, 10, 12, "#2d8075")
    c.r(3, 11, 10, 11, "#58b7a6")
    c.r(4, 1, 9, 4, EDGE)                          # 顶盖
    c.r(5, 2, 8, 3, "#e8f0d0")
    c.r(9, 0, 13, 2, EDGE)                         # 拉环
    c.r(10, 1, 12, 1, "#cdd9a5")
    return c.img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    items = {"sniper_base.png": sniper_base(), "sniper_head.png": sniper_head(False),
             "sniper_head_dead.png": sniper_head(True), "sniper_barrel.png": sniper_barrel(),
             "laser_post.png": laser_post(), "press_head.png": press_head(), "press_plate.png": press_plate(),
             "lift_deck.png": lift_deck(), "smoke_canister.png": smoke_canister()}
    for name, img in items.items():
        img.save(OUT / name)
        print("wrote", name, img.size)


if __name__ == "__main__":
    main()
