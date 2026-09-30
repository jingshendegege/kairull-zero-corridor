"""04 排风脊线机关精灵（原创像素画，逐像素几何绘制，幂等）。

输出 godot/assets/maps/m06/：
  fan_sheet.png     排风弹射扇 4 帧（每帧 64×16，扇心在 x=32，y=0 为地表）
  glass_panel.png   检疫玻璃 32×128（完好）
  glass_shards.png  碎片 2 种（每种 6×6）
  dash_node.png     冲刺节点 5 帧（每帧 32×32：0–3 脉动，4 熄灭）
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "godot/assets/maps/m06"


def hx(c: str, a: int = 255) -> tuple[int, int, int, int]:
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), a)


STEEL = ["#8a9aa8", "#5c6b78", "#3b4652", "#232b33", "#12171c"]
AMBER, AMBER_D = "#e8a33e", "#8a5a1e"
CYAN, CYAN_D = "#7ff1e8", "#2f8f96"


def fan_sheet() -> Image.Image:
    fw, fh, n = 64, 16, 4
    sheet = Image.new("RGBA", (fw * n, fh), (0, 0, 0, 0))
    for f in range(n):
        img = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        px = img.load()
        # 外框：地表处 2px 高唇 + 嵌入地面的 10px 箱体
        for x in range(2, fw - 2):
            px[x, 0] = hx(STEEL[0])
            px[x, 1] = hx(STEEL[1])
            for y in range(2, 12):
                px[x, y] = hx(STEEL[3])
            px[x, 12] = hx(STEEL[4])
        for y in range(0, 13):
            for x in (2, 3, fw - 4, fw - 3):
                px[x, y] = hx(STEEL[2] if x in (3, fw - 4) else STEEL[4])
        # 两端琥珀警示斜纹
        for x in range(4, 12):
            for y in range(2, 12):
                px[x, y] = hx(AMBER if (x + y) % 6 < 3 else AMBER_D)
        for x in range(fw - 12, fw - 4):
            for y in range(2, 12):
                px[x, y] = hx(AMBER if (x - y) % 6 < 3 else AMBER_D)
        # 中间扇腔：深色 + 旋转叶片（斜向亮条随帧移动）+ 格栅横条
        for x in range(12, fw - 12):
            for y in range(2, 12):
                px[x, y] = hx("#0b1116")
        for b in range(4):
            bx = 12 + ((b * 10 + f * 3) % 40)
            for y in range(2, 12):
                xx = bx + (y - 2) // 2
                if 12 <= xx < fw - 12:
                    px[xx, y] = hx(STEEL[1] if y < 7 else STEEL[2])
                    if 12 <= xx + 1 < fw - 12:
                        px[xx + 1, y] = hx(STEEL[2])
        for x in range(12, fw - 12):
            for y in (4, 8):
                px[x, y] = hx(STEEL[0] if x % 2 else STEEL[1])
        for y in range(2, 12):
            px[31, y] = hx(STEEL[1])
            px[32, y] = hx(STEEL[2])
        # 状态灯
        px[31, 13] = hx(CYAN)
        px[32, 13] = hx(CYAN_D)
        sheet.alpha_composite(img, (f * fw, 0))
    return sheet


def glass_panel() -> Image.Image:
    w, h = 32, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = y / h
            # 磨砂玻璃：青灰半透明，竖向渐变 + 有序颗粒
            base = (70 + int(30 * (1 - t)), 120 + int(30 * (1 - t)), 138 + int(24 * (1 - t)))
            grain = ((x * 7 + y * 3) % 5 == 0)
            a = 170 if not grain else 190
            px[x, y] = (*base, a)
    # 斜向高光条
    for k, (off, width) in enumerate([(10, 3), (26, 1), (70, 2), (96, 1)]):
        for y in range(h):
            x = (y - off) // 2
            for dx in range(width):
                if 3 <= x + dx < w - 3 and y > off:
                    px[x + dx, y] = hx("#d9f3f2", 200 if k % 2 == 0 else 150)
    # 检疫标记：中部横向品红虚线 + 青色小方块
    for x in range(6, w - 6):
        if x % 3 != 2:
            px[x, 62] = hx("#ff4fa3", 210)
    for y in range(52, 58):
        for x in range(13, 19):
            px[x, y] = hx(CYAN, 220) if (x in (13, 18) or y in (52, 57)) else px[x, y]
    # 钢框：两侧竖框 + 上下封口
    for y in range(h):
        for x in (0, w - 1):
            px[x, y] = hx(STEEL[4])
        for x in (1, w - 2):
            px[x, y] = hx(STEEL[2])
    for y in list(range(0, 5)) + list(range(h - 5, h)):
        for x in range(w):
            c = STEEL[1] if y in (1, h - 4) else STEEL[3] if y in (0, h - 1) else STEEL[2]
            px[x, y] = hx(c)
    for x in range(4, w - 4, 6):
        px[x, 2] = hx(STEEL[0])
        px[x, h - 3] = hx(STEEL[0])
    return img


def glass_shards() -> Image.Image:
    img = Image.new("RGBA", (12, 6), (0, 0, 0, 0))
    px = img.load()
    for x, y in [(0, 5), (1, 4), (1, 5), (2, 3), (2, 4), (3, 2), (3, 3), (4, 1), (4, 2), (5, 0)]:
        px[x, y] = hx("#c7f0ef")
    for x, y in [(1, 3), (2, 2), (3, 1)]:
        px[x, y] = hx("#6fb3bd")
    for x, y in [(6, 1), (7, 1), (8, 1), (7, 2), (8, 2), (9, 2), (8, 3), (9, 3), (10, 4)]:
        px[x, y] = hx("#b3e6e8")
    for x, y in [(6, 2), (7, 3)]:
        px[x, y] = hx("#5a9aa6")
    return img


def dash_node() -> Image.Image:
    s, n = 32, 5
    sheet = Image.new("RGBA", (s * n, s), (0, 0, 0, 0))
    for f in range(n):
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        px = img.load()
        c = 15.5
        lit = f < 4
        pulse = [0, 1, 2, 1][f] if lit else 0
        for y in range(s):
            for x in range(s):
                d = abs(x - c) + abs(y - c) * 0.8      # 竖长菱形
                if lit and d <= 13 + pulse:
                    # 外晕：稀疏棋盘点
                    if d > 9 and (x + y + f) % 2 == 0:
                        px[x, y] = hx("#3fb7c9", 120)
                if d <= 9:
                    if not lit:
                        if d > 7.6:
                            px[x, y] = hx("#3a4f5c")
                        continue
                    if d > 7.6:
                        col = "#1f6f7a"
                    elif x < c and y < c:
                        col = "#e8fffb"
                    elif x < c or y < c:
                        col = "#8ef5ea"
                    else:
                        col = "#43c2c4"
                    px[x, y] = hx(col)
        if lit:
            # 内芯亮点 + 闪光十字
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                px[int(c) + dx - 2, int(c) + dy - 3] = hx("#ffffff")
            arm = 3 + pulse
            for k in range(1, arm):
                for xx, yy in ((int(c) - 9 - k, int(c)), (int(c) + 9 + k, int(c))):
                    if 0 <= xx < s:
                        px[xx, yy] = hx("#bff7f0", 200 - k * 30)
        sheet.alpha_composite(img, (f * s, 0))
    return sheet


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in [("fan_sheet.png", fan_sheet), ("glass_panel.png", glass_panel),
                     ("glass_shards.png", glass_shards), ("dash_node.png", dash_node)]:
        img = fn()
        img.save(OUT / name)
        print("wrote", name, img.size)


if __name__ == "__main__":
    main()
