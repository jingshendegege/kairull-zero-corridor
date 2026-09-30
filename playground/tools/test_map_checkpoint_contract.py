"""唯一中途记录点只读回归：源码/生成一致、幂等迁移、全层保留、几何和清场安全。"""
import copy
import contextlib
import io
import json
import re
import tempfile
import unittest
from unittest import mock
from pathlib import Path

import gen_m01_protocol_quarantine as m01
import gen_m04_chrono_freight as m04
import gen_m05_vertical_freight as m05
import map_checkpoint_contract as contract

MODULES = [(m01, m01.LDTK_PATH, m01.OUTPUT_PATH), (m04, m04.SOURCE, m04.OUTPUT), (m05, m05.SOURCE, m05.OUTPUT)]
BACKUP = Path("C:/Users/Administrator/Documents/ChatGPT/游戏制作/work/single-crt-checkpoint-before-20260906")


def doc_at(path):
    return json.loads(path.read_text(encoding="utf-8"))


def field(doc, name):
    return next(item for item in doc["levels"][0]["fieldInstances"] if item["__identifier"] == name)


def put_checkpoints(doc, values):
    field(doc, contract.FIELD)["__value"] = json.dumps(values, ensure_ascii=False)


def layer(doc, name):
    return next(item for item in doc["levels"][0]["layerInstances"] if item["__identifier"] == name)["intGridCsv"]


def without_checkpoint_fields(doc):
    result = copy.deepcopy(doc)
    result["levels"][0]["fieldInstances"] = [item for item in result["levels"][0]["fieldInstances"]
        if item["__identifier"] not in (contract.FIELD, contract.REVISION_FIELD)]
    result["defs"]["levelFields"] = [item for item in result["defs"]["levelFields"]
        if item["identifier"] not in (contract.FIELD, contract.REVISION_FIELD)]
    return result


