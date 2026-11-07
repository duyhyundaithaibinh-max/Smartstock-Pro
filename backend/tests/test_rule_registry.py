import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import db, rule_registry


class RuleRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "rules.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def test_default_active_version_is_seeded_once(self):
        active = rule_registry.get_active_version()
        self.assertEqual(active["version"], "1.0.0")
        self.assertEqual(active["status"], "active")
        self.assertEqual(rule_registry.list_versions()["total"], 1)

    def test_create_draft_is_immutable_and_has_config_hash(self):
        config = {"fibonacci": {"wing": 1}}
        created = rule_registry.create_version("1.1.0", "EMA experiment", "Draft only", config)
        self.assertEqual(created["status"], "draft")
        self.assertEqual(created["config"], config)
        self.assertEqual(len(created["config_sha256"]), 64)
        with self.assertRaisesRegex(ValueError, "already exists"):
            rule_registry.create_version("1.1.0", "Overwrite", "", {})

    def test_activation_archives_previous_active_and_keeps_history(self):
        rule_registry.create_version("1.1.0", "EMA experiment", "Draft", {"volume_flow": {"window": 12}})
        activated = rule_registry.activate_version("1.1.0")
        self.assertEqual(activated["status"], "active")
        self.assertEqual(rule_registry.get_active_version()["version"], "1.1.0")
        history = {item["version"]: item["status"] for item in rule_registry.list_versions()["items"]}
        self.assertEqual(history["1.0.0"], "archived")
        self.assertEqual(history["1.1.0"], "active")

    def test_unknown_version_cannot_be_activated(self):
        with self.assertRaises(KeyError):
            rule_registry.activate_version("9.9.9")

    def test_semver_and_metadata_validation(self):
        for version in ("latest", "1.0", "01.2.3", "1.0.0-beta"):
            with self.assertRaises(ValueError):
                rule_registry.create_version(version, "Name", "", {})
        with self.assertRaises(ValueError):
            rule_registry.create_version("2.0.0", "", "", {})
        with self.assertRaises(ValueError):
            rule_registry.create_version("2.0.0", "Name", "", ["not", "object"])

    def test_non_finite_and_oversized_config_are_rejected(self):
        with self.assertRaises(ValueError):
            rule_registry.create_version("2.0.0", "Name", "", {"x": float("nan")})
        with self.assertRaises(ValueError):
            rule_registry.create_version("2.0.0", "Name", "", {"text": "x" * 21_000})

    def test_only_supported_parameter_sections_and_ranges_are_accepted(self):
        invalid_configs = [
            {"unknown": {"value": 1}},
            {"fibonacci": {"wing": 0}},
            {"elliott": {"lookback": 9}},
            {"volume_flow": {"window": 251}},
            {"volume_flow": {"window": True}},
        ]
        for index, config in enumerate(invalid_configs):
            with self.subTest(config=config):
                with self.assertRaises(ValueError):
                    rule_registry.create_version(f"2.0.{index}", "Invalid", "", config)


if __name__ == "__main__":
    unittest.main()
