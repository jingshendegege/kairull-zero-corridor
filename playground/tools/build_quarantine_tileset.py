#!/usr/bin/env python3
"""生成正式第一关“协议检疫站”的独立 11×1 像素瓦片图集。

图集严格沿用 ``CorridorLevel`` 的 32px 索引合同：
0 空、1 # 顶面、2 # 内部、3/4/5 = 左中右、6 |、7 P、8 L、9 r、
10 梯下薄地板。

本脚本只写入隔离目录 ``godot/assets/maps/quarantine``，不会改动旧图集、
地图数据或 Godot 核心脚本。所有图形直接在最终分辨率上以整数坐标绘制，
不经过缩放或抗锯齿；Alpha 只允许 0/255。
"""

from __future__ import annotations

import hashlib
import io
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot" / "assets" / "maps" / "quarantine" / "tileset_quarantine.png"

TS = 32
TILE_COUNT = 11
SHEET_SIZE = (TS * TILE_COUNT, TS)
TILE_NAMES = (
    "空",
    "# 可玩顶面",
    "# 不可见内部",
    "= 平台左端",
    "= 平台中段",
    "= 平台右端",
    "| 墙板",
    "P 管线",
    "L 检疫信号灯",
    "r 栏杆",
    "梯下薄地板",
)

# 与 quarantine_slice 地标共用的冷蓝灰色系。可玩表面保持中等明度，
# 让红、青、品红等血迹都能读清；不可达内部则回到近黑包裹。
VOID = (7, 11, 17, 255)
INK = (12, 18, 29, 255)
DEEP = (20, 29, 43, 255)
STEEL_DARK = (36, 50, 64, 255)
STEEL = (47, 64, 80, 255)
STEEL_MID = (72, 91, 105, 255)
STEEL_EDGE = (101, 121, 132, 255)
STEEL_HI = (128, 148, 158, 255)
SURFACE_HI = (151, 166, 171, 255)
BEAM_WEB = (27, 40, 51, 255)
BEAM_BRACE = (65, 82, 93, 255)
RUST = (120, 69, 54, 255)
RUST_DARK = (82, 49, 42, 255)

# 高饱和色只允许出现在端头警示和小型检疫状态灯，绝不铺成地板光带。
CYAN = (52, 220, 218, 255)
CYAN_DIM = (35, 126, 137, 255)
MAGENTA = (229, 48, 137, 255)
AMBER = (224, 167, 72, 255)
SIGNAL_COLORS = frozenset((CYAN, CYAN_DIM, MAGENTA, AMBER))


def _new_tile(fill=(0, 0, 0, 0)) -> Image.Image:
    return Image.new("RGBA", (TS, TS), fill)


def _paste(sheet: Image.Image, index: int, tile: Image.Image) -> None:
    """按固定槽位粘贴，不使用 mask，完整保留透明像素的零 RGB。"""
    sheet.paste(tile, (index * TS, 0))


def _draw_floor_surface() -> Image.Image:
    """tile 1：连续行走顶沿 + 开放梁腹板；横拼后不再读成 32px 方盒。"""
    tile = _new_tile(STEEL_DARK)
    draw = ImageDraw.Draw(tile)

    # 中性受光顶沿连续跨格；高饱和色完全不进入地板。
    draw.rectangle((0, 0, TS - 1, 0), fill=SURFACE_HI)
    draw.rectangle((0, 1, TS - 1, 1), fill=STEEL_EDGE)
    draw.rectangle((0, 2, TS - 1, 2), fill=DEEP)

    # 上下翼缘夹住深色梁腹板；跨越格边的斜撑拼成连续桁架，不画四边框。
    draw.rectangle((0, 3, TS - 1, 7), fill=STEEL)
    draw.rectangle((0, 8, TS - 1, 24), fill=BEAM_WEB)
    draw.line((-2, 24, 13, 8), fill=BEAM_BRACE, width=3)
    draw.line((18, 8, 33, 24), fill=BEAM_BRACE, width=3)
    draw.line((0, 23, 14, 9), fill=STEEL_MID, width=1)
    draw.line((18, 9, 31, 22), fill=STEEL_MID, width=1)
    draw.rectangle((0, 25, TS - 1, 29), fill=STEEL_DARK)
    draw.rectangle((0, 30, TS - 1, 31), fill=DEEP)

    # 贯通检修槽跨到左右格边，避免每 32px 出现一个中央“小屏幕”。
    draw.rectangle((0, 13, TS - 1, 17), fill=INK)
    draw.line((0, 13, TS - 1, 13), fill=STEEL_DARK, width=1)
    draw.line((0, 17, TS - 1, 17), fill=DEEP, width=1)
    draw.point((7, 5), fill=STEEL_HI)
    draw.point((25, 5), fill=STEEL_HI)
    draw.line((23, 27, 27, 27), fill=RUST, width=1)
    draw.point((28, 28), fill=RUST_DARK)
    return tile