class SingleCheckpointContract(unittest.TestCase):
    def test_fresh_seed_already_has_checkpoint_and_never_overwrites_real_source(self):
        originals = [source.read_bytes() for _, source, _ in MODULES]
        with tempfile.TemporaryDirectory(prefix="kairull-checkpoint-seed-") as directory:
            seed_path = Path(directory) / "seed.ldtk"
            with mock.patch.object(m01, "LDTK_PATH", seed_path), contextlib.redirect_stderr(io.StringIO()):
                m01._seed_ldtk()
            self.assertEqual(len(contract.validate(doc_at(seed_path))), 1)
            m01.compile_path(seed_path)
        for module in (m04, m05):
            seeded = module.seed_document()
            self.assertEqual(len(contract.validate(seeded)), 1)
            module.compile_document(seeded, "seed-test")
        self.assertEqual(originals, [source.read_bytes() for _, source, _ in MODULES])

    def test_three_sources_each_have_one_exact_runtime_checkpoint(self):
        for module, source, output in MODULES:
            with self.subTest(map=source.stem):
                doc = doc_at(source)
                self.assertEqual(contract.validate(doc), [contract.DEFAULTS[doc["levels"][0]["identifier"]]])
                compiled = module.compile_path()
                self.assertEqual(compiled, output.read_text(encoding="utf-8"))
                match = re.search(r"const CHECKPOINTS: Array\[Dictionary\] = (.*?)\n\n", compiled, re.S)
                self.assertIsNotNone(match)
                self.assertEqual(json.loads(match.group(1)), contract.validate(doc))

    def test_source_migration_preserved_every_old_layer_and_field(self):
        if not (BACKUP / "godot/maps/m01_protocol_quarantine.ldtk").exists():
            self.skipTest("本机迁移前备份不在此环境；仍执行其余幂等与源数据合同")
        for module, source, _ in MODULES:
            with self.subTest(map=source.stem):
                previous = doc_at(BACKUP / "godot/maps" / source.name)
                current = doc_at(source)
                self.assertEqual(current["levels"][0]["layerInstances"], previous["levels"][0]["layerInstances"])
                stripped = without_checkpoint_fields(current)
                stripped["nextUid"] = previous["nextUid"]
                self.assertEqual(stripped, previous, "只允许追加两个level字段/schema和nextUid")

    def test_migration_idempotent_and_preserves_unknown_user_data(self):
        for _, source, _ in MODULES:
            with self.subTest(map=source.stem):
                doc = without_checkpoint_fields(doc_at(source))
                doc["custom_user_data"] = {"preserve": [3, "中文", {"flag": True}]}
                before = copy.deepcopy(doc)
                self.assertTrue(contract.add_single_checkpoint(doc))
                self.assertEqual(doc["levels"][0]["layerInstances"], before["levels"][0]["layerInstances"])
                self.assertEqual(doc["custom_user_data"], before["custom_user_data"])
                after = copy.deepcopy(doc)
                self.assertFalse(contract.add_single_checkpoint(doc))
                self.assertEqual(after, doc)

    def test_existing_user_checkpoint_position_is_not_overwritten(self):
        for _, source, _ in MODULES:
            with self.subTest(map=source.stem):
                doc = doc_at(source)
                doc["levels"][0]["fieldInstances"] = [f for f in doc["levels"][0]["fieldInstances"]
                    if f["__identifier"] != contract.REVISION_FIELD]
                doc["defs"]["levelFields"] = [f for f in doc["defs"]["levelFields"] if f["identifier"] != contract.REVISION_FIELD]
                values = contract.validate(doc)
                values[0]["cell"][0] -= 1
                put_checkpoints(doc, values)
                self.assertTrue(contract.add_single_checkpoint(doc))
                self.assertEqual(contract.validate(doc), values)

    def test_required_clear_enemy_counts_are_ten_twenty_two_twenty_four(self):
        for (_, source, _), expected in zip(MODULES, [10, 22, 24]):
            doc = doc_at(source)
            values = contract.validate(doc)[0]
            entities, owners = layer(doc, "Entities"), layer(doc, "Rooms")
            count = sum(kind in (3, 4) and owners[index] - 1 in values["required_clear_rooms"]
                        for index, kind in enumerate(entities))
            self.assertEqual(count, expected)
            self.assertTrue(values["required_clear_rooms"])

    def test_zero_or_two_points_rejected(self):
        for _, source, _ in MODULES:
            doc = doc_at(source)
            original = contract.validate(doc)
            for invalid in ([], original * 2):
                put_checkpoints(doc, invalid)
                with self.assertRaisesRegex(ValueError, "恰好一个"):
                    contract.validate(doc)

    def test_missing_field_unknown_revision_and_partial_migration_rejected(self):
        doc = without_checkpoint_fields(doc_at(m04.SOURCE))
        with self.assertRaisesRegex(ValueError, "CheckpointMetadata"):
            contract.validate(doc)
        migrated = doc_at(m04.SOURCE)
        field(migrated, contract.REVISION_FIELD)["__value"] = json.dumps("unknown_user_revision")
        before = copy.deepcopy(migrated)
        with self.assertRaisesRegex(ValueError, "未知"):
            contract.add_single_checkpoint(migrated)
        self.assertEqual(before, migrated)
        partial = doc_at(m04.SOURCE)
        partial["levels"][0]["fieldInstances"] = [f for f in partial["levels"][0]["fieldInstances"] if f["__identifier"] != contract.FIELD]
        with self.assertRaisesRegex(ValueError, "CheckpointMetadata"):
            contract.add_single_checkpoint(partial)

    def test_lower_tower_prerequisites_cannot_be_shortened_or_empty(self):
        for invalid in ([], [3, 4], [3, 4, 5, 6, 7], [3, 4, 5, 6, 7, 8, 8]):
            doc = doc_at(m05.SOURCE)
            values = contract.validate(doc)
            values[0]["required_clear_rooms"] = invalid
            put_checkpoints(doc, values)
            with self.assertRaisesRegex(ValueError, "required_clear_rooms|半程"):
                contract.validate(doc)

    def test_schema_only_or_wrong_uid_does_not_duplicate_definitions(self):
        doc = doc_at(m04.SOURCE)
        doc["levels"][0]["fieldInstances"] = [entry for entry in doc["levels"][0]["fieldInstances"]
            if entry["__identifier"] not in (contract.FIELD, contract.REVISION_FIELD)]
        before = copy.deepcopy(doc)
        with self.assertRaisesRegex(ValueError, "schema"):
            contract.add_single_checkpoint(doc)
        self.assertEqual(before, doc)
        doc = doc_at(m04.SOURCE)
        field(doc, contract.FIELD)["defUid"] = -100
        with self.assertRaisesRegex(ValueError, "uid"):
            contract.validate(doc)

    def test_stable_three_column_support_and_three_cell_headroom_required(self):
        for _, source, _ in MODULES:
            for dx, dy, value, phrase in ((0, 1, 0, "稳定静态地面"), (1, 1, 0, "稳定静态地面"), (0, -2, 1, "站立净空")):
                doc = doc_at(source)
                x, y = contract.validate(doc)[0]["cell"]
                width = doc["levels"][0]["pxWid"] // 32
                layer(doc, "Collision")[(y + dy) * width + x + dx] = value
                with self.assertRaisesRegex(ValueError, phrase):
                    contract.validate(doc)

    def test_entity_overlap_rejected_even_in_cleared_battle_room(self):
        doc = doc_at(m01.LDTK_PATH)
        x, y = contract.validate(doc)[0]["cell"]
        layer(doc, "Entities")[y * m01.W + x] = 4
        with self.assertRaisesRegex(ValueError, "出生包围盒重叠"):
            contract.validate(doc)

    def test_battle_room_must_require_itself_and_shaft_is_not_safe(self):
        doc = doc_at(m01.LDTK_PATH)
        values = contract.validate(doc)
        values[0].update(room_index=6, cell=[174, 27])
        put_checkpoints(doc, values)
        with self.assertRaisesRegex(ValueError, "本房全清"):
            contract.validate(doc)
        values[0].update(room_index=2, cell=[56, 25])
        put_checkpoints(doc, values)
        with self.assertRaisesRegex(ValueError, "楼梯井/货梯井"):
            contract.validate(doc)

    def test_cannot_overlap_stair_lift_or_press_envelope(self):
        for kind in ("stairs", "freight_lift", "press"):
            doc = doc_at(m04.SOURCE)
            x, y = contract.validate(doc)[0]["cell"]
            if kind == "stairs":
                stairs = json.loads(field(doc, "StairMetadata")["__value"])
                stairs.append({"bottom_cell": [x - 2, y + 1], "top_cell": [x + 2, y - 1]})
                field(doc, "StairMetadata")["__value"] = json.dumps(stairs)
            else:
                tactical = json.loads(field(doc, "TacticalObjects")["__value"])
                tactical.append({"id": "blocked-checkpoint", "type": kind,
                    "pos": [x * 32 + 16, (y + 1) * 32] if kind == "freight_lift" else [x * 32 - 16, (y - 3) * 32],
                    "top_y": (y - 5) * 32, "floor_y": (y + 1) * 32, "width": 96})
                field(doc, "TacticalObjects")["__value"] = json.dumps(tactical)
            with self.assertRaisesRegex(ValueError, "楼梯踏面|机关/货梯轨道"):
                contract.validate(doc)


if __name__ == "__main__":
    unittest.main(verbosity=2)
