"""Focused file staging tests; uses a temporary addon root, never the live driver."""
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("probe_prepare", HERE / "prepare.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class PrepareTests(unittest.TestCase):
    def test_verbatim_modules_and_no_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            addon = Path(temporary)
            (addon / "tools").mkdir()
            (addon / "README.md").write_text("Fixture")
            (addon / "tools/llm.py").write_text("Fixture")
            catalog = addon / "fixture-catalog.txt"
            catalog.write_bytes(b"0000000000000001\n0000000000000002\n")
            result = probe.prepare(addon, catalog)
            self.assertTrue(result["diagnostic_only"])
            self.assertEqual(result["catalog_items"], 2)
            self.assertFalse((addon / "commands.txt").exists())
            manifest = json.loads((addon / "r6_weapon_probe_manifest.json").read_text())
            self.assertEqual(len(manifest["modules"]), 6)
            for item in manifest["modules"]:
                self.assertEqual((addon / item["target"]).read_bytes(), (probe.ROOT / item["source"]).read_bytes())

    def test_bad_catalog_refused_before_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            addon = Path(temporary)
            (addon / "tools").mkdir()
            (addon / "README.md").write_text("Fixture")
            (addon / "tools/llm.py").write_text("Fixture")
            catalog = addon / "fixture-catalog.txt"
            catalog.write_bytes(b"invalid texture identity\n")
            with self.assertRaises(AssertionError):
                probe.prepare(addon, catalog)
            self.assertFalse((addon / "scripts").exists())

    def test_optional_pilot_stages_exact_production_modules_without_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            addon = Path(temporary)
            resource, weapon = "babd338977faa2ff", "5fecab819f96a3e8"
            dds = addon / f"game-{resource}-original.dds"
            body = bytearray(128)
            body[:4] = b"DDS "
            struct.pack_into("<II", body, 12, 8, 23)
            dds.write_bytes(body)
            manifest = probe.prepare_pilot(addon, resource, weapon, dds)
            self.assertEqual(manifest["command"], "run r6_weapon_pilot")
            self.assertFalse((addon / "commands.txt").exists())
            for item in manifest["modules"]:
                self.assertEqual((addon / item["target"]).read_bytes(), (probe.ROOT / item["source"]).read_bytes())
            self.assertEqual((addon / "r6_weapon_pilot_dds.hex").read_text(), bytes(body).hex())


if __name__ == "__main__":
    unittest.main()
