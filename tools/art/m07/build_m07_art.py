"""05 节拍广播塔：竞技场视差背景 + 节奏 Boss 的音符/判定环/击碎特效（原创程序化像素画，固定种子，幂等）。

背景低分辨率 384×256 绘制 → 最近邻 ×4（与 M06 相同：GameBackground SCALE 0.75 显示为 3px 像素块）。
输出：
  godot/assets/bg/m07/M07_L0_hall.png      广播大厅（固定层）：紫黑渐变 + 巨型喇叭膜同心环 + 斜射光柱
  godot/assets/bg/m07/M07_L1_speakers.png  音箱墙 + 中央 LED 频谱屏（慢视差，可镜像平铺）
  godot/assets/bg/m07/M07_L2_truss.png     顶部灯光桁架 + 聚光灯 + 垂缆（中视差，可镜像平铺）
  godot/assets/boss/beat_warden/note_*.png  音符：normal/heavy/bomb（地面轨）与 *_air（空中轨，带翼）
  godot/assets/boss/beat_warden/judge_ring.png   判定环（运行时按拍脉动/着色）
  godot/assets/boss/beat_warden/note_burst.png   击碎特效 4 帧横排（48×48/帧，白底色，运行时按音符类型着色）
  godot/assets/boss/beat_warden/stage_lightbar.png  随拍闪烁的灯带单元（运行时 modulate）
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
BG_OUT = ROOT / "godot/assets/bg/m07"
BOSS_OUT = ROOT / "godot/assets/boss/beat_warden"
LW, LH, UP = 384, 256, 4
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
OUTLINE = "#0b0916"


def hx(c: str, a: int = 255) -> tuple[int, int, int, int]:
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), a)


def dither_ramp(stops, t: float, x: int, y: int):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t0 <= t <= t1:
            k = (t - t0) / max(1e-6, t1 - t0)
            return hx(c1) if k * 16 > BAYER[y % 4][x % 4] + 0.5 else hx(c0)
    return hx(stops[-1][1])


def dith(k: float, x: int, y: int) -> bool:
    return k * 16 > BAYER[y % 4][x % 4] + 0.5


def upscale(img: Image.Image) -> Image.Image:
    return img.resize((img.width * UP, img.height * UP), Image.NEAREST)


def put(px, w, h, x, y, col):
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = hx(col) if isinstance(col, str) else col


# ================================================================ 背景
def hall() -> Image.Image:
    img = Image.new("RGBA", (LW, LH))
    px = img.load()
    stops = [(0.0, "#07050f"), (0.35, "#120b24"), (0.7, "#1b1136"), (1.0, "#0e0a1c")]
    for y in range(LH):
        for x in range(LW):
            px[x, y] = dither_ramp(stops, y / (LH - 1), x, y)
    # 巨型喇叭膜：舞台右侧（Boss 身后）的同心环，越往外越暗
    cx, cy = 262, 132
    for y in range(LH):
        for x in range(LW):
            d = math.hypot((x - cx) * 1.0, (y - cy) * 1.12)
            if d < 118:
                ring = int(d) % 14
                if ring in (0, 1):
                    k = 1.0 - d / 118
                    if dith(k * 1.4, x, y):
                        px[x, y] = hx("#3b2a66" if k > 0.5 else "#2a1d4c")
                elif d < 20:
                    px[x, y] = hx("#2a1d4c") if dith(0.6, x, y) else px[x, y]
    # 斜射光柱：从顶部两盏大灯打向舞台（抖动半透明感）
    for sx, ang, col in ((60, 0.32, "#2b2150"), (170, 0.12, "#2a2350"), (330, -0.28, "#2b2150")):
        for y in range(0, LH):
            half = 4 + y * 0.12
            center = sx + math.tan(ang) * y
            for x in range(int(center - half), int(center + half) + 1):
                k = (1.0 - abs(x - center) / half) * (1.0 - y / LH) * 0.8
                if 0 <= x < LW and dith(k, x, y):
                    px[x, y] = hx(col)
    # 地平线处的观众席剪影（低矮起伏的人头 + 应援荧光棒）
    rnd = random.Random(7070)
    base = 214
    for x in range(LW):
        top = base - int(4 + 3 * abs(math.sin(x * 0.45)) + 2 * math.sin(x * 0.13))
        for y in range(top, LH):
            px[x, y] = hx("#08060f" if y > top + 1 else "#130d24")
    for _ in range(70):
        x = rnd.randrange(LW)
        col = rnd.choice(["#ff5aa8", "#8ff8ff", "#ffd27a", "#8ff8ff"])
        top = base - 12 - rnd.randrange(4)
        for y in range(top, top + 4):
            put(px, LW, LH, x, y, col if y == top else "#3a2a55")
    return img


def speakers() -> Image.Image:
    img = Image.new("RGBA", (LW, LH), (0, 0, 0, 0))
    px = img.load()
    floor = 216

    def cabinet(x0, y0, w, h):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                edge = x in (x0, x0 + w - 1) or y in (y0, y0 + h - 1)
                put(px, LW, LH, x, y, "#060409" if edge else ("#16102a" if x < x0 + w - 3 else "#0f0b1e"))
        r = min(w, h) // 2 - 3
        cx, cy = x0 + w // 2, y0 + h // 2
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                d = math.hypot(x - cx, y - cy)
                if d <= r:
                    col = "#241a40" if d > r - 1.5 else "#0a0712" if d > r * 0.35 else "#2f2150"
                    put(px, LW, LH, x, y, col)
        put(px, LW, LH, cx, cy, "#5a2a60")

    # 左右两堵音箱墙（每堵 2 列 × 4 行），中间留出 LED 屏
    for col_x in (4, 34, 316, 346):
        for row in range(4):
            cabinet(col_x, floor - 34 - row * 34, 30, 34)
    # LED 频谱屏（中央）：边框 + 柱状频谱（静态画面，运行时灯带另画）
    sx0, sy0, sx1, sy1 = 120, 58, 264, 132
    for y in range(sy0, sy1 + 1):
        for x in range(sx0, sx1 + 1):
            edge = x in (sx0, sx1) or y in (sy0, sy1)
            put(px, LW, LH, x, y, "#060409" if edge else ("#0c0918" if (x + y) % 2 else "#0e0a1c"))
    rnd = random.Random(128)
    for i, x in enumerate(range(sx0 + 4, sx1 - 3, 5)):
        h = int(8 + 44 * abs(math.sin(i * 0.55)) * (0.6 + 0.4 * rnd.random()))
        for y in range(sy1 - 3 - h, sy1 - 3):
            t = (sy1 - 3 - y) / 56
            col = "#8ff8ff" if t < 0.45 else "#c9a0ff" if t < 0.75 else "#ff5aa8"
            if (y % 3) != 0:
                for dx in range(3):
                    put(px, LW, LH, x + dx, y, col if (y + dx) % 5 else "#6a4a9a")
    # 屏幕支架
    for x in (150, 234):
        for y in range(sy1 + 1, floor):
            put(px, LW, LH, x, y, "#0a0712")
            put(px, LW, LH, x + 1, y, "#130d24")
    # 地台
    for y in range(floor, LH):
        for x in range(LW):
            put(px, LW, LH, x, y, "#07050c")
    return img


def truss() -> Image.Image:
    img = Image.new("RGBA", (LW, LH), (0, 0, 0, 0))
    px = img.load()
    top, bot = 10, 22
    # 双弦桁架 + 斜腹杆
    for x in range(LW):
        for y in (top, top + 1, bot, bot + 1):
            put(px, LW, LH, x, y, "#2a2340" if y in (top, bot) else "#0f0b1b")
        k = x % 12
        yy = top + 2 + (k if k < 6 else 12 - k) * 2 * (bot - top - 2) // 12
        put(px, LW, LH, x, yy, "#1f1933")
    for x in range(0, LW, 12):
        for y in range(top, bot + 2):
            put(px, LW, LH, x, y, "#1f1933")
    # 聚光灯（交替青/品红镜头）+ 垂缆
    for i, x in enumerate(range(18, LW, 48)):
        lens = "#8ff8ff" if i % 2 == 0 else "#ff5aa8"
        for y in range(bot + 2, bot + 12):
            for dx in range(-4, 5):
                edge = abs(dx) == 4 or y == bot + 11
                put(px, LW, LH, x + dx, y, "#060409" if edge else "#241c3c")
        for dx in range(-2, 3):
            put(px, LW, LH, x + dx, bot + 12, lens)
            put(px, LW, LH, x + dx, bot + 13, "#3a2a55")
        for y in range(bot + 2, bot + 30 + (i * 17) % 24):
            put(px, LW, LH, x + 7 + int(2 * math.sin(y * 0.2)), y, "#0d0a17")
    return img


# ================================================================ 音符与特效
def disc(px, w, h, cx, cy, r, ramp, outline=OUTLINE):
    """带受光面的像素圆：ramp = [高光, 基色, 阴影]。"""
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx + 0.5, y - cy + 0.5)
            if d <= r + 0.5:
                if d > r - 0.7:
                    px[x, y] = hx(outline)
                else:
                    lx, ly = (x - cx + r * 0.35) / r, (y - cy + r * 0.35) / r
                    lit = math.hypot(lx, ly)
                    px[x, y] = hx(ramp[0] if lit < 0.45 else ramp[1] if lit < 1.05 else ramp[2])


GLYPH = ["...#..", "...##.", "...#.#", "...#..", "...#..", ".###..", "####..", ".##..."]


def glyph(px, cx, cy, col, big=False):
    """八分音符 ♪（固定遮罩；big = 2× 像素块）。(cx, cy) ≈ 图形中心。"""
    s = 2 if big else 1
    x0, y0 = cx - 3 * s, cy - 4 * s
    for r, row in enumerate(GLYPH):
        for c, ch in enumerate(row):
            if ch == "#":
                for dy in range(s):
                    for dx in range(s):
                        px[x0 + c * s + dx, y0 + r * s + dy] = hx(col)


WING = ["......##", "....####", "..######", "########", ".#######", "...####.", ".....#.."]


def wings(img: Image.Image, cy: int, col="#d7f6ff", dark="#5d7fa0") -> Image.Image:
    """空中轨音符：两侧加像素小翼（固定遮罩，右侧镜像），画布左右各扩 8px。"""
    w, h = img.size
    out = Image.new("RGBA", (w + 16, h), (0, 0, 0, 0))
    px = out.load()
    y0 = cy - len(WING) // 2 - 1
    for r, row in enumerate(WING):
        for c, ch in enumerate(row):
            if ch != "#":
                continue
            below = r + 1 >= len(WING) or WING[r + 1][c] != "#"
            colr = dark if below or c == 0 or row[c - 1] != "#" else col
            for x in (c + 2, w + 13 - c):
                if 0 <= y0 + r < h:
                    px[x, y0 + r] = hx(colr)
    out.alpha_composite(img, (8, 0))
    return out


def note_normal() -> Image.Image:
    img = Image.new("RGBA", (28, 28), (0, 0, 0, 0))
    px = img.load()
    disc(px, 28, 28, 14, 14, 12, ["#e6ffff", "#5fe6f0", "#2a8ea8"])
    disc(px, 28, 28, 14, 14, 8, ["#bff9ff", "#3fcfe0", "#2a8ea8"], outline="#1a6f86")
    glyph(px, 13, 14, "#0b2a3a")
    return img


def note_heavy(cracked: bool = False) -> Image.Image:
    img = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    px = img.load()
    disc(px, 40, 40, 20, 20, 18, ["#fff0b8", "#f0b44a", "#a8661e"])
    disc(px, 40, 40, 20, 20, 13, ["#ffe39a", "#dd9a3a", "#a8661e"], outline="#6b3c0e")
    for a in range(0, 360, 45):                      # 外圈铆钉
        x = int(20 + 15.5 * math.cos(math.radians(a)))
        y = int(20 + 15.5 * math.sin(math.radians(a)))
        px[x, y] = hx("#fff6d8")
    glyph(px, 19, 20, "#3a1d05", big=True)
    if cracked:                                      # 第一击后的裂纹
        x, y = 8, 12
        for step in range(22):
            px[min(39, x), min(39, y)] = hx(OUTLINE)
            if 0 <= x + 1 < 40:
                px[x + 1, min(39, y)] = hx("#6b3c0e")
            x += 1
            y += 1 if step % 3 else 0
        for i in range(8):
            px[22 + i, 27 - i // 2] = hx(OUTLINE)
    return img


def note_bomb() -> Image.Image:
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    px = img.load()
    # 尖刺（8 向）
    for a in range(0, 360, 45):
        for r in range(9, 15):
            x = int(round(16 + r * math.cos(math.radians(a))))
            y = int(round(16 + r * math.sin(math.radians(a))))
            half = 1 if r < 13 else 0
            for dx in range(-half, half + 1):
                for dy in range(-half, half + 1):
                    if 0 <= x + dx < 32 and 0 <= y + dy < 32:
                        px[x + dx, y + dy] = hx("#ff9ccc" if r == 14 else "#b8246c")
    disc(px, 32, 32, 16, 16, 10, ["#ff9ccc", "#ff3f94", "#9a1a5a"])
    # 白色 ✕ 禁止标志
    for i in range(-4, 5):
        for t in (0, 1):
            px[16 + i, 16 + i - t] = hx("#fff0f7")
            px[16 + i, 16 - i - t] = hx("#fff0f7")
    return img


def judge_ring() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for y in range(64):
        for x in range(64):
            d = math.hypot(x - 31.5, y - 31.5)
            a = math.degrees(math.atan2(y - 31.5, x - 31.5)) % 360
            if 28.5 <= d <= 31:
                px[x, y] = hx("#ffffff")
            elif 26.5 <= d < 28.5:
                px[x, y] = hx("#9aa6c0", 200)
            elif 18 <= d <= 19.5 and int(a / 15) % 2 == 0:  # 内圈虚线
                px[x, y] = hx("#ffffff", 190)
    for a in range(0, 360, 90):                         # 四个刻度
        for r in range(22, 27):
            x = int(round(31.5 + r * math.cos(math.radians(a))))
            y = int(round(31.5 + r * math.sin(math.radians(a))))
            px[x, y] = hx("#ffffff")
    return img


def note_burst() -> Image.Image:
    sheet = Image.new("RGBA", (48 * 4, 48), (0, 0, 0, 0))
    rnd = random.Random(44)
    for f in range(4):
        frame = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
        px = frame.load()
        r_ring = 6 + f * 5.5
        for y in range(48):
            for x in range(48):
                d = math.hypot(x - 23.5, y - 23.5)
                if abs(d - r_ring) < (2.2 - f * 0.4):
                    px[x, y] = hx("#ffffff", 255 - f * 40)
                elif f == 0 and d < 6:
                    px[x, y] = hx("#ffffff")
        for i in range(8):                                  # 放射状碎片
            a = math.radians(i * 45 + 22 + rnd.randint(-8, 8))
            r = 8 + f * 6
            for k in range(3 - f // 2):
                x = int(round(23.5 + (r + k) * math.cos(a)))
                y = int(round(23.5 + (r + k) * math.sin(a)))
                if 0 <= x < 48 and 0 <= y < 48:
                    px[x, y] = hx("#ffffff", 255 - f * 50)
        sheet.alpha_composite(frame, (f * 48, 0))
    return sheet


def lightbar() -> Image.Image:
    img = Image.new("RGBA", (64, 8), (0, 0, 0, 0))
    px = img.load()
    for x in range(64):
        for y in range(8):
            edge = y in (0, 7) or x in (0, 63)
            seg = x % 8 in (0, 7)
            px[x, y] = hx(OUTLINE) if edge else hx("#9a9aa8") if seg else hx("#ffffff") if y in (2, 3) else hx("#d8d8e4")
    return img


def main() -> None:
    BG_OUT.mkdir(parents=True, exist_ok=True)
    BOSS_OUT.mkdir(parents=True, exist_ok=True)
    for name, img in {"M07_L0_hall.png": hall(), "M07_L1_speakers.png": speakers(), "M07_L2_truss.png": truss()}.items():
        upscale(img).save(BG_OUT / name)
        print("wrote bg", name)
    items = {"note_normal.png": note_normal(), "note_heavy.png": note_heavy(), "note_heavy_cracked.png": note_heavy(True),
             "note_bomb.png": note_bomb(), "judge_ring.png": judge_ring(), "note_burst.png": note_burst(),
             "stage_lightbar.png": lightbar()}
    items["note_normal_air.png"] = wings(items["note_normal.png"], 14)
    items["note_bomb_air.png"] = wings(items["note_bomb.png"], 16, "#ffd0e6", "#9a1a5a")
    for name, img in items.items():
        img.save(BOSS_OUT / name)
        print("wrote", name, img.size)


if __name__ == "__main__":
    main()
