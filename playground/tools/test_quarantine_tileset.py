#!/usr/bin/env python3
"""协议检疫站瓦片图集的独立生成期回归测试。"""

from __future__ import annotations

import hashlib
import sys
import unittest
from pathlib import Path

from PIL import Image


sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_quarantine_tileset as gen


class QuarantineTilesetTest(unittest.TestCase):
    def setUp(self) -> None:
        self.sheet = gen.build_tileset()

    def test_generator_contract(self) -> None:
        """生成器自身的尺寸、Alpha、明度和信号预算断言必须全通过。"""
        gen.validate_tileset(self.sheet)

    def test_slot_contract_is_exactly_11_by_1(self) -> None:
        self.assertEqual(self.sheet.mode, "RGBA")
        self.assertEqual(self.sheet.size, (352, 32))
        self.assertEqual(len(gen.TILE_NAMES), 11)
        self.assertEqual(gen.TILE_NAMES[1], "# 可玩顶面")
        self.assertEqual(gen.TILE_NAMES[2], "# 不可见内部")
        self.assertEqual(gen.TILE_NAMES[3:6], ("= 平台左端", "= 平台中段", "= 平台右端"))
        self.assertEqual(gen.TILE_NAMES[10], "梯下薄地板")

    def test_alpha_contract_is_binary_and_semantic(self) -> None:
        self.assertEqual(set(gen.pixels_of(self.sheet.getchannel("A"))), {0, 255})
        self.assertEqual(set(gen.pixels_of(gen.tile_at(self.sheet, 0))), {(0, 0, 0, 0)})
        for index in (1, 2, 6):
            self.assertEqual(set(gen.pixels_of(gen.tile_at(self.sheet, index).getchannel("A"))), {255})
        for index in (3, 4, 5, 7, 8, 9, 10):
            self.assertEqual(
                set(gen.pixels_of(gen.tile_at(self.sheet, index).getchannel("A"))),
                {0, 255},
            )

    def test_platform_has_structure_without_neon_strip(self) -> None:
        for index in (3, 4, 5):
            tile = gen.tile_at(self.sheet, index)
            self.assertTrue(all(tile.getpixel((x, 0))[3] == 255 for x in range(32)))
            self.assertTrue(all(tile.getpixel((x, 13))[3] == 0 for x in range(32)))
            self.assertTrue(all(tile.getpixel((x, 0)) not in gen.SIGNAL_COLORS for x in range(32)))
            self.assertIn(gen.INK, set(gen.pixels_of(tile)))
            self.assertIn(gen.BEAM_BRACE, set(gen.pixels_of(tile)))
        self.assertFalse(any(
            pixel in gen.SIGNAL_COLORS for pixel in gen.pixels_of(gen.tile_at(self.sheet, 4))
        ))

    def test_floor_surface_joins_as_open_beam_not_repeated_boxes(self) -> None:
        """地板横拼保持贯通翼缘，腹板有斜撑但没有左右整高暗框。"""
        floor = gen.tile_at(self.sheet, 1)
        for y in (3, 4, 5, 25, 26, 29, 30, 31):
            self.assertEqual(floor.getpixel((0, y)), floor.getpixel((31, y)))
        self.assertGreaterEqual(gen.pixels_of(floor).count(gen.BEAM_BRACE), 46)
        self.assertFalse(all(
            floor.getpixel((0, y)) in (gen.INK, gen.DEEP) for y in range(3, 30)
        ))
        self.assertFalse(all(
            floor.getpixel((31, y)) in (gen.INK, gen.DEEP) for y in range(3, 30)
        ))

    def test_unreachable_interior_is_darker_than_playable_surface(self) -> None:
        surface = gen.tile_at(self.sheet, 1)
        interior = gen.tile_at(self.sheet, 2)
        self.assertGreater(
            gen._average_luminance(surface),
            gen._average_luminance(interior) + 24.0,
        )
        self.assertTrue(all(surface.getpixel((x, 0)) == gen.SURFACE_HI for x in range(32)))
        self.assertEqual(set(gen.pixels_of(interior)), {gen.VOID})

    def test_stair_floor_cap_is_thin_and_unframed(self) -> None:
        cap = gen.tile_at(self.sheet, 10)
        self.assertTrue(all(cap.getpixel((x, 0)) == gen.SURFACE_HI for x in range(32)))
        self.assertTrue(all(cap.getpixel((x, 12))[3] == 0 for x in range(32)))
        self.assertFalse(any(
            pixel in gen.SIGNAL_COLORS for pixel in gen.pixels_of(cap)
        ))

    def test_png_encoding_is_deterministic(self) -> None:
        first = gen.encode_png(self.sheet)
        second = gen.encode_png(gen.build_tileset())
        self.assertEqual(first, second)
        self.assertEqual(hashlib.sha256(first).hexdigest(), hashlib.sha256(second).hexdigest())

    def test_checked_in_asset_matches_generator(self) -> None:
        self.assertTrue(gen.OUT.exists(), f"请先运行生成器：{gen.OUT}")
        expected = gen.encode_png(self.sheet)
        self.assertEqual(gen.OUT.read_bytes(), expected)
        with Image.open(gen.OUT) as actual:
            self.assertEqual(actual.mode, "RGBA")
            self.assertEqual(actual.size, (352, 32))
            self.assertEqual(actual.info, {})


if __name__ == "__main__":
    unittest.main(verbosity=2)
