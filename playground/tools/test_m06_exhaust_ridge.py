#!/usr/bin/env python3
"""04 排风脊线（M06）LDtk/编译合同只读测试（Codex 编写，Claude 移至 playground/tools）。"""
import collections
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_m06_exhaust_ridge as gen


class ExhaustRidgeContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads(gen.SOURCE.read_text(encoding="utf-8"))
        cls.level, cls.layers = gen.base._level_and_layers(cls.doc)

    def test_generator_check_sync(self):
        result = subprocess.run(
            [sys.executable, "-B", str(Path(gen.__file__)), "--check"],
            capture_output=True, text=True, encoding="utf-8",
            env={**os.environ, "PYTHONIOENCODING": "utf-8"},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(gen.compile_path(), gen.OUTPUT.read_text(encoding="utf-8"))

    def test_dimensions_rooms_entities(self):
        self.assertEqual((self.level["pxWid"], self.level["pxHei"]), (330 * 32, 37 * 32))
        rooms = gen.base._metadata(self.level, "RoomMetadata")
        gen.validate_rooms(self.layers["Rooms"], rooms)
        self.assertEqual(len(rooms), 11)
        counts = collections.Counter(self.layers["Entities"])
        self.assertEqual((counts[3], counts[4]), (14, 12))
        self.assertEqual((counts[1], counts[2], counts[5], counts[6]), (1, 1, 4, 1))
        self.assertEqual(self.layers["Entities"][34 * 330 + 311], 6)
        self.assertEqual(self.layers["Rooms"][34 * 330 + 311], 10)
        self.assertEqual(rooms[9]["room_id"], "pump_arena")

    def test_tactical_counts_and_each_new_object(self):
        before = copy.deepcopy(self.doc)
        items = gen.validate_tactics(self.doc)
        self.assertEqual(collections.Counter(item["type"] for item in items), {
            "updraft_fan": 8, "glass_panel": 4, "dash_node": 6,
            "auto_sniper": 1, "laser_gate": 2, "press": 3, "smoke_pickup": 3,
        })
        for item in items:
            if item["type"] in gen.NEW_KINDS:
                with self.subTest(object_id=item["id"]):
                    self.assertIn(item, gen.validate_tactics(self.doc))
                    self.assertTrue(item["purpose"])
                    self.assertGreaterEqual(len(item["solutions"]), 2)
        self.assertEqual(self.doc, before)

    def test_linear_boundaries_and_checkpoint(self):
        self.assertEqual(gen.base._metadata(self.level, "EncounterPolicy"), "linear_flow")
        self.assertEqual(gen.base._metadata(self.level, "EncounterBoundaries"), [4, 6])
        self.assertEqual(gen.base.checkpoint_contract.validate(self.doc, gen.base.MapError), [{
            "id": "m06_relay_mid", "room_index": 4, "cell": [150, 34],
            "required_clear_rooms": [1, 2, 3],
        }])


if __name__ == "__main__":
    unittest.main(verbosity=2)