def _draw_floor_interior() -> Image.Image:
    """tile 2：只承担碰撞内部显示，完全融入近黑虚空，不再露出方格框。"""
    return _new_tile(VOID)


def _draw_stair_floor_cap() -> Image.Image:
    """tile 10：梯下实心地面只显示开放薄梁，其余区域透出黑暗后景。"""
    tile = _new_tile()
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, TS - 1, 0), fill=SURFACE_HI)
    draw.rectangle((0, 1, TS - 1, 1), fill=STEEL_EDGE)
    draw.rectangle((0, 2, TS - 1, 2), fill=DEEP)
    draw.rectangle((0, 3, TS - 1, 5), fill=STEEL)
    draw.rectangle((0, 6, TS - 1, 9), fill=BEAM_WEB)
    draw.line((-2, 10, 10, 5), fill=BEAM_BRACE, width=2)
    draw.line((21, 5, 33, 10), fill=BEAM_BRACE, width=2)
    draw.rectangle((0, 10, TS - 1, 11), fill=DEEP)
    draw.point((15, 7), fill=STEEL_HI)
    return tile


def _draw_platform(left_cap: bool, right_cap: bool) -> Image.Image:
    """tiles 3–5：中性顶沿、承重腹板与梁槽；下方保持透明。"""
    tile = _new_tile()
    draw = ImageDraw.Draw(tile)

    # 行走面连续且中性；高饱和色只能进入端头标记。
    draw.rectangle((0, 0, TS - 1, 0), fill=STEEL_HI)
    draw.rectangle((0, 1, TS - 1, 1), fill=STEEL_EDGE)
    draw.rectangle((0, 2, TS - 1, 2), fill=INK)

    # 13px 深的主梁：单一贯通梁槽 + 错向斜撑，避免重复成两只小方盒。
    draw.rectangle((0, 3, TS - 1, 5), fill=STEEL)
    draw.rectangle((0, 6, TS - 1, 9), fill=BEAM_WEB)
    draw.rectangle((0, 10, TS - 1, 12), fill=STEEL_DARK)
    draw.rectangle((6, 7, 25, 8), fill=INK)
    # Pillow 偶数线宽会向正方向多占 1px，端点收在 y=11，确保 y=13 起透明。
    draw.line((-2, 11, 11, 6), fill=BEAM_BRACE, width=2)
    draw.line((21, 6, 34, 11), fill=BEAM_BRACE, width=2)
    draw.rectangle((0, 12, TS - 1, 12), fill=INK)

    if left_cap:
        draw.rectangle((0, 0, 2, 12), fill=INK)
        draw.rectangle((2, 1, 2, 10), fill=STEEL_MID)
        draw.rectangle((3, 4, 5, 6), fill=AMBER)
        draw.point((4, 5), fill=INK)
    if right_cap:
        draw.rectangle((TS - 3, 0, TS - 1, 12), fill=INK)
        draw.rectangle((TS - 3, 1, TS - 3, 10), fill=STEEL_MID)
        draw.rectangle((TS - 6, 4, TS - 4, 6), fill=AMBER)
        draw.point((TS - 5, 5), fill=INK)
    return tile


