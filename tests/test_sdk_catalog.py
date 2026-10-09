"""Offline generator fixtures; no SDK checkout, game assets or network needed."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import generate_sdk_catalog as G


def fixture():
    enums = (
        ("basic+", "Basic+", "A material which renders in the UI"),
        ("alphaclip", "Alpha Clip", "A material which does not render in the UI"),
        ("armorlut", "Armor LUT", "Undocumented UI behavior"),
    )
    groups = {
        "Armor": {"ffffffffffffffff": "Exact Armor"},
        "Helmet": {"1234": "Exact Helmet"},
        "Cape": {"fedcba9876543210": "Exact Cape"},
        "Support Weapon": {"0123456789abcdef": "Do not include this weapon"},
    }
    files = {
        "hashlists/archivehashes.json": json.dumps(groups).encode(),
        "hashlists/friendlynames.txt": (
            "18446744073709551614 Exact Armor\n"
            "15418518113916889238 Helmet Exact Helmet\n"
            "9007199254740993 Exact Cape\n"
            "1 Cape Icons Set 1\n2 Weapon\n3 Some unknown resource\n"
        ).encode(),
        "hashlists/texturetypes.txt": b"MaterialLut 0x7e662968\nPatternLut 0x81d4c49d\n",
        "hashlists/shadervariables.txt": "\n".join(
            f"{name} 0x{n:08x}" for n, name in enumerate(sorted(G.VARIABLES), 1)
        ).encode() + b"\nUnrelatedBone1 0xdeadbeef\nUnrelatedBone2 0xdeadbeef\n",
        "__init__.py": (f"Global_Materials = {enums!r}\nraise RuntimeError('Never execute addon code')\n").encode(),
    }
    for n, (name, _, _) in enumerate(enums, 1):
        data = bytearray(32)
        struct.pack_into("<Q", data, 24, 2**64 - n)
        files[f"materials/{name}.material"] = bytes(data)
    return files


class SDKGeneratorTests(unittest.TestCase):
    def test_exact_ids_and_separate_namespaces(self):
        data = G.derive(fixture())
        self.assertEqual(data["resources"]["fffffffffffffffe"], ["Armor", "Exact Armor"])
        self.assertEqual(data["resources"]["d5f99488a6f12896"], ["Helmet", "Helmet Exact Helmet"])
        self.assertEqual(data["resources"]["0020000000000001"], ["Cape", "Exact Cape"])
        self.assertNotIn("ffffffffffffffff", data["resources"])
        self.assertEqual(data["archives"]["0000000000001234"], ["Helmet", "Exact Helmet"])
        self.assertNotIn("0123456789abcdef", data["archives"])
        self.assertNotIn("deadbeef", data["variables"])
        self.assertEqual(data["templates"]["fffffffffffffffe"], ["Alpha Clip", "unsupported_ui"])
        self.assertEqual(data["templates"]["ffffffffffffffff"], ["Basic+", "supports_ui"])
        self.assertEqual(data["templates"]["fffffffffffffffd"], ["Armor LUT", "unknown_ui"])

    def test_deterministic_generation_and_namespace_preservation(self):
        files = fixture()
        data = G.derive(files)
        first = G.render(data)
        reordered = {name: dict(reversed(list(rows.items()))) for name, rows in reversed(list(data.items()))}
        self.assertEqual(first, G.render(reordered))
        self.assertIn("['fffffffffffffffe']", first)
        self.assertNotIn("Never execute addon code", first)
        self.assertLess(len(first.encode()), G.MAX_OUTPUT)

    def test_conflicting_curated_variables_fail(self):
        files = fixture()
        files["hashlists/shadervariables.txt"] += b"\nBloodWeightsPositive 0x00000001\n"
        with self.assertRaisesRegex(ValueError, "Conflicting SDK labels"):
            G.derive(files)

    def test_missing_variable_and_truncated_template_fail(self):
        files = fixture()
        files["hashlists/shadervariables.txt"] = b"BloodWeightsPositive 0x00000001\n"
        with self.assertRaisesRegex(ValueError, "cosmetic shader variables are missing"):
            G.derive(files)
        files = fixture()
        files["materials/basic+.material"] = b"truncated"
        with self.assertRaisesRegex(ValueError, "Truncated SDK material"):
            G.derive(files)

    def test_pinned_bytes_fail_closed(self):
        with tempfile.TemporaryDirectory(prefix="EpicLUT-SDK-fixture-") as temp:
            root = Path(temp)
            file = root / "catalog.txt"
            file.write_bytes(b"reviewed")
            expected = hashlib.sha256(file.read_bytes()).hexdigest()
            with patch.object(G, "INPUTS", {"catalog.txt": expected}):
                self.assertEqual(G.read_inputs(root), {"catalog.txt": b"reviewed"})
                file.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "Pinned SDK input changed"):
                    G.read_inputs(root)


if __name__ == "__main__":
    unittest.main()
