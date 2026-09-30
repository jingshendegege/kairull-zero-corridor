#!/usr/bin/env python3
"""武士零风格地图 4 层 PNG 验收脚本（管线合同附件）。

用法：
  python map_acceptance.py --alpha  layer.png            # L1/L3 真 alpha：黑底合成查白边
  python map_acceptance.py --seam   layer.png            # L0 offset 50% 横向接缝差值
  python map_acceptance.py --walkway layer.png sprite.png out.png --walk-y 0.78
                                                         # L2 走道带亮度 + 凯露尔合成可读性图
全部检查输出 PASS/FAIL 与关键数值；--walkway 额外落盘一张合成验收图。
"""
import argparse
import sys

from PIL import Image, ImageChops, ImageStat


def check_alpha(path: str, edge_thresh: float = 12.0) -> bool:
    """半透明层验收：必须真含透明像素；半透明边缘不得带白边（亮色晕）。

    白边判定：alpha 在 8..247 的像素里，RGB 亮度中位数若显著偏高，
    说明是从白底抠下来的，黑底下会泛白。
    """
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A")
    lo, hi = a.getextrema()
    if lo > 250:
        print(f"FAIL alpha: 完全不透明（alpha min={lo}），不是透明层")
        return False
    semi = []
    px = im.load()
    w, h = im.size
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b, av = px[x, y]
            if 8 <= av <= 247:
                semi.append((r + g + b) / 3.0)
    if not semi:
        print("PASS alpha: 边缘锐利（无半透明过渡区），天然无白边")
        return True
    semi.sort()
    med = semi[len(semi) // 2]
    ok = med < 200.0 - edge_thresh
    print(f"{'PASS' if ok else 'FAIL'} alpha: 半透明边缘亮度中位数 {med:.1f}"
          f"（阈值 {200.0 - edge_thresh:.1f}，越高越像白底残留）")
    return ok


def check_seam(path: str, max_diff: float = 26.0) -> bool:
    """L0 无缝验收：左右边缘相邻列的均色差。直接比较首尾列邻带。"""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    band = 8
    left = im.crop((0, 0, band, h))
    right = im.crop((w - band, 0, w, h))
    stat = ImageStat.Stat(ImageChops.difference(left, right))
    mean = sum(stat.mean) / 3.0
    ok = mean <= max_diff
    print(f"{'PASS' if ok else 'FAIL'} seam: 左右边缘 {band}px 带均色差 {mean:.1f}"
          f"（阈值 {max_diff:.1f}）")
    if not ok:
        off = im.copy()
        off.load()
        rolled = Image.new("RGB", (w, h))
        rolled.paste(im.crop((w // 2, 0, w, h)), (0, 0))
        rolled.paste(im.crop((0, 0, w // 2, h)), (w // 2, 0))
        out = path.rsplit(".", 1)[0] + "_offset_debug.png"
        rolled.save(out)
        print(f"  已落盘 offset 调试图：{out}（接缝移到画面中央，人工修补用）")
    return ok


def check_walkway(layer_path: str, sprite_path: str, out_path: str,
                  walk_y: float, max_luma: float = 70.0) -> bool:
    """L2 验收：走道带亮度足够暗 + 合成角色精灵出验收图。

    walk_y: 走道中心占图高比例（0~1）。取 walk_y±8% 高度带测亮度中位数，
    并把精灵脚底对齐 walk_y 合成到画面中央。
    """
    im = Image.open(layer_path).convert("RGB")
    w, h = im.size
    y0 = int(h * (walk_y - 0.08))
    y1 = int(h * (walk_y + 0.08))
    band = im.crop((0, y0, w, y1)).convert("L")
    hist = band.histogram()
    total = sum(hist)
    acc, med = 0, 0
    for i, c in enumerate(hist):
        acc += c
        if acc >= total // 2:
            med = i
            break
    ok = med <= max_luma
    print(f"{'PASS' if ok else 'FAIL'} walkway: 走道带亮度中位数 {med}"
          f"（阈值 {max_luma:.0f}，带 {y0}-{y1}px）")

    sprite = Image.open(sprite_path).convert("RGBA")
    target_h = int(h * 0.14)  # 角色约 2.6 格 ≈ 画面高度 14%（1536×1024 下约 143px）
    ratio = target_h / sprite.height
    sprite = sprite.resize((max(1, int(sprite.width * ratio)), target_h), Image.NEAREST)
    canvas = im.convert("RGBA")
    canvas.paste(sprite, (w // 2 - sprite.width // 2, int(h * walk_y) - sprite.height), sprite)
    canvas.convert("RGB").save(out_path)
    print(f"  合成验收图：{out_path}（请人工确认白毛衣剪影在走道带上可读）")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--alpha", action="store_true")
    ap.add_argument("--seam", action="store_true")
    ap.add_argument("--walkway", action="store_true")
    ap.add_argument("--walk-y", type=float, default=0.78)
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()

    ok = True
    if args.alpha:
        ok &= check_alpha(args.files[0])
    if args.seam:
        ok &= check_seam(args.files[0])
    if args.walkway:
        if len(args.files) < 3:
            print("--walkway 需要 layer.png sprite.png out.png 三个路径")
            return 2
        ok &= check_walkway(args.files[0], args.files[1], args.files[2], args.walk_y)
    if not (args.alpha or args.seam or args.walkway):
        ap.print_help()
        return 2
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