def _draw_wall_panel() -> Image.Image:
    """tile 6：可见检疫墙板，明度低于行走顶沿但足以承接彩色血迹。"""
    tile = _new_tile(STEEL_DARK)
    draw = ImageDraw.Draw(tile)
    draw.rectangle((1, 1, 30, 30), fill=STEEL)
    draw.rectangle((3, 3, 14, 14), fill=STEEL_DARK)
    draw.rectangle((17, 3, 28, 14), fill=(53, 71, 86, 255))
    draw.rectangle((3, 17, 14, 28), fill=(43, 59, 73, 255))
    draw.rectangle((17, 17, 28, 28), fill=STEEL_DARK)
    draw.rectangle((15, 1, 16, 30), fill=DEEP)
    draw.rectangle((1, 15, 30, 16), fill=DEEP)
    for point in ((3, 3), (28, 3), (3, 28), (28, 28)):
        draw.point(point, fill=STEEL_MID)
    draw.line((20, 22, 26, 22), fill=STEEL_MID, width=1)
    draw.point((9, 10), fill=RUST)
    draw.rectangle((9, 11, 10, 13), fill=RUST_DARK)
    return tile


def _draw_pipe() -> Image.Image:
    """tile 7：透明底的检疫介质竖管和锈蚀管箍。"""
    tile = _new_tile()
    draw = ImageDraw.Draw(tile)
    draw.rectangle((9, 0, 22, TS - 1), fill=INK)
    draw.rectangle((11, 0, 20, TS - 1), fill=STEEL)
    draw.rectangle((12, 0, 13, TS - 1), fill=STEEL_MID)
    draw.rectangle((20, 0, 20, TS - 1), fill=DEEP)
    for y in (6, 22):
        draw.rectangle((7, y, 24, y + 3), fill=INK)
        draw.rectangle((8, y, 23, y + 1), fill=STEEL_EDGE)
    draw.rectangle((8, 22, 12, 23), fill=RUST)
    draw.rectangle((9, 24, 11, 25), fill=RUST_DARK)
    return tile


def _draw_signal_fixture() -> Image.Image:
    """tile 8：小型检疫状态灯；无透明光晕、无贯穿整格的霓虹条。"""
    tile = _new_tile()
    draw = ImageDraw.Draw(tile)
    draw.rectangle((4, 2, 27, 4), fill=INK)
    draw.rectangle((7, 5, 24, 13), fill=DEEP)
    draw.rectangle((8, 6, 23, 12), fill=STEEL_DARK)
    draw.rectangle((10, 7, 15, 9), fill=CYAN_DIM)
    draw.rectangle((11, 7, 14, 8), fill=CYAN)
    draw.rectangle((18, 7, 20, 9), fill=MAGENTA)
    draw.rectangle((22, 8, 23, 10), fill=AMBER)
    draw.rectangle((12, 14, 19, 16), fill=INK)
    draw.rectangle((15, 16, 16, 20), fill=STEEL_DARK)
    return tile


def _draw_railing() -> Image.Image:
    """tile 9：透明底的厚重钢栏杆，少量锈迹交代废弃状态。"""
    tile = _new_tile()
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 9, TS - 1, 12), fill=INK)
    draw.rectangle((0, 9, TS - 1, 10), fill=STEEL_EDGE)
    draw.rectangle((0, 20, TS - 1, 22), fill=INK)
    draw.rectangle((0, 20, TS - 1, 20), fill=STEEL_MID)
    for x in (3, 15, 27):
        draw.rectangle((x, 11, x + 3, TS - 1), fill=INK)
        draw.rectangle((x + 1, 12, x + 1, TS - 1), fill=STEEL_MID)
    draw.rectangle((15, 9, 20, 10), fill=RUST)
    draw.rectangle((17, 11, 19, 12), fill=RUST_DARK)
    return tile


