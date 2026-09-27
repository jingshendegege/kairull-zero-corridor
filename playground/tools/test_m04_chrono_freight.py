#!/usr/bin/env python3
"""时差货运场只读合同；禁止此测试改写第一关或任何 LDtk。"""
import copy
import json
import unittest
import gen_m04_chrono_freight as gen


class ChronoFreightContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads(gen.SOURCE.read_text(encoding="utf-8"))

    def test_source_and_generated_exact(self):
        self.assertEqual(gen.compile_path(), gen.OUTPUT.read_text(encoding="utf-8"))

    def test_long_level_and_combat_budget(self):
        level, layers = gen.base._level_and_layers(self.doc)
        self.assertEqual((level["pxWid"], level["pxHei"]), (460 * 32, 36 * 32))
        self.assertEqual(len(gen.base._metadata(level, "RoomMetadata")), 14)
        entities = layers["Entities"]
        self.assertEqual(entities.count(3) + entities.count(4), 38)
        self.assertEqual((entities.count(3), entities.count(4)), (19, 19))
        self.assertEqual(entities.count(5), 20)
        self.assertEqual(entities.count(1), 1)
        self.assertEqual(entities.count(2), 1)

    def test_seed_deterministic_and_no_source_mutation(self):
        before = gen.SOURCE.read_bytes()
        first = gen.seed_document()
        second = gen.seed_document()
        self.assertEqual(first, second)
        # LDtk 可以重新格式化字符串/用户可继续改图，不能把 seed 相等误作日常保存合同。
        gen.compile_path()
        self.assertEqual(before, gen.SOURCE.read_bytes())

    def test_one_checkpoint_separate_from_two_encounter_boundaries(self):
        tactical, boundaries = gen.validate_tactical(self.doc)
        self.assertEqual(boundaries, [4, 8])
        self.assertNotIn("checkpoint_cell", json.dumps(self.doc))
        self.assertEqual(gen.base.checkpoint_contract.validate(self.doc, gen.base.MapError),
                         [{"id": "m04_observatory_mid", "room_index": 8,
                           "cell": [278, 26], "required_clear_rooms": [1, 2, 3, 5, 6, 7]}])
        self.assertEqual(len(tactical), 15)

    def test_five_open_staircases(self):
        stairs = gen.base._metadata(self.doc["levels"][0], "StairMetadata")
        self.assertEqual(len(stairs), 5)
        self.assertEqual(sum(s["steps"] for s in stairs), 50)
        self.assertEqual(sum(s["direction"] == "left_up" for s in stairs), 2)
        gen.compile_document(self.doc, "contract")

    def test_all_pickups_have_position_specific_purpose(self):
        tactical, _ = gen.validate_tactical(self.doc)
        smoke = [item for item in tactical if item["type"] == "smoke_pickup"]
        self.assertEqual(len(smoke), 6)
        self.assertEqual(len({item["purpose"] for item in smoke}), 6)
        for a, b in zip(smoke, smoke[1:]):
            self.assertGreater(abs(a["pos"][0] - b["pos"][0]), 16 * 32)

    def test_sparse_telegraphed_hazards(self):
        tactical, _ = gen.validate_tactical(self.doc)
        snipers = [item for item in tactical if item["type"] == "auto_sniper"]
        self.assertEqual(len(snipers), 2)
        self.assertTrue(snipers[0]["hard_only"])
        for sniper in snipers:
            self.assertGreater(sniper["pos"][0], 280 * 32)
            self.assertLessEqual(sniper["range"], 1024)
        for item in tactical:
            self.assertGreaterEqual(len(item["solutions"]), 2)
            if item["type"] == "laser_gate":
                self.assertGreaterEqual(item["height"] - 34, 14)

    def test_reject_missing_usage(self):
        doc = copy.deepcopy(self.doc)
        field = next(f for f in doc["levels"][0]["fieldInstances"] if f["__identifier"] == "TacticalObjects")
        values = json.loads(field["__value"])
        values[0]["solutions"] = ["随便用"]
        field["__value"] = json.dumps(values)
        with self.assertRaisesRegex(gen.base.MapError, "两种解法"):
            gen.validate_tactical(doc)

    def test_reject_low_roll_gate(self):
        doc = copy.deepcopy(self.doc)
        field = next(f for f in doc["levels"][0]["fieldInstances"] if f["__identifier"] == "TacticalObjects")
        values = json.loads(field["__value"])
        next(item for item in values if item["type"] == "laser_gate")["height"] = 30
        field["__value"] = json.dumps(values)
        with self.assertRaisesRegex(gen.base.MapError, "翻滚"):
            gen.validate_tactical(doc)

    def test_four_accessible_optional_maintenance_routes(self):
        _, layers = gen.base._level_and_layers(self.doc)
        for start, end, floor in gen.PLATFORMS:
            for x in range(start, end + 1):
                self.assertEqual(gen.base._cell(layers["Collision"], x, floor), 2)
                ground = 27 if floor == 21 else floor + 3
                self.assertEqual(gen.base._cell(layers["Collision"], x, ground), 1)
                self.assertNotEqual(gen.base._cell(layers["Traversal"], x, floor - 1), 0)
                self.assertNotEqual(gen.base._cell(layers["Traversal"], x, ground - 1), 0)

    def test_defender_migration_only_six_empty_cells_and_is_idempotent(self):
        doc = copy.deepcopy(self.doc)
        level = doc["levels"][0]
        level["fieldInstances"] = [f for f in level["fieldInstances"] if f["__identifier"] != "DefenderRevision"]
        doc["defs"]["levelFields"] = [f for f in doc["defs"]["levelFields"] if f["identifier"] != "DefenderRevision"]
        entities = next(layer for layer in level["layerInstances"] if layer["__identifier"] == "Entities")["intGridCsv"]
        for x, floor, _ in gen.EXTRA_DEFENDERS:
            entities[(floor - 1) * gen.W + x] = 0
        before = copy.deepcopy(doc)
        self.assertTrue(gen.augment_defenders(doc))
        for old, new in zip(before["levels"][0]["layerInstances"], level["layerInstances"]):
            if old["__identifier"] != "Entities":
                self.assertEqual(old, new)
            else:
                self.assertEqual(sum(a != b for a, b in zip(old["intGridCsv"], new["intGridCsv"])), 6)
        after = copy.deepcopy(doc)
        self.assertFalse(gen.augment_defenders(doc))
        self.assertEqual(after, doc)

    def test_all_battle_rooms_at_least_three_and_safe_rooms_empty(self):
        level, layers = gen.base._level_and_layers(self.doc)
        rooms = gen.base._metadata(level, "RoomMetadata")
        counts = [0] * len(rooms)
        for index, value in enumerate(layers["Entities"]):
            if value in {3, 4}:
                counts[layers["Rooms"][index] - 1] += 1
        self.assertEqual(counts, [0, 3, 3, 4, 0, 4, 4, 4, 0, 4, 4, 4, 4, 0])

    def test_real_upper_galleries_and_two_optional_lifts(self):
        level, layers = gen.base._level_and_layers(self.doc)
        tactical, _ = gen.validate_tactical(self.doc)
        lifts = [item for item in tactical if item["type"] == "freight_lift"]
        self.assertEqual(len(lifts), 2)
        for lift in lifts:
            self.assertEqual(lift["pos"][1] - lift["top_y"], 192)
            self.assertEqual(lift["width"], 96)
            self.assertEqual(lift["travel_time"], 2.8)
        for start, end in [(114, 130), (301, 321)]:
            for x in range(start, end + 1):
                self.assertEqual(gen.base._cell(layers["Collision"], x, 21), 2)
                self.assertEqual(gen.base._cell(layers["Collision"], x, 27), 1)
                self.assertEqual(gen.base._cell(layers["BackdropTiles"], x, 22), 4)
                self.assertEqual(gen.base._cell(layers["BackdropTiles"], x, 23), 4)
                self.assertNotEqual(gen.base._cell(layers["BackdropTiles"], x, 24), 4)
        self.assertEqual(gen.base._metadata(level, "MultilevelRevision"), gen.MULTILEVEL_REVISION)

    def test_multilevel_migration_idempotent_and_preserves_other_rooms(self):
        doc = copy.deepcopy(self.doc)
        level = doc["levels"][0]
        self.assertFalse(gen.upgrade_multilevel(doc))
        level["fieldInstances"] = [f for f in level["fieldInstances"] if f["__identifier"] != "MultilevelRevision"]
        doc["defs"]["levelFields"] = [f for f in doc["defs"]["levelFields"] if f["identifier"] != "MultilevelRevision"]
        field = next(f for f in level["fieldInstances"] if f["__identifier"] == "TacticalObjects")
        field["__value"] = json.dumps([i for i in json.loads(field["__value"]) if i["type"] != "freight_lift"])
        entities = next(layer for layer in level["layerInstances"] if layer["__identifier"] == "Entities")["intGridCsv"]
        for old, new in gen.UPPER_MOVES:
            entities[(new[1] - 1) * gen.W + new[0]] = 0
            entities[(old[1] - 1) * gen.W + old[0]] = old[2]
        before = copy.deepcopy(doc)
        self.assertTrue(gen.upgrade_multilevel(doc))
        for old_layer, new_layer in zip(before["levels"][0]["layerInstances"], level["layerInstances"]):
            for index, (a, b) in enumerate(zip(old_layer["intGridCsv"], new_layer["intGridCsv"])):
                if not (95 <= index % gen.W <= 134 or 287 <= index % gen.W <= 326):
                    self.assertEqual(a, b)
        self.assertFalse(gen.upgrade_multilevel(doc))


if __name__ == "__main__":
    unittest.main(verbosity=2)
