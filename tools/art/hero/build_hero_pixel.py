"""主角像素复刻图集（游戏内 1:1 显示）。

以用户原素材母表（OneDrive/图片/人物素材/*.png，1024×576 横条）为唯一画面源，
帧选择与旧 build_hero_atlas.py 完全一致（跑步自动找循环、攻击裁首尾静止帧、联合包围盒），
但直接按游戏显示尺寸（旧 234px × CHAR_SCALE 0.4 = 93.6px 高）重建为干净像素画：
预乘 alpha 面积缩放 → Lab 距离映射限定色板 → 去斑/聚簇 → 自身色系描边。
每个动作写入 raw_scale = 1/CHAR_SCALE，player.gd 据此以 1.0 缩放显示（整数像素，不再最近邻丢像素）。
翻滚取游戏现有 hero_roll.png（6×512 格）为源，同样重建。

输出 godot/assets/clips/hero_px/*.png + hero_px_atlas.json；旧 hero/ 图集保留。
用法：python tools/art/hero/build_hero_pixel.py
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SRC = Path(r"C:/Users/Administrator/OneDrive/图片/人物素材")
OUT = ROOT / "godot/assets/clips/hero_px"
OLD_ATLAS = ROOT / "godot/assets/clips/hero/hero_atlas.json"
ROLL_SRC = ROOT / "godot/assets/clips/hero/hero_roll.png"
FW, FH = 1024, 576
CHAR_SCALE = 0.4
TARGET_H = 234 * CHAR_SCALE          # 93.6：与旧显示高度一致
SHEETS = {
    "hero_idle": ("空闲.png", 8, {}),
    "hero_run": ("疾跑.png", 45, {"auto_cycle": True}),
    "hero_jump": ("跳跃.png", 4, {}),
    "hero_hurt": ("受击.png", 5, {}),
    "hero_death": ("倒下.png", 15, {}),
    "hero_bat1": ("棒球棍攻击.png", 30, {"trim": True}),
    "hero_bat2": ("棒球棍攻击2.png", 8, {}),
    "hero_bat3": ("棒球棍攻击3.png", 24, {"trim": True}),
}


def hx(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


# 限定色板（与已确认的 160px 复刻母版一致）：材质 → 色阶
RAMPS = {
    "hair": ["#ffffff", "#eef1fa", "#d3dbf0", "#b0bde3", "#8193cc", "#5b6cb4"],
    "hairblue": ["#6f8fe0", "#4a68c8"],
    "skin": ["#fff1e6", "#fde0cc", "#f6c4ab", "#e8a58c", "#c97866"],
    "blush": ["#f7a8a4"],
    "navy": ["#4a5ea6", "#2c3a78", "#1d2654", "#121838"],
    "eye": ["#9cc8ff", "#4f86e8", "#2b56c4", "#1a2a78"],
    "wood": ["#eeb07c", "#cf8656", "#a85e3a", "#7c3e24", "#55260f"],
    "red": ["#ff7a8a", "#d84a5c", "#8e2238"],
    "line": ["#1c1a3a", "#0e1230"],
}
MAT_LINE = {"hair": "#5b6cb4", "hairblue": "#34488f", "skin": "#a85a50", "blush": "#a85a50",
            "navy": "#0c1030", "eye": "#141c50", "wood": "#55260f", "red": "#5a1422", "line": "#0e1230"}
PALETTE = [(hx(c), mat) for mat, cs in RAMPS.items() for c in cs]


def _lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


PAL_LAB = _lab(np.array([p[0] for p in PALETTE], float))


# ---------------------------------------------------------------- 帧选择（与旧构建器一致）
def slice_frames(path: Path, n: int) -> list[Image.Image]:
    im = Image.open(path).convert("RGBA")
    return [im.crop((i * FW, 0, (i + 1) * FW, FH)) for i in range(n)]


def alpha_bbox(im: Image.Image, thr: int = 40):
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > thr)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def frame_diff(a: Image.Image, b: Image.Image) -> float:
    ra = np.array(a.resize((64, 36), Image.BILINEAR), dtype=np.float32)
    rb = np.array(b.resize((64, 36), Image.BILINEAR), dtype=np.float32)
    return float(np.abs(ra - rb).mean())


def find_cycle(frames, lo=8, hi=24) -> int:
    best_p, best_d = None, None
    n = len(frames)
    for p in range(lo, hi + 1):
        d = sum(frame_diff(frames[i], frames[i + p]) for i in range(n - p)) / (n - p)
        if best_d is None or d < best_d:
            best_d, best_p = d, p
    return best_p


def trim_static(frames, eps=2.0):
    n = len(frames)
    head = 0
    while head < n - 2 and frame_diff(frames[head], frames[head + 1]) < eps:
        head += 1
    tail = n - 1
    while tail > head + 2 and frame_diff(frames[tail], frames[tail - 1]) < eps:
        tail -= 1
    return frames[head:tail + 1]


# ---------------------------------------------------------------- 像素化
def downscale(img: Image.Image, size: tuple[int, int]) -> tuple[np.ndarray, np.ndarray]:
    a = np.asarray(img, float)
    pre = a.copy()
    pre[..., :3] *= a[..., 3:4] / 255.0
    small = np.asarray(Image.fromarray(pre.astype(np.uint8), "RGBA").resize(size, Image.BOX), float)
    al = small[..., 3]
    rgb = np.where(al[..., None] > 0, small[..., :3] * 255.0 / np.maximum(al[..., None], 1), 0)
    return np.clip(rgb, 0, 255), al


def quantize(rgb: np.ndarray, al: np.ndarray, thr: float = 110) -> np.ndarray:
    h, w = al.shape
    lab = _lab(rgb.reshape(-1, 3)).reshape(h, w, 3)
    d = ((lab[:, :, None, :] - PAL_LAB[None, None, :, :]) ** 2).sum(-1)
    idx = np.argmin(d, -1)
    idx[al < thr] = -1
    return idx


def clean(idx: np.ndarray) -> np.ndarray:
    h, w = idx.shape
    for _ in range(2):
        out = idx.copy()
        for y in range(h):
            for x in range(w):
                v = idx[y, x]
                nb = [idx[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                      if 0 <= x + dx < w and 0 <= y + dy < h]
                if v >= 0 and v not in nb and nb:
                    out[y, x] = Counter(nb).most_common(1)[0][0]
                elif v < 0 and sum(n >= 0 for n in nb) >= 3:
                    out[y, x] = Counter(n for n in nb if n >= 0).most_common(1)[0][0]
        idx = out
    return idx


def render(idx: np.ndarray) -> Image.Image:
    h, w = idx.shape
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            v = idx[y, x]
            if v < 0:
                continue
            rgb, mat = PALETTE[v]
            edge = any(not (0 <= x + dx < w and 0 <= y + dy < h) or idx[y + dy, x + dx] < 0
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge and mat != "line":
                rgb = hx(MAT_LINE[mat])
            px[x, y] = (*rgb, 255)
    return img


def pixelize(frame: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgb, al = downscale(frame, size)
    return render(clean(quantize(rgb, al)))


def pack(frames: list[Image.Image], tw: int, th: int):
    n = len(frames)
    cols = 1
    while cols * cols < n:
        cols += 1
    rows = (n + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * tw, rows * th), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, ((i % cols) * tw, (i // cols) * th))
    return sheet, cols, rows


def build_clip(name: str, fn: str, n: int, opt: dict) -> dict:
    frames = slice_frames(SRC / fn, n)
    if opt.get("auto_cycle"):
        frames = frames[:find_cycle(frames)]
    if opt.get("trim"):
        frames = trim_static(frames)
    boxes = [alpha_bbox(f) for f in frames]
    ux0, uy0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    ux1, uy1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    uw, uh = ux1 - ux0, uy1 - uy0
    s = TARGET_H / uh
    tw, th = int(round(uw * s)), int(round(uh * s))
    out = [pixelize(f.crop((ux0, uy0, ux1, uy1)), (tw, th)) for f in frames]
    sheet, cols, rows = pack(out, tw, th)
    sheet.save(OUT / f"{name}.png")
    return {"file": f"hero_px/{name}.png", "frames": len(out), "fw": tw, "fh": th, "cols": cols, "rows": rows,
            "foot_y": float(th), "body_cx": round(uw / 2.0 * s, 1), "raw_scale": round(1.0 / CHAR_SCALE, 6)}


def build_roll() -> dict:
    src = Image.open(ROLL_SRC).convert("RGBA")
    cell, count = 512, 6
    roll_scale = CHAR_SCALE * 0.82                 # 旧 RAW_SCALE hero_roll 0.82
    c = int(round(cell * roll_scale))
    out = [pixelize(src.crop((i * cell, 0, (i + 1) * cell, cell)), (c, c)) for i in range(count)]
    sheet = Image.new("RGBA", (c * count, c), (0, 0, 0, 0))
    for i, f in enumerate(out):
        sheet.alpha_composite(f, (i * c, 0))
    sheet.save(OUT / "hero_roll.png")
    return {"file": "hero_px/hero_roll.png", "frames": count, "fw": c, "fh": c, "cols": count, "rows": 1,
            "foot_y": round(500.0 * roll_scale, 1), "body_cx": round(256.0 * roll_scale, 1),
            "raw_scale": round(1.0 / CHAR_SCALE, 6)}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    old = json.loads(OLD_ATLAS.read_text(encoding="utf-8"))["actions"]
    atlas = {"scale": 1.0, "fps": 24, "source": "OneDrive/图片/人物素材（用户原素材），tools/art/hero/build_hero_pixel.py",
             "actions": {}}
    for name, (fn, n, opt) in SHEETS.items():
        meta = build_clip(name, fn, n, opt)
        if name in old and old[name]["frames"] != meta["frames"]:
            raise SystemExit(f"{name} 帧数 {meta['frames']} 与现用图集 {old[name]['frames']} 不一致，拒绝改变动作节奏")
        atlas["actions"][name] = meta
        print(f"{name}: {meta['frames']}f cell={meta['fw']}x{meta['fh']}")
    atlas["actions"]["hero_roll"] = build_roll()
    print("hero_roll:", atlas["actions"]["hero_roll"]["fw"])
    (OUT / "hero_px_atlas.json").write_text(json.dumps(atlas, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("HERO_PIXEL_OK")


if __name__ == "__main__":
    main()