def build_tileset() -> Image.Image:
    """在内存中构造确定性的 352×32 RGBA 图集。"""
    sheet = Image.new("RGBA", SHEET_SIZE, (0, 0, 0, 0))
    _paste(sheet, 1, _draw_floor_surface())
    _paste(sheet, 2, _draw_floor_interior())
    _paste(sheet, 3, _draw_platform(left_cap=True, right_cap=False))
    _paste(sheet, 4, _draw_platform(left_cap=False, right_cap=False))
    _paste(sheet, 5, _draw_platform(left_cap=False, right_cap=True))
    _paste(sheet, 6, _draw_wall_panel())
    _paste(sheet, 7, _draw_pipe())
    _paste(sheet, 8, _draw_signal_fixture())
    _paste(sheet, 9, _draw_railing())
    _paste(sheet, 10, _draw_stair_floor_cap())
    return sheet


def tile_at(sheet: Image.Image, index: int) -> Image.Image:
    """返回指定槽位的独立 32×32 副本，供生成期断言与测试使用。"""
    if not 0 <= index < TILE_COUNT:
        raise IndexError(f"瓦片索引越界: {index}")
    return sheet.crop((index * TS, 0, (index + 1) * TS, TS))


def pixels_of(image: Image.Image) -> tuple:
    """兼容新旧 Pillow 的扁平像素读取，并避开 Pillow 14 的弃用接口。"""
    if hasattr(image, "get_flattened_data"):
        return tuple(image.get_flattened_data())
    return tuple(image.getdata())


def _luminance(pixel: tuple[int, int, int, int]) -> float:
    return pixel[0] * 0.2126 + pixel[1] * 0.7152 + pixel[2] * 0.0722


def _average_luminance(tile: Image.Image) -> float:
    pixels = [pixel for pixel in pixels_of(tile) if pixel[3] == 255]
    return sum(_luminance(pixel) for pixel in pixels) / len(pixels)


def _longest_signal_run(sheet: Image.Image) -> int:
    longest = 0
    for y in range(sheet.height):
        run = 0
        for x in range(sheet.width):
            if sheet.getpixel((x, y)) in SIGNAL_COLORS:
                run += 1
                longest = max(longest, run)
            else:
                run = 0
    return longest


