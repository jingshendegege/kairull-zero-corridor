"""05 节拍广播塔：竞技场视差背景 + 节奏 Boss 的音符/判定环/击碎特效（原创程序化像素画，固定种子，幂等）。

背景低分辨率 384×256 绘制 → 最近邻 ×4（与 M06 相同：GameBackground SCALE 0.75 显示为 3px 像素块）。
输出：
  godot/assets/bg/m07/M07_L0_hall.png      远景场馆（固定层）：地平线品红光晕 + 放射光芒 + 灯塔 + 看台手机灯海
  godot/assets/bg/m07/M07_L1_speakers.png  前排观众剪影 + 荧光棒/应援牌（4 倍宽、首尾无缝、不镜像）
  godot/assets/bg/m07/M07_L2_truss.png     顶部远处桁架（中视差，可镜像平铺；摇头灯由舞台层绘制）
  godot/assets/boss/beat_warden/note_*.png  音符：normal/heavy/bomb（地面轨）与 *_air（空中轨，带翼）
  godot/assets/boss/beat_warden/judge_ring.png   判定环（运行时按拍脉动/着色）
  godot/assets/boss/beat_warden/note_burst.png   击碎特效 4 帧横排（48×48/帧，白底色，运行时按音符类型着色）
  godot/assets/boss/beat_warden/stage_lightbar.png  随拍闪烁的灯带单元（运行时 modulate）
  godot/assets/boss/beat_warden/stage_*.png        舞台实景层：LED 灯墙遮罩/音箱塔/低音振膜/摇头灯/霓虹招牌
                                                   （世界坐标 1:1，由 godot/scripts/m07_beat_stage_fx.gd 随拍驱动）
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
    """远景：巨型场馆。夜空 → 地平线品红光晕；舞台方向放射光芒；两侧灯塔；看台上一片手机灯海。
    左右边缘只有渐变与看台，可无缝横向平铺。"""
    rnd = random.Random(7070)
    img = Image.new("RGBA", (LW, LH))
    px = img.load()
    stops = [(0.0, "#04020b"), (0.4, "#0e0624"), (0.66, "#26093f"), (0.78, "#4a1260"), (0.83, "#7a1f73"),
             (0.86, "#2a0b36"), (1.0, "#0c0514")]
    for y in range(LH):
        for x in range(LW):
            px[x, y] = dither_ramp(stops, y / (LH - 1), x, y)
    # 舞台方向的放射光芒（中心在画面下方中部），抖动半透明
    cx, cy = 192, 214
    for y in range(0, 214):
        for x in range(LW):
            a = math.atan2(y - cy, x - cx)
            ray = (int((a + math.pi) / (math.pi / 18)) % 2 == 0)
            d = math.hypot(x - cx, (y - cy) * 1.3)
            k = max(0.0, 1.0 - d / 230) * (0.9 if ray else 0.35)
            if dith(k * 0.8, x, y):
                px[x, y] = hx("#3b1466" if ray else "#241046")
    # 天空里稀疏的烟花残点
    for _ in range(90):
        x, y = rnd.randrange(LW), int(rnd.random() ** 1.5 * 150)
        px[x, y] = hx(rnd.choice(["#6d4aa6", "#9a6ad0", "#4a3a86", "#c28bff"]))
    # 两座灯塔：格构柱 + 顶部灯组 + 下射的抖动光柱
    for tx in (64, 320):
        for y in range(40, 214):
            for dx in (-5, 5):
                put(px, LW, LH, tx + dx, y, "#150a26")
            k = y % 10
            put(px, LW, LH, tx - 5 + k, y, "#1d0f33")
            put(px, LW, LH, tx + 5 - k, y, "#1d0f33")
        for row in range(3):
            for col in range(5):
                x0, y0 = tx - 12 + col * 5, 26 + row * 5
                for yy in range(y0, y0 + 4):
                    for xx in range(x0, x0 + 4):
                        put(px, LW, LH, xx, yy, "#fff6e0" if (xx + yy) % 3 else "#bfe8ff")
        for y in range(42, 214):
            half = (y - 42) * 0.32
            for x in range(int(tx - half), int(tx + half) + 1):
                k = (1.0 - abs(x - tx) / max(1.0, half)) * (1.0 - (y - 42) / 172) * 0.55
                if 0 <= x < LW and dith(k, x, y):
                    px[x, y] = hx("#5a3c8a")
    # 看台：三层弧形看台 + 手机灯海（越近越密）
    for tier, (top, col) in enumerate(((150, "#14081f"), (172, "#10061a"), (194, "#0b0413"))):
        for x in range(LW):
            t = top + int(6 * math.cos((x - 192) / 192 * math.pi * 0.5) * -1) + 6
            for y in range(t, 216):
                if px[x, y][2] > 20 or tier == 2:
                    px[x, y] = hx(col)
            put(px, LW, LH, x, t, "#2a1240")
    for _ in range(1400):
        x = rnd.randrange(LW)
        y = 154 + int(rnd.random() ** 0.6 * 60)
        if y < 214:
            px[x, y] = hx(rnd.choice(["#fff3d6", "#c9f6ff", "#ff9bd0", "#8a6ab8", "#ffe28a", "#6a4a9a"]))
    # 地平线霓虹带
    for x in range(LW):
        put(px, LW, LH, x, 215, "#ff4fa8" if x % 6 else "#8a1f60")
        put(px, LW, LH, x, 216, "#5a1348")
    return img


CROWD_W = LW * 4   # 观众层 4 倍宽且首尾无缝：边跑边打时不再镜像平铺出明显重复


def speakers() -> Image.Image:
    """中景：前排观众剪影（举手、荧光棒、偶尔的应援牌），CROWD_W 宽、横向首尾无缝，不镜像。"""
    rnd = random.Random(128)
    W = CROWD_W
    img = Image.new("RGBA", (W, LH), (0, 0, 0, 0))
    px = img.load()

    def wput(x, y, col):
        if 0 <= y < LH:
            px[x % W, y] = hx(col)

    x = 0
    while x < W:
        w = rnd.randint(6, 12)
        base = 206 + rnd.randint(-2, 3)
        h = rnd.randint(13, 26)
        top = base - h
        cx = x + w // 2
        body = "#07040d" if rnd.random() < 0.8 else "#0a0613"
        for yy in range(top + 5, LH):                       # 身体
            for xx in range(x + 1, x + w - 1):
                wput(xx, yy, body)
        for yy in range(top, top + 6):                       # 头
            for xx in range(cx - 2, cx + 3):
                if (xx - cx) ** 2 + (yy - top - 3) ** 2 <= 7:
                    wput(xx, yy, body)
        r = rnd.random()
        if r < 0.5:                                          # 举手 + 荧光棒
            side = rnd.choice((-1, 1))
            hx0 = cx + side * (w // 2)
            arm = rnd.randint(6, 10)
            for k in range(arm):
                wput(hx0 + side * (k // 4), top + 6 - k, body)
            stick = rnd.choice(["#8ff8ff", "#ff5aa8", "#ffe28a", "#b08cff", "#8ff8ff"])
            for k in range(5):
                wput(hx0 + side * 2, top + 6 - arm - k, stick)
        elif r < 0.56:                                       # 双手举应援牌
            sw = rnd.randint(10, 16)
            col = rnd.choice(["#ff5aa8", "#8ff8ff", "#ffe28a"])
            for yy in range(top - 12, top - 4):
                for xx in range(cx - sw // 2, cx + sw // 2):
                    edge = yy in (top - 12, top - 5) or xx in (cx - sw // 2, cx + sw // 2 - 1)
                    wput(xx, yy, "#1a1026" if edge else ("#241838" if (xx + yy) % 3 else col))
            for yy in range(top - 4, top + 6):
                wput(cx - sw // 2 + 1, yy, body)
                wput(cx + sw // 2 - 2, yy, body)
        elif r < 0.62:                                       # 手机闪光灯
            wput(cx + 3, top - 4, "#fff6e0")
            wput(cx + 3, top - 3, body)
        x += w - rnd.randint(1, 3)
    # 观众头顶被舞台光擦亮的边
    for xx in range(W):
        for yy in range(1, LH):
            if px[xx, yy][3] and px[xx, yy - 1][3] == 0 and px[xx, yy][:3] in ((7, 4, 13), (10, 6, 19)):
                px[xx, yy] = hx("#3a2058")
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


# ================================================================ 舞台实景层（世界坐标 1:1，由 m07_beat_stage_fx.gd 随拍驱动）
LED_W, LED_H, LED_FRAME = 736, 352, 10


def stage_led_mask() -> Image.Image:
    """LED 灯墙遮罩：外框 + 3×3 像素灯珠（透明）与 1px 暗缝。运行时先在底下画彩色频谱，再盖这张遮罩。"""
    img = Image.new("RGBA", (LED_W, LED_H), (0, 0, 0, 0))
    px = img.load()
    for y in range(LED_H):
        for x in range(LED_W):
            inner = LED_FRAME <= x < LED_W - LED_FRAME and LED_FRAME <= y < LED_H - LED_FRAME
            if not inner:
                edge = x in (0, LED_W - 1) or y in (0, LED_H - 1)
                lit = y in (1, 2) or x in (1, 2)
                px[x, y] = hx(OUTLINE if edge else "#4a3f6a" if lit else "#231c38")
            elif (x - LED_FRAME) % 4 == 3 or (y - LED_FRAME) % 4 == 3:
                px[x, y] = hx("#050308")
    for x in range(24, LED_W - 20, 48):                      # 外框螺栓
        for y in (4, LED_H - 6):
            px[x, y] = hx("#8a80b0")
            px[x + 1, y + 1] = hx("#120c20")
    return img


def stage_speaker() -> Image.Image:
    """112×224 音箱塔（两只箱体）：暗紫箱体、青色霓虹包边、低音口留黑（运行时叠 stage_woofer 随拍鼓动）。"""
    w, h = 112, 224
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for box in range(2):
        y0 = box * 112
        for y in range(y0, y0 + 112):
            for x in range(w):
                edge = x in (0, w - 1) or y in (y0, y0 + 111)
                col = OUTLINE if edge else ("#1a1230" if x < w - 8 else "#110b20")
                if not edge and (x in (2, w - 3) or y == y0 + 2):
                    col = "#3fd8ff" if (x + y) % 2 else "#2a8ea8"         # 霓虹包边
                px[x, y] = hx(col)
        cx, cy = 56, y0 + 62
        for y in range(y0, y0 + 112):
            for x in range(w):
                d = math.hypot(x - cx, y - cy)
                if d <= 40:
                    px[x, y] = hx("#2c2448" if d > 38 else "#030206")
        for x in range(84, 100):                               # 高音口
            for y in range(y0 + 10, y0 + 22):
                px[x, y] = hx("#05030a" if (x + y) % 2 else "#241c3c")
        for x in range(12, 40, 6):                             # 电平灯
            px[x, y0 + 14] = hx("#ff5aa8" if x > 30 else "#8ff8ff")
    return img


def stage_woofer() -> Image.Image:
    """76×76 低音喇叭振膜：橡胶折环 + 锥盆同心纹 + 品红防尘帽。"""
    s = 76
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    c = s / 2 - 0.5
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c)
            if d > 37.5:
                continue
            lx = (x - c + d * 0.3) / 38
            if d > 34:
                col = "#3a3350" if lx < 0 else "#1c1830"
            elif d > 30:
                col = "#0c0914"
            elif d > 12:
                ring = int(d) % 5 == 0
                col = "#2a2344" if ring else ("#1a1530" if lx < 0.1 else "#120e22")
            elif d > 10:
                col = "#0c0914"
            else:
                col = "#ffb0d8" if (x - c) + (y - c) < -6 else "#ff3f94" if d < 8.5 else "#9a1a5a"
            px[x, y] = hx(col)
    return img


def stage_spot() -> Image.Image:
    """28×22 摇头灯（倒挂在桁架上）：U 型叉臂 + 灯头 + 白色镜头（光色由运行时光束决定）。"""
    img = Image.new("RGBA", (28, 22), (0, 0, 0, 0))
    px = img.load()
    for x in range(4, 24):
        for y in range(0, 4):
            px[x, y] = hx(OUTLINE if y in (0, 3) or x in (4, 23) else "#3a3350")
    for side in (5, 21):
        for y in range(3, 14):
            for x in (side, side + 1):
                px[x, y] = hx("#2a2344")
    for y in range(8, 21):
        for x in range(7, 21):
            edge = x in (7, 20) or y in (8, 20)
            px[x, y] = hx(OUTLINE if edge else "#1c1830" if x > 16 else "#2c2448")
    for x in range(9, 19):
        px[x, 19] = hx("#ffffff")
        px[x, 18] = hx("#cfd8ff")
    return img


FONT5 = {
    "B": ["1110", "1001", "1110", "1001", "1001", "1110"], "E": ["1111", "1000", "1110", "1000", "1000", "1111"],
    "A": ["0110", "1001", "1001", "1111", "1001", "1001"], "T": ["11111", "00100", "00100", "00100", "00100", "00100"],
    "W": ["10001", "10001", "10101", "10101", "11011", "10001"], "R": ["1110", "1001", "1110", "1010", "1001", "1001"],
    "D": ["1110", "1001", "1001", "1001", "1001", "1110"], "N": ["1001", "1101", "1101", "1011", "1011", "1001"],
    " ": ["00", "00", "00", "00", "00", "00"],
}


def stage_neon() -> Image.Image:
    """霓虹招牌 "BEAT WARDEN"：像素灯管（白芯 + 品红管壁）+ 预烘焙的抖动光晕；运行时调亮度/闪烁。"""
    text, scale = "BEAT WARDEN", 5
    widths = [len(FONT5[ch][0]) for ch in text]
    w = sum(widths) * scale + (len(text) - 1) * 4 + 24
    h = 6 * scale + 24
    tube = Image.new("L", (w, h), 0)
    tp = tube.load()
    x0 = 12
    for ch, cw in zip(text, widths):
        for r, row in enumerate(FONT5[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    for dy in range(scale):
                        for dx in range(scale):
                            tp[x0 + c * scale + dx, 12 + r * scale + dy] = 255
        x0 += cw * scale + 4
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    lit = {(x, y) for y in range(h) for x in range(w) if tp[x, y]}
    for y in range(h):
        for x in range(w):
            if (x, y) in lit:
                inner = all((x + dx, y + dy) in lit for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                px[x, y] = hx("#fff0f8" if inner else "#ff5aa8")
            else:
                near = 99
                for dy in range(-6, 7):
                    for dx in range(-6, 7):
                        if (x + dx, y + dy) in lit:
                            near = min(near, abs(dx) + abs(dy))
                if near <= 6 and dith((7 - near) / 7 * 0.7, x, y):
                    px[x, y] = hx("#ff3f94", 110 if near <= 3 else 60)
    return img


def main() -> None:
    BG_OUT.mkdir(parents=True, exist_ok=True)
    BOSS_OUT.mkdir(parents=True, exist_ok=True)
    for name, img in {"M07_L0_hall.png": hall(), "M07_L1_speakers.png": speakers(), "M07_L2_truss.png": truss()}.items():
        upscale(img).save(BG_OUT / name)
        print("wrote bg", name)
    items = {"note_normal.png": note_normal(), "note_heavy.png": note_heavy(), "note_heavy_cracked.png": note_heavy(True),
             "note_bomb.png": note_bomb(), "judge_ring.png": judge_ring(), "note_burst.png": note_burst(),
             "stage_lightbar.png": lightbar(), "stage_led_mask.png": stage_led_mask(),
             "stage_speaker.png": stage_speaker(), "stage_woofer.png": stage_woofer(), "stage_spot.png": stage_spot(),
             "stage_neon.png": stage_neon()}
    items["note_normal_air.png"] = wings(items["note_normal.png"], 14)
    items["note_bomb_air.png"] = wings(items["note_bomb.png"], 16, "#ffd0e6", "#9a1a5a")
    for name, img in items.items():
        img.save(BOSS_OUT / name)
        print("wrote", name, img.size)


if __name__ == "__main__":
    main()
