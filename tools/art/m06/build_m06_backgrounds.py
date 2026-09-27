"""04 排风脊线视差背景（原创程序化像素画）。

低分辨率 384×256 绘制 → 最近邻 ×4 = 1536×1024；GameBackground 以 SCALE 0.75 显示，
即 3px 像素块，与 M01 背景的像素密度一致。固定随机种子，幂等可复跑。
输出 godot/assets/bg/m06/：
  M06_L0_sky.png   夜空（固定层）
  M06_L1_far.png   远景城市天际线 + 冷却塔（慢视差）
  M06_L2_mid.png   中景工业屋顶剪影（中视差）
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "godot/assets/bg/m06"
LW, LH, UP = 384, 256, 4

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hx(c: str) -> tuple[int, int, int, int]:
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), 255)


def dither_ramp(stops: list[tuple[float, str]], t: float, x: int, y: int) -> tuple:
    """按阈值矩阵在相邻色阶间抖动，得到像素画式渐变。"""
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t0 <= t <= t1:
            k = (t - t0) / max(1e-6, t1 - t0)
            return hx(c1) if k * 16 > BAYER[y % 4][x % 4] + 0.5 else hx(c0)
    return hx(stops[-1][1])


def upscale(img: Image.Image) -> Image.Image:
    return img.resize((img.width * UP, img.height * UP), Image.NEAREST)


# ---------------------------------------------------------------- L0 夜空
def sky() -> Image.Image:
    rnd = random.Random(606)
    img = Image.new("RGBA", (LW, LH))
    px = img.load()
    stops = [(0.0, "#060913"), (0.28, "#0a1122"), (0.55, "#101c33"), (0.8, "#182a44"), (1.0, "#22384f")]
    for y in range(LH):
        for x in range(LW):
            px[x, y] = dither_ramp(stops, y / (LH - 1), x, y)
    # 星星：稀疏，靠上更多；少数十字亮星
    for _ in range(260):
        x, y = rnd.randrange(LW), int(rnd.random() ** 1.7 * LH * 0.75)
        c = rnd.choice(["#8fa4c4", "#6d82a6", "#b9c9e0", "#5f7093"])
        px[x, y] = hx(c)
    for _ in range(14):
        x, y = rnd.randrange(4, LW - 4), rnd.randrange(4, int(LH * 0.45))
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            px[x + dx, y + dy] = hx("#dce8f5" if (dx, dy) == (0, 0) else "#7f94b8")
    # 月亮 + 光晕
    mx, my, mr = 292, 58, 21
    for y in range(my - mr - 16, my + mr + 17):
        for x in range(mx - mr - 16, mx + mr + 17):
            d = math.hypot(x - mx, y - my)
            if d <= mr:
                lx, ly = (x - mx + 7) / mr, (y - my + 6) / mr
                lit = 1.0 - min(1.0, math.hypot(lx, ly) * 0.75)
                crater = ((x * 7 + y * 13) % 29 == 0) or math.hypot(x - mx + 6, y - my - 4) < 4 \
                    or math.hypot(x - mx - 8, y - my + 7) < 3
                if crater:
                    lit -= 0.25
                col = "#c9d8e2" if lit > 0.62 else "#a7bccb" if lit > 0.35 else "#7f95a9"
                px[x, y] = hx(col)
            elif d <= mr + 16:
                k = 1.0 - (d - mr) / 16
                if k * 16 > BAYER[y % 4][x % 4] * 1.6 + 2:
                    px[x, y] = hx("#223550" if k > 0.5 else "#1a2a42")
    # 云带：水平长条，压住月亮下缘
    for band_y, length, x0, col in [(66, 150, 210, "#1a2a44"), (72, 110, 250, "#223556"),
                                    (120, 220, 20, "#16243b"), (126, 160, 60, "#1c2d49"),
                                    (170, 260, 90, "#1a2b44")]:
        for x in range(x0, min(LW, x0 + length)):
            thick = 2 + int(2 * math.sin(x * 0.07) + 1.5 * math.sin(x * 0.19 + band_y))
            for y in range(band_y, band_y + max(1, thick)):
                if 0 <= y < LH and (x - x0 > 6 and x0 + length - x > 6 or (x + y) % 2):
                    px[x, y] = hx(col)
    return img


# ---------------------------------------------------------------- L1 远景
def cooling_tower(px, cx: int, base_y: int, top_y: int, r_base: int, r_waist: int, r_top: int,
                  body: str, rim: str, dark: str) -> None:
    h = base_y - top_y
    for y in range(top_y, base_y + 1):
        t = (y - top_y) / h
        # 双曲面：顶部略收，腰在 0.35 处，底部外扩
        if t < 0.35:
            r = r_top + (r_waist - r_top) * (t / 0.35) ** 0.7
        else:
            r = r_waist + (r_base - r_waist) * ((t - 0.35) / 0.65) ** 1.6
        r = int(round(r))
        for x in range(cx - r, cx + r + 1):
            if 0 <= x < LW:
                edge = x - (cx - r)
                col = rim if edge < 2 else dark if x > cx + r * 0.35 else body
                if (y - top_y) % 11 == 0 and x > cx - r + 1:
                    col = dark
                px[x, y] = hx(col)


def steam(px, rnd, cx: int, top_y: int, width: int) -> None:
    for i in range(60):
        y = top_y - i
        drift = int(i * 0.45 + 3 * math.sin(i * 0.2))
        w = width + i // 3
        for x in range(cx - w // 2 + drift, cx + w // 2 + drift):
            if 0 <= x < LW and 0 <= y < LH:
                fade = 1.0 - i / 60
                if fade * 16 > BAYER[y % 4][x % 4] + rnd.random() * 3:
                    px[x, y] = hx("#2a3b55" if fade > 0.55 else "#1f2d45")


def far() -> Image.Image:
    rnd = random.Random(1606)
    img = Image.new("RGBA", (LW, LH), (0, 0, 0, 0))
    px = img.load()
    horizon = 214
    # 城市天际线
    x = 0
    while x < LW:
        w = rnd.randint(8, 22)
        h = rnd.randint(14, 58)
        top = horizon - h
        for xx in range(x, min(LW, x + w)):
            for yy in range(top, LH):
                px[xx, yy] = hx("#0d1523" if xx > x else "#142034")
        # 楼顶天线 / 水箱
        if rnd.random() < 0.35:
            ax = x + w // 2
            for yy in range(top - rnd.randint(4, 12), top):
                if 0 <= ax < LW:
                    px[ax, yy] = hx("#1a283f")
            if 0 <= ax < LW:
                px[ax, top - 12 if top - 12 >= 0 else 0] = hx("#ff4f6a")
        # 窗灯
        for yy in range(top + 3, LH - 4, 4):
            for xx in range(x + 2, min(LW, x + w) - 1, 3):
                if rnd.random() < 0.06:
                    px[xx, yy] = hx(rnd.choice(["#2c7f8c", "#8f6a36", "#3c8e98", "#5e4a2c"]))
        x += w + rnd.randint(0, 3)
    # 两座冷却塔 + 蒸汽 + 航空警示灯
    for cx, top, rb, rw, rt in [(84, 118, 34, 21, 24), (262, 104, 40, 25, 28)]:
        cooling_tower(px, cx, horizon + 8, top, rb, rw, rt, "#141f31", "#1f2e45", "#0f1726")
        steam(px, rnd, cx, top, rt * 2 - 6)
        for dx in (-rt + 3, rt - 3):
            px[cx + dx, top + 2] = hx("#ff4f6a")
    # 地平线下的远处灯带
    for x in range(0, LW, 2):
        if rnd.random() < 0.4:
            px[x, horizon + 12] = hx("#27405c")
    return img


# ---------------------------------------------------------------- L2 中景
def mid() -> Image.Image:
    rnd = random.Random(2606)
    img = Image.new("RGBA", (LW, LH), (0, 0, 0, 0))
    px = img.load()
    base = 232
    body, rim, lamp_c, amber = "#090e17", "#152536", "#c43d80", "#a8792e"

    def rect(x0, y0, x1, y1, col=body):
        for yy in range(max(0, y0), min(LH, y1 + 1)):
            for xx in range(max(0, x0), min(LW, x1 + 1)):
                px[xx, yy] = hx(col)

    # 连续屋顶女儿墙
    rect(0, base, LW - 1, LH - 1)
    for x in range(0, LW):
        px[x, base] = hx(rim)
    x = 4
    while x < LW - 10:
        kind = rnd.choice(["stack", "tank", "mast", "box", "stack"])
        if kind == "stack":          # 排气烟囱：细高 + 顶部环带
            w, h = rnd.randint(5, 8), rnd.randint(50, 96)
            rect(x, base - h, x + w, base)
            rect(x, base - h, x, base, rim)
            for yy in range(base - h + 4, base, 14):
                rect(x, yy, x + w, yy + 1, "#18283a")
            px[x + w // 2, base - h - 1] = hx(lamp_c)
            x += w + rnd.randint(10, 26)
        elif kind == "tank":         # 水塔：支腿 + 圆罐
            w, h = rnd.randint(18, 26), rnd.randint(34, 52)
            for lx in (x + 2, x + w - 2):
                rect(lx, base - h + 16, lx, base)
            rect(x + 3, base - h + 20, x + w - 3, base - h + 20)
            rect(x, base - h, x + w, base - h + 16)
            rect(x + 2, base - h - 3, x + w - 2, base - h)
            rect(x, base - h, x, base - h + 16, rim)
            px[x + w // 2, base - h + 8] = hx(amber)
            x += w + rnd.randint(12, 30)
        elif kind == "mast":         # 格构天线塔：斜撑 + 顶灯
            h = rnd.randint(70, 110)
            for yy in range(base - h, base):
                t = (yy - (base - h)) / h
                half = int(1 + 5 * t)
                px[x + 6 - half, yy] = hx(rim)
                px[x + 6 + half, yy] = hx(body)
                if (yy - base) % 6 == 0:
                    rect(x + 6 - half, yy, x + 6 + half, yy)
            px[x + 6, base - h - 1] = hx(lamp_c)
            px[x + 6, base - h - 2] = hx(lamp_c)
            x += 12 + rnd.randint(16, 34)
        else:                        # 设备箱 + 百叶
            w, h = rnd.randint(14, 30), rnd.randint(10, 22)
            rect(x, base - h, x + w, base)
            rect(x, base - h, x + w, base - h, rim)
            for yy in range(base - h + 3, base - 2, 3):
                rect(x + 2, yy, x + w - 2, yy, "#142233")
            x += w + rnd.randint(8, 24)
    # 电缆：下垂曲线连接桅杆顶附近
    for x0 in range(0, LW, 96):
        x1 = x0 + 90
        for xx in range(x0, min(LW, x1)):
            t = (xx - x0) / 90
            yy = int(base - 70 + 14 * math.sin(math.pi * t))
            if 0 <= yy < LH and px[xx, yy][3] == 0:
                px[xx, yy] = hx("#16233a")
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in [("M06_L0_sky.png", sky), ("M06_L1_far.png", far), ("M06_L2_mid.png", mid)]:
        img = upscale(fn())
        img.save(OUT / name)
        print("wrote", OUT / name, img.size)


if __name__ == "__main__":
    main()
