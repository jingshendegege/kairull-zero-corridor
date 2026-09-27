"""04 排风脊线屋顶装饰精灵（原创像素画，幂等）。输出 godot/assets/maps/m06/decor_*.png。

全部为背景装饰（画在碰撞层之后，不参与玩法）；主体压暗、青色轮廓光、琥珀/品红小灯做点缀，
不抢敌人与危险预警的视觉层级。
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "godot/assets/maps/m06"
BODY, BODY_D, RIM, EDGE = "#1b2536", "#131b28", "#2e4560", "#0b1019"
CYAN, AMBER, MAGENTA = "#3fb7c9", "#d9a14a", "#ff4fa3"


def hx(c: str, a: int = 255):
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), a)


class Canvas:
    def __init__(self, w: int, h: int):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()
        self.w, self.h = w, h

    def rect(self, x0, y0, x1, y1, col):
        for y in range(max(0, y0), min(self.h, y1 + 1)):
            for x in range(max(0, x0), min(self.w, x1 + 1)):
                self.px[x, y] = hx(col)

    def box(self, x0, y0, x1, y1):
        """带轮廓与左上轮廓光的实体块。"""
        self.rect(x0, y0, x1, y1, EDGE)
        self.rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, BODY)
        self.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 1, RIM)
        self.rect(x0 + 1, y0 + 1, x0 + 1, y1 - 1, RIM)
        self.rect(x1 - 2, y0 + 2, x1 - 1, y1 - 1, BODY_D)


def ac_unit() -> Image.Image:
    c = Canvas(64, 40)
    c.box(0, 8, 63, 39)
    for x in range(6, 30, 3):                       # 百叶
        c.rect(x, 14, x, 34, BODY_D)
    cx, cy, r = 45, 23, 11                          # 圆形风扇罩
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r:
                c.px[x, y] = hx(EDGE if d > r - 1 else "#0e141e" if d > 3 else RIM)
    for k in range(-r + 2, r - 1, 3):
        c.rect(cx - r + 2, cy + k, cx + r - 2, cy + k, BODY_D)
    c.rect(4, 4, 12, 8, EDGE)                       # 顶部接管
    c.rect(5, 4, 11, 5, RIM)
    c.px[58, 12] = hx(CYAN)
    return c.img


def vent_stack() -> Image.Image:
    c = Canvas(24, 104)
    c.box(5, 8, 18, 103)
    c.rect(2, 4, 21, 9, EDGE)                       # 防雨帽
    c.rect(3, 5, 20, 6, RIM)
    for y in range(18, 100, 16):
        c.rect(6, y, 17, y + 1, BODY_D)
        c.rect(6, y + 2, 17, y + 2, RIM)
    for y in range(40, 46):                         # 琥珀警示环
        for x in range(6, 18):
            c.px[x, y] = hx(AMBER if (x + y) % 4 < 2 else "#7a5020")
    c.px[11, 2] = hx(MAGENTA)
    c.px[12, 2] = hx(MAGENTA)
    return c.img


def antenna() -> Image.Image:
    c = Canvas(28, 168)
    top, base = 6, 167
    for y in range(top, base + 1):
        t = (y - top) / (base - top)
        half = int(2 + 10 * t)
        c.px[14 - half, y] = hx(RIM)
        c.px[14 + half, y] = hx(EDGE)
        if (y - top) % 10 == 0:
            c.rect(14 - half, y, 14 + half, y, BODY)
            # 斜撑
        if (y - top) % 10 < 5:
            k = (y - top) % 10
            xs = 14 - half + int((2 * half) * k / 5)
            c.px[max(0, min(27, xs)), y] = hx(BODY)
    c.rect(13, 0, 15, 6, EDGE)
    c.rect(13, 0, 15, 1, MAGENTA)
    c.rect(8, 60, 20, 66, EDGE)                     # 天线盘
    c.rect(9, 61, 19, 62, RIM)
    return c.img


def water_tank() -> Image.Image:
    c = Canvas(64, 96)
    for lx in (8, 30, 54):                          # 支腿
        c.rect(lx, 44, lx + 2, 95, EDGE)
        c.rect(lx, 44, lx, 95, RIM)
    for y in (62, 80):
        c.rect(8, y, 56, y + 1, BODY_D)
    c.box(2, 10, 61, 46)
    for x in range(8, 58, 8):                       # 罐身竖缝
        c.rect(x, 12, x, 44, BODY_D)
    c.rect(6, 4, 57, 10, EDGE)                      # 锥顶
    c.rect(10, 1, 53, 4, EDGE)
    c.rect(11, 2, 52, 2, RIM)
    c.px[32, 28] = hx(AMBER)
    c.px[33, 28] = hx(AMBER)
    return c.img


def sign_board() -> Image.Image:
    """屋顶灯牌：像素字"排风"意象用条形灯带 + 箭头，不写真实企业/品牌名。"""
    c = Canvas(128, 56)
    for lx in (18, 106):
        c.rect(lx, 36, lx + 3, 55, EDGE)
        c.rect(lx, 36, lx, 55, RIM)
    c.box(0, 0, 127, 38)
    c.rect(4, 4, 123, 34, "#0c121c")
    for i, x0 in enumerate(range(10, 94, 14)):      # 青色灯带条 + 右指箭头
        col = CYAN if i % 2 == 0 else "#2a8494"
        c.rect(x0, 12, x0 + 9, 16, col)
        c.rect(x0, 22, x0 + 9, 26, "#2a8494" if i % 2 == 0 else CYAN)
    for k in range(9):
        c.rect(100 + k, 19 - k // 1 // 2, 100 + k, 19 + k // 2, MAGENTA)
    c.rect(98, 18, 110, 20, MAGENTA)
    return c.img


def beacon() -> Image.Image:
    c = Canvas(12, 6)
    c.rect(0, 1, 4, 5, EDGE)
    c.rect(1, 2, 3, 4, MAGENTA)
    c.px[2, 2] = hx("#ffd0e8")
    c.rect(6, 1, 10, 5, EDGE)
    c.rect(7, 2, 9, 4, "#5a2140")
    return c.img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in [("decor_ac_unit.png", ac_unit), ("decor_vent_stack.png", vent_stack),
                     ("decor_antenna.png", antenna), ("decor_water_tank.png", water_tank),
                     ("decor_sign.png", sign_board), ("decor_beacon.png", beacon)]:
        img = fn()
        img.save(OUT / name)
        print("wrote", name, img.size)


if __name__ == "__main__":
    main()
