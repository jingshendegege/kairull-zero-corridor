#!/usr/bin/env python3
"""把用户提供的透明动作母表整理为货运巡检员 Godot 图集。

母表是 7 行、每行最多 8 格；按主体连通域切帧可避免相邻动作的半透明
毛边串入同一格。第七行原素材保留 7 帧，运行图集按要求只取前 6 帧。
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / "godot" / "assets" / "enemy" / "freight_inspector"
SOURCE = ASSET_DIR / "ai_reference.png"
ATLAS = ASSET_DIR / "atlas.png"
META = ASSET_DIR / "atlas.json"

SOURCE_SIZE = (1341, 1173)
# name, source frame count, used frame count, fps, loop
ANIMS = [
    ("idle", 4, 4, 5.0, True),
    ("alert", 5, 5, 12.0, False),
    ("run", 8, 8, 12.0, True),
    ("windup", 4, 4, 12.0, False),
    ("attack", 6, 6, 24.0, False),
    ("recover", 4, 4, 10.0, False),
    ("death", 7, 6, 9.0, False),
]

COLS = 8
CELL_W, CELL_H = 128, 96
BASELINE_Y = 90
SOURCE_SCALE = 0.54
CORE_ALPHA = 32
MIN_COMPONENT_PIXELS = 500


def _row_bounds(alpha: np.ndarray) -> list[tuple[int, int]]:
    """用透明横沟槽找出七个动作行。"""
    values = np.where((alpha > 8).sum(axis=1) > 3)[0]
    bounds: list[tuple[int, int]] = []
    start = previous = int(values[0])
    for raw in values[1:]:
        value = int(raw)
        if value - previous > 12:
            bounds.append((start, previous))
            start = value
        previous = value
    bounds.append((start, previous))
    if len(bounds) != len(ANIMS):
        raise SystemExit(f"动作行数变化：{len(bounds)}，预期 {len(ANIMS)}")
    return bounds


def _large_components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """返回从左到右的高置信主体；低 Alpha 串格毛边不会连接两个动作。"""
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or seen[y, x]:
                continue
            queue = deque([(x, y)])
            seen[y, x] = True
            points: list[tuple[int, int]] = []
            while queue:
                px, py = queue.popleft()
                points.append((px, py))
                for nx, ny in ((px - 1, py - 1), (px, py - 1),
                               (px + 1, py - 1), (px - 1, py),
                               (px + 1, py), (px - 1, py + 1),
                               (px, py + 1), (px + 1, py + 1)):
                    if (0 <= nx < width and 0 <= ny < height
                            and mask[ny, nx] and not seen[ny, nx]):
                        seen[ny, nx] = True
                        queue.append((nx, ny))
            if len(points) >= MIN_COMPONENT_PIXELS:
                components.append(points)
    components.sort(key=lambda points: min(point[0] for point in points))
    return components


def _isolated_frame(
        source: Image.Image, row_y: int,
        points: list[tuple[int, int]]) -> Image.Image:
    """只保留当前主体及其一像素柔边，输出统一正方形安全格。"""
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    x0, x1 = max(0, min(xs) - 2), min(source.width, max(xs) + 3)
    y0, y1 = max(0, row_y + min(ys) - 2), min(source.height, row_y + max(ys) + 3)
    crop = source.crop((x0, y0, x1, y1)).convert("RGBA")

    core = Image.new("L", crop.size, 0)
    core_pixels = core.load()
    for px, py in points:
        core_pixels[px - x0, row_y + py - y0] = 255
    nearby = core.filter(ImageFilter.MaxFilter(3))
    source_alpha = np.asarray(crop.getchannel("A"))
    keep = np.asarray(nearby) > 0
    isolated_alpha = np.where(keep, source_alpha, 0).astype(np.uint8)
    crop.putalpha(Image.fromarray(isolated_alpha, "L"))

    bbox = crop.getbbox()
    canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    if bbox is None:
        return canvas
    content = crop.crop(bbox)
    scale = min(SOURCE_SCALE, (CELL_W - 8) / content.width,
                (CELL_H - 6) / content.height)
    width = max(1, round(content.width * scale))
    height = max(1, round(content.height * scale))
    small = content.resize((width, height), Image.Resampling.NEAREST)
    # 所有帧统一脚底线；四周仍保留透明区，方便逐格无污染裁切。
    canvas.alpha_composite(small, ((CELL_W - width) // 2, BASELINE_Y - height))
    return canvas


def main() -> int:
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != SOURCE_SIZE:
        raise SystemExit(f"动作母表尺寸变化：{source.size}，预期 {SOURCE_SIZE}")
    alpha = np.asarray(source.getchannel("A"))
    if int((alpha == 0).sum()) == 0:
        raise SystemExit("动作母表没有透明像素，拒绝构建伪透明图集")

    rows = _row_bounds(alpha)
    atlas = Image.new(
        "RGBA", (CELL_W * COLS, CELL_H * len(ANIMS)), (0, 0, 0, 0))
    for row, ((name, source_count, used_count, _fps, _loop), (y0, y1)) in enumerate(
            zip(ANIMS, rows)):
        components = _large_components(alpha[y0:y1 + 1] > CORE_ALPHA)
        if len(components) != source_count:
            raise SystemExit(
                f"{name} 行识别到 {len(components)} 帧，预期 {source_count}")
        for col, points in enumerate(components[:used_count]):
            atlas.alpha_composite(_isolated_frame(source, y0, points),
                                  (col * CELL_W, row * CELL_H))
        suffix = "（末帧保留但不使用）" if source_count != used_count else ""
        print(f"{row + 1}: {name} {used_count}/{source_count} 帧{suffix}")

    # 共用 32 色减少帧间色漂；保留用户原图的透明柔边。
    atlas_alpha = atlas.getchannel("A")
    quantized = atlas.convert("RGB").quantize(
        colors=32, method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE).convert("RGBA")
    quantized.putalpha(atlas_alpha)
    quantized.save(ATLAS)
    META.write_text(json.dumps({
        "cell": [CELL_W, CELL_H],
        "baseline_y": BASELINE_Y,
        "columns": COLS,
        "source_frames": {name: source_count for name, source_count, *_ in ANIMS},
        "animations": {
            name: {"row": row, "frames": used_count, "fps": fps, "loop": loop}
            for row, (name, _source_count, used_count, fps, loop) in enumerate(ANIMS)
        },
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已生成 {ATLAS}（{quantized.width}x{quantized.height}，37 个使用帧）")
    print(f"已生成 {META}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