def validate_tileset(sheet: Image.Image) -> None:
    """内置生成期合同：尺寸、槽位、Alpha、明度层级与信号色预算。"""
    assert sheet.mode == "RGBA", f"图集必须为 RGBA，实际 {sheet.mode}"
    assert sheet.size == SHEET_SIZE, f"图集尺寸必须为 {SHEET_SIZE}，实际 {sheet.size}"
    assert set(pixels_of(sheet.getchannel("A"))) <= {0, 255}, "Alpha 必须严格二值化"

    empty = tile_at(sheet, 0)
    assert set(pixels_of(empty)) == {(0, 0, 0, 0)}, "tile 0 必须是零 RGB 的全透明空格"

    # 实心墙块不允许漏背景；装饰与单向台则必须保留透明区域。
    for index in (1, 2, 6):
        assert set(pixels_of(tile_at(sheet, index).getchannel("A"))) == {255}, (
            f"tile {index} {TILE_NAMES[index]} 必须完全不透明"
        )
    for index in (3, 4, 5, 7, 8, 9, 10):
        assert set(pixels_of(tile_at(sheet, index).getchannel("A"))) == {0, 255}, (
            f"tile {index} {TILE_NAMES[index]} 必须同时含透明与实体像素"
        )

    floor = tile_at(sheet, 1)
    interior = tile_at(sheet, 2)
    assert all(floor.getpixel((x, 0)) == SURFACE_HI for x in range(TS)), (
        "tile 1 顶沿必须连续且为中性钢色"
    )
    assert _average_luminance(interior) < 24.0, "tile 2 必须维持近黑包裹"
    assert set(pixels_of(interior)) == {VOID}, "tile 2 不得再绘制可见方格或边框"
    assert _average_luminance(floor) > _average_luminance(interior) + 24.0, (
        "可玩表面与不可达内部的明度层级不足"
    )
    # 上下翼缘必须横向连续，且腹板含足量斜撑；禁止退回每格四边框的小箱子。
    for y in (3, 4, 5, 25, 26, 29, 30, 31):
        assert floor.getpixel((0, y)) == floor.getpixel((TS - 1, y)), (
            f"tile 1 横拼边在 y={y} 不连续"
        )
    floor_pixels = pixels_of(floor)
    assert floor_pixels.count(BEAM_BRACE) >= 46, "tile 1 缺少可读的开放桁架腹板"
    assert not all(floor.getpixel((0, y)) in (INK, DEEP) for y in range(3, 30)), (
        "tile 1 左边缘形成整高暗框"
    )
    assert not all(floor.getpixel((TS - 1, y)) in (INK, DEEP) for y in range(3, 30)), (
        "tile 1 右边缘形成整高暗框"
    )

    # 平台顶沿连续、下方透明；信号色只出现在左右端头，不能形成光带。
    for index in (3, 4, 5):
        platform = tile_at(sheet, index)
        assert all(platform.getpixel((x, 13))[3] == 0 for x in range(TS)), (
            f"tile {index} 平台 13px 以下必须透明"
        )
        assert all(platform.getpixel((x, 0)) not in SIGNAL_COLORS for x in range(TS)), (
            f"tile {index} 平台顶沿不得使用信号色"
        )
        assert INK in set(pixels_of(platform)) and BEAM_BRACE in set(pixels_of(platform)), (
            f"tile {index} 平台缺少梁槽或斜撑"
        )
    assert not any(pixel in SIGNAL_COLORS for pixel in pixels_of(tile_at(sheet, 4))), (
        "平台中段不得出现连续警示色"
    )
    assert AMBER in set(pixels_of(tile_at(sheet, 3))), "平台左端缺少小型琥珀警示"
    assert AMBER in set(pixels_of(tile_at(sheet, 5))), "平台右端缺少小型琥珀警示"

    stair_cap = tile_at(sheet, 10)
    assert all(stair_cap.getpixel((x, 0)) == SURFACE_HI for x in range(TS)), (
        "梯下薄地板必须保留连续可走顶沿"
    )
    assert all(stair_cap.getpixel((x, 12))[3] == 0 for x in range(TS)), (
        "梯下薄地板 12px 以下必须透明，让黑暗后景连续"
    )
    assert not any(pixel in SIGNAL_COLORS for pixel in pixels_of(stair_cap)), (
        "梯下薄地板不得加入抢眼信号色"
    )

    for index in (1, 2, 6):
        assert not any(pixel in SIGNAL_COLORS for pixel in pixels_of(tile_at(sheet, index))), (
            f"tile {index} 大面积建筑面不得混入高饱和信号色"
        )
    signal_count = sum(pixel in SIGNAL_COLORS for pixel in pixels_of(sheet))
    assert signal_count <= 64, f"信号色像素预算超标: {signal_count} > 64"
    assert _longest_signal_run(sheet) <= 6, "检测到疑似整条霓虹，最长信号色连续段超过 6px"


def encode_png(sheet: Image.Image) -> bytes:
    """用固定编码参数输出 PNG；构造图不含时间戳或随机元数据。"""
    stream = io.BytesIO()
    sheet.save(stream, format="PNG", optimize=False, compress_level=9)
    return stream.getvalue()


def main() -> None:
    first = build_tileset()
    second = build_tileset()
    validate_tileset(first)
    validate_tileset(second)

    payload = encode_png(first)
    repeated = encode_png(second)
    assert payload == repeated, "相同输入生成的 PNG 字节不一致"

    OUT.parent.mkdir(parents=True, exist_ok=True)
    changed = not OUT.exists() or OUT.read_bytes() != payload
    if changed:
        OUT.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    state = "written" if changed else "unchanged"
    print(f"{state}: {OUT} ({first.width}x{first.height}, sha256={digest})")


if __name__ == "__main__":
    main()
