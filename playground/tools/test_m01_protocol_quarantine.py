#!/usr/bin/env python3
"""协议检疫站 LDtk 编译合同的只读回归测试。"""

from __future__ import annotations

import hashlib
import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_m01_protocol_quarantine as gen


def load_doc() -> dict:
    return json.loads(gen.LDTK_PATH.read_text(encoding="utf-8"))


def layer(doc: dict, name: str) -> dict:
    return next(item for item in doc["levels"][0]["layerInstances"]
                if item["__identifier"] == name)


class ProtocolQuarantineContractTest(unittest.TestCase):
    def test_bat_cargo_layout_is_a_same_floor_teaching_lane(self) -> None:
        doc = load_doc()
        collision = layer(doc, "Collision")["intGridCsv"]
        entities = layer(doc, "Entities")["intGridCsv"]
        self.assertEqual([i % gen.W for i, value in enumerate(entities)
                          if value == 5 and i % gen.W < 63], [28, 40])
        for cargo_x, enemy_x, enemy_kind in ((28, 36, 4), (40, 47, 3)):
            self.assertEqual(entities[27 * gen.W + enemy_x], enemy_kind)
            for x in range(cargo_x, enemy_x + 1):
                self.assertEqual(collision[28 * gen.W + x], 1)
                self.assertEqual(collision[27 * gen.W + x], 0)
                self.assertEqual(collision[26 * gen.W + x], 0)
        self.assertEqual(gen.ENTITY_TO_CHAR[5], "C")
        self.assertIn('"kind": "BatCargo"', gen.compile_path())

    def test_ground_lane_and_optional_maintenance_walkway_are_both_valid(self) -> None:
        doc = load_doc()
        collision = layer(doc, "Collision")["intGridCsv"]
        traversal = layer(doc, "Traversal")["intGridCsv"]
        for x in range(41, 48):
            self.assertEqual(collision[25 * gen.W + x], 2)
            self.assertNotEqual(traversal[24 * gen.W + x], 0)
            self.assertNotEqual(traversal[27 * gen.W + x], 0)
        gen._validate_and_compile(doc, "test")

    def test_rework_is_idempotent_and_preserves_other_rooms_and_unknown_fields(self) -> None:
        doc = load_doc()
        doc["levels"][0]["fieldInstances"] = [
            field for field in doc["levels"][0]["fieldInstances"]
            if field["__identifier"] != "CombatSliceRevision"
        ]
        doc["defs"]["levelFields"] = [
            field for field in doc["defs"]["levelFields"]
            if field["identifier"] != "CombatSliceRevision"
        ]
        doc["user_note_preserve"] = {"future": [1, 2, 3]}
        before = copy.deepcopy(doc)
        self.assertTrue(gen._apply_combat_slice_rework(doc))
        self.assertEqual(doc["user_note_preserve"], before["user_note_preserve"])
        for name in gen.LAYER_SPECS:
            original = layer(before, name)["intGridCsv"]
            revised = layer(doc, name)["intGridCsv"]
            for index in range(gen.W * gen.H):
                x, y = index % gen.W, index // gen.W
                if not (15 <= x <= 50 and 12 <= y <= 27):
                    self.assertEqual(original[index], revised[index], f"{name}: c{x} r{y}")
        # 用户在迁移后移动灯具，再次执行迁移不允许把这项编辑撤销。
        layer(doc, "Lights")["intGridCsv"][23 * gen.W + 22] = 2
        after_user_edit = copy.deepcopy(doc)
        self.assertFalse(gen._apply_combat_slice_rework(doc))
        self.assertEqual(after_user_edit, doc)

    def test_missing_bat_cargo_is_rejected(self) -> None:
        doc = load_doc()
        values = layer(doc, "Entities")["intGridCsv"]
        values[:] = [0 if value == 5 else value for value in values]
        with self.assertRaisesRegex(gen.MapError, "BatCargo"):
            gen._validate_and_compile(doc, "test")

    def test_extended_run_keeps_old_metadata_but_one_runtime_checkpoint(self) -> None:
        doc = load_doc()
        entities = layer(doc, "Entities")["intGridCsv"]
        rooms = gen._metadata(doc["levels"][0], "RoomMetadata")
        stairs = gen._metadata(doc["levels"][0], "StairMetadata")
        self.assertEqual(gen.W, 280)
        self.assertEqual(len(rooms), 10)
        self.assertEqual(entities.count(3) + entities.count(4), 20)
        self.assertEqual(entities.count(5), 11)
        self.assertEqual([room["checkpoint_cell"] for room in rooms if "checkpoint_cell" in room],
                         [[111, 22], [215, 22]])
        checkpoints = gen.checkpoint_contract.validate(doc, gen.MapError)
        self.assertEqual(checkpoints, [{"id": "m01_coolant_mid", "room_index": 5,
                         "cell": [154, 27], "required_clear_rooms": [1, 3, 5]}])
        self.assertEqual(len(stairs), 3)
        self.assertEqual(stairs[1]["direction"], "left_up")
        self.assertEqual(entities[22 * gen.W + 274], 2)

    def test_extension_preserves_approved_first_63_columns_from_old_116_stride(self) -> None:
        doc = load_doc()
        level = doc["levels"][0]
        level["fieldInstances"] = [f for f in level["fieldInstances"]
                                   if f["__identifier"] != "CampaignRevision"]
        doc["defs"]["levelFields"] = [f for f in doc["defs"]["levelFields"]
                                       if f["identifier"] != "CampaignRevision"]
        for field in level["fieldInstances"]:
            if field["__identifier"] == "StairMetadata":
                field["__value"] = json.dumps(json.loads(field["__value"])[:1])
        for item in level["layerInstances"]:
            original = item["intGridCsv"]
            item["intGridCsv"] = [original[y * gen.W + x] for y in range(gen.H) for x in range(116)]
            item["__cWid"] = 116
        level["pxWid"] = 116 * gen.TS
        doc["unknown_user_field"] = {"preserved": ["yes", 7]}
        before = copy.deepcopy(doc)
        self.assertTrue(gen._apply_campaign_extension(doc))
        self.assertEqual(doc["unknown_user_field"], before["unknown_user_field"])
        for name in gen.LAYER_SPECS:
            original = layer(before, name)["intGridCsv"]
            revised = layer(doc, name)["intGridCsv"]
            for y in range(gen.H):
                self.assertEqual(original[y * 116:y * 116 + 63], revised[y * gen.W:y * gen.W + 63],
                                 f"preserve {name} row{y}")
        gen._validate_and_compile(doc, "test")
        layer(doc, "Lights")["intGridCsv"][20 * gen.W + 250] = 2
        edited = copy.deepcopy(doc)
        self.assertFalse(gen._apply_campaign_extension(doc))
        self.assertEqual(doc, edited)

    def test_left_up_stair_interface_is_outside_tread_not_on_it(self) -> None:
        doc = load_doc()
        values = layer(doc, "Collision")["intGridCsv"]
        self.assertEqual(values[23 * gen.W + 123], 2)
        self.assertEqual(values[23 * gen.W + 124], 0)
        values[23 * gen.W + 123] = 0
        values[23 * gen.W + 124] = 2
        with self.assertRaisesRegex(gen.MapError, "楼梯.*缺少上端 OneWay"):
            gen._validate_and_compile(doc, "test")

    def test_checkpoint_cannot_contain_an_enemy(self) -> None:
        doc = load_doc()
        layer(doc, "Entities")["intGridCsv"][22 * gen.W + 110] = 3
        with self.assertRaisesRegex(gen.MapError, "检查点房间.*不允许布置敌人"):
            gen._validate_and_compile(doc, "test")

    def test_core_cargo_fix_is_idempotent_and_only_moves_two_entity_cells(self) -> None:
        doc = load_doc()
        level = doc["levels"][0]
        level["fieldInstances"] = [field for field in level["fieldInstances"]
                                   if field["__identifier"] != "CoreCargoRevision"]
        doc["defs"]["levelFields"] = [field for field in doc["defs"]["levelFields"]
                                      if field["identifier"] != "CoreCargoRevision"]
        values = layer(doc, "Entities")["intGridCsv"]
        values[22 * gen.W + 226], values[22 * gen.W + 228] = 5, 0
        before = copy.deepcopy(doc)
        self.assertTrue(gen._apply_core_cargo_spacing_fix(doc))
        for name in gen.LAYER_SPECS:
            differences = [index for index, (a, b) in enumerate(zip(
                layer(before, name)["intGridCsv"], layer(doc, name)["intGridCsv"])) if a != b]
            self.assertEqual(differences, [22 * gen.W + 226, 22 * gen.W + 228]
                             if name == "Entities" else [])
        fixed = copy.deepcopy(doc)
        self.assertFalse(gen._apply_core_cargo_spacing_fix(doc))
        self.assertEqual(doc, fixed)

    def test_cargo_enemy_spawn_overlap_is_rejected(self) -> None:
        doc = load_doc()
        values = layer(doc, "Entities")["intGridCsv"]
        values[22 * gen.W + 226], values[22 * gen.W + 228] = 5, 0
        with self.assertRaisesRegex(gen.MapError, "货箱与敌人出生包围盒重叠"):
            gen._validate_and_compile(doc, "test")

    def test_compile_is_deterministic_and_embeds_source_hash(self) -> None:
        raw = gen.LDTK_PATH.read_bytes()
        expected_hash = hashlib.sha256(raw).hexdigest()
        first = gen.compile_path()
        second = gen.compile_path()
        self.assertEqual(first, second)
        self.assertIn(expected_hash, first)

    def test_unknown_intgrid_value_is_rejected(self) -> None:
        doc = load_doc()
        layer(doc, "Architecture")["intGridCsv"][0] = 99
        with self.assertRaisesRegex(gen.MapError, "Architecture 未知值"):
            gen._validate_and_compile(doc, "test")

    def test_missing_semantic_layer_is_rejected(self) -> None:
        doc = load_doc()
        doc["levels"][0]["layerInstances"] = [
            item for item in doc["levels"][0]["layerInstances"]
            if item["__identifier"] != "Lights"
        ]
        with self.assertRaisesRegex(gen.MapError, "语义层不一致"):
            gen._validate_and_compile(doc, "test")

    def test_duplicate_player_spawn_is_rejected(self) -> None:
        doc = load_doc()
        values = layer(doc, "Entities")["intGridCsv"]
        values[27 * gen.W + 5] = 1
        with self.assertRaisesRegex(gen.MapError, "PlayerSpawn/Exit 必须各唯一"):
            gen._validate_and_compile(doc, "test")

    def test_airborne_entity_is_rejected(self) -> None:
        doc = load_doc()
        values = layer(doc, "Entities")["intGridCsv"]
        old = 70 + 22 * gen.W
        values[old] = 0
        values[70 + 17 * gen.W] = 4
        with self.assertRaisesRegex(gen.MapError, "实体脚下不是立即地面"):
            gen._validate_and_compile(doc, "test")

    def test_room_rect_and_intgrid_must_match(self) -> None:
        doc = load_doc()
        values = layer(doc, "Rooms")["intGridCsv"]
        values[27 * gen.W + 4] = 0
        with self.assertRaisesRegex(gen.MapError, "Rooms IntGrid"):
            gen._validate_and_compile(doc, "test")

    def test_stair_rejects_enemy_spawn(self) -> None:
        doc = load_doc()
        values = layer(doc, "Entities")["intGridCsv"]
        # 先移除原枪手，再把它放到楼梯下方地面与高度场重叠处。
        values[70 + 22 * gen.W] = 0
        values[52 + 27 * gen.W] = 4
        with self.assertRaisesRegex(gen.MapError, "楼梯.*禁止实体刷点"):
            gen._validate_and_compile(doc, "test")

    def test_open_stair_semantic_cell_shift_is_rejected(self) -> None:
        doc = load_doc()
        values = layer(doc, "Architecture")["intGridCsv"]
        # 把第一级从 c52/r27 错开到 c51/r27；数量没变也必须失败。
        values[52 + 27 * gen.W] = 0
        values[51 + 27 * gen.W] = 6
        with self.assertRaisesRegex(gen.MapError, "Architecture.OpenStair"):
            gen._validate_and_compile(doc, "test")


if __name__ == "__main__":
    unittest.main(verbosity=2)
