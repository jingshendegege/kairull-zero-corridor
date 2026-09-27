#!/usr/bin/env python3
"""垂直货运井只读合同：六层错位双塔、长程货梯开口、空间唤醒、旧图不变。"""
import copy
import json
import unittest
import gen_m05_vertical_freight as gen


class VerticalFreightContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads(gen.SOURCE.read_text(encoding="utf-8"))
        cls.level, cls.layers = gen.base._level_and_layers(cls.doc)

    def test_generated_exact_source(self):
        self.assertEqual(gen.compile_path(), gen.OUTPUT.read_text(encoding="utf-8"))

    def test_bottom_spawn_migration_only_moves_known_marker(self):
        doc = copy.deepcopy(self.doc)
        grid = next(item["intGridCsv"] for item in doc["levels"][0]["layerInstances"] if item["__identifier"] == "Entities")
        grid[104 * gen.W + 74], grid[50 * gen.W + 74] = 0, 1
        expected = copy.deepcopy(doc)
        expected_grid = next(item["intGridCsv"] for item in expected["levels"][0]["layerInstances"] if item["__identifier"] == "Entities")
        expected_grid[104 * gen.W + 74], expected_grid[50 * gen.W + 74] = 1, 0
        self.assertTrue(gen.move_spawn_to_bottom(doc))
        self.assertEqual(doc, expected)
        self.assertFalse(gen.move_spawn_to_bottom(doc))
        grid[104 * gen.W + 74], grid[103 * gen.W + 74] = 0, 1
        with self.assertRaises(gen.base.MapError):
            gen.move_spawn_to_bottom(doc)

    def test_real_vertical_dimensions(self):
        self.assertEqual((self.level["pxWid"], self.level["pxHei"]), (144 * 32, 114 * 32))
        floors = gen.base._metadata(self.level, "RoomFloors")
        self.assertEqual([f["center_floor"] for f in floors], [105, 87, 69, 51, 33, 15])
        self.assertTrue(all(f["left_floor"] - f["right_floor"] == 6 for f in floors))

    def test_twenty_unique_nonoverlapping_rooms(self):
        rooms = gen.base._metadata(self.level, "RoomMetadata")
        gen.validate_rooms(self.layers["Rooms"], rooms)
        self.assertEqual(len(rooms), 20)
        self.assertEqual(sum(room["role"] == "main" for room in rooms), 12)
        self.assertEqual(sum(room["role"] == "connector" for room in rooms), 6)
        self.assertEqual(sum(room["role"] == "shaft" for room in rooms), 2)

    def test_fiftytwo_defenders_twentysix_cargo(self):
        values = self.layers["Entities"]
        self.assertEqual((values.count(3), values.count(4), values.count(5)), (26, 26, 26))
        self.assertEqual((values.count(1), values.count(2)), (1, 1))
        per_room = [0] * 20
        for index, value in enumerate(values):
            if value in {3, 4}:
                per_room[self.layers["Rooms"][index] - 1] += 1
        self.assertEqual(sorted(count for count in per_room if count), [4] * 10 + [6] * 2)

    def test_bottom_spawn_and_upper_exit(self):
        spawn = self.layers["Entities"].index(1)
        exit_point = self.layers["Entities"].index(2)
        self.assertEqual((spawn % gen.W, spawn // gen.W), (74, 104))
        self.assertEqual((exit_point % gen.W, exit_point // gen.W), (74, 14))

    def test_four_lifts_cross_whole_storeys(self):
        items = gen.validate_tactics(self.doc)
        lifts = [item for item in items if item["type"] == "freight_lift"]
        self.assertEqual(len(lifts), 4)
        self.assertEqual([int(item["pos"][0] // 32) for item in lifts], [86, 98, 86, 98])
        self.assertTrue(all(item["pos"][1] - item["top_y"] == 576 for item in lifts))
        self.assertTrue(all(item["travel_time"] == 3.6 and item["dwell"] == 1.2 for item in lifts))

    def test_lifts_have_actual_open_landings(self):
        for item in gen.validate_tactics(self.doc):
            if item["type"] != "freight_lift":
                continue
            center = int(item["pos"][0] // 32)
            for floor in [int(item["pos"][1] // 32), int(item["top_y"] // 32)]:
                for x in range(center - 1, center + 2):
                    self.assertEqual(gen.base._cell(self.layers["Collision"], x, floor), 0)
                self.assertEqual(gen.base._cell(self.layers["Collision"], center - 2, floor), 2)
                self.assertEqual(gen.base._cell(self.layers["Collision"], center + 2, floor), 2)

    def test_six_room_stairs_and_fifteen_maintenance_platforms(self):
        stairs = gen.base._metadata(self.level, "StairMetadata")
        self.assertEqual(len(stairs), 6)
        self.assertEqual(sum(stair["steps"] for stair in stairs), 72)
        for floor in [105, 87, 69, 51, 33]:
            for x0, x1, y in [(58, 64, floor - 3), (55, 61, floor - 6), (52, 58, floor - 9)]:
                for x in range(x0, x1 + 1):
                    self.assertEqual(gen.base._cell(self.layers["Collision"], x, y), 2)

    def test_safe_hubs_and_shafts_have_no_enemy_spawns(self):
        room_meta = gen.base._metadata(self.level, "RoomMetadata")
        for index, value in enumerate(self.layers["Entities"]):
            if value in {3, 4}:
                room = room_meta[self.layers["Rooms"][index] - 1]
                self.assertEqual(room["role"], "main")

    def test_tactical_budget_and_clear_purposes(self):
        items = gen.validate_tactics(self.doc)
        self.assertEqual(len(items), 25)
        self.assertEqual(sum(item["type"] == "smoke_pickup" for item in items), 8)
        self.assertEqual(sum(item["type"] == "auto_sniper" and item["hard_only"] for item in items), 2)
        self.assertTrue(all(item["purpose"] and len(item["solutions"]) >= 2 for item in items))

    def test_free_exploration_with_one_lower_clear_checkpoint(self):
        self.assertEqual(gen.base._metadata(self.level, "EncounterBoundaries"), [])
        self.assertEqual(gen.base._metadata(self.level, "EncounterPolicy"), "same_floor_nearby")
        self.assertNotIn("checkpoint_cell", json.dumps(self.doc))
        self.assertEqual(gen.base.checkpoint_contract.validate(self.doc, gen.base.MapError),
                         [{"id": "m05_hub_after_lower", "room_index": 0,
                           "cell": [71, 50], "required_clear_rooms": [3, 4, 5, 6, 7, 8]}])

    def test_solid_roof_across_lift_is_rejected(self):
        doc = copy.deepcopy(self.doc)
        collision = next(layer for layer in doc["levels"][0]["layerInstances"] if layer["__identifier"] == "Collision")["intGridCsv"]
        collision[96 * gen.W + 86] = 1
        with self.assertRaisesRegex(gen.base.MapError, "实心楼板"):
            gen.validate_tactics(doc)

    def test_compile_preserves_existing_first_and_second_maps(self):
        paths = [gen.ROOT / "godot/maps/m01_protocol_quarantine.ldtk", gen.ROOT / "godot/maps/m04_chrono_freight.ldtk"]
        before = [path.read_bytes() for path in paths]
        source_before = gen.SOURCE.read_bytes()
        gen.compile_path()
        self.assertEqual(before, [path.read_bytes() for path in paths])
        self.assertEqual(source_before, gen.SOURCE.read_bytes())

    def test_crown_overhead_clearance_and_honest_side_steps(self):
        for start, end, upper, ground in [(14, 26, 17, 21), (114, 132, 11, 15)]:
            self.assertGreaterEqual((ground - upper) * 32 - 12, 94 + 16)
            for x in range(start, end + 1):
                self.assertEqual(gen.base._cell(self.layers["Collision"], x, upper), 2)
                self.assertEqual(gen.base._cell(self.layers["Collision"], x, ground), 1)
        for x0, x1, top, floor in [(11, 12, 19, 21), (111, 112, 13, 15)]:
            self.assertEqual((floor - top) * 32, 64)
            for x in range(x0, x1 + 1):
                self.assertEqual(gen.base._cell(self.layers["Collision"], x, top), 1)
                self.assertEqual(gen.base._cell(self.layers["Collision"], x, floor - 1), 1)
        self.assertFalse(gen.upgrade_crown_clearance(copy.deepcopy(self.doc)))

    def test_crown_high_defenders_and_cargo_follow_new_surfaces(self):
        for x, floor, kind in [(16, 17, 4), (24, 17, 3), (21, 17, 5),
                              (116, 11, 4), (128, 11, 3), (123, 11, 5)]:
            self.assertEqual(gen.base._cell(self.layers["Entities"], x, floor - 1), kind)
        laser = next(item for item in gen.validate_tactics(self.doc) if item["id"] == "laser_6")
        self.assertEqual(laser["pos"], [121 * 32, 15 * 32 - 54])
        self.assertEqual(gen.base._cell(self.layers["Collision"], 121, 13), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
