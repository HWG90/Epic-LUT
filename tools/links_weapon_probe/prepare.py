"""Prepare or explicitly run the diagnostic Link's Link to Memory weapon probe.

This copies reviewed modules verbatim; it is not a production addon dependency.
Preparing files sends no commands and does not touch the installed Epic LUT build.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PREFIX = "r6_weapon_probe_"
SOURCES = {
    "primary_identity": "src/weapons/primary_identity.lua",
    "weapon_discovery": "src/weapons/weapon_discovery.lua",
    "engine": "vendor/engine.lua",
    "bingus_memory": "vendor/bingus_memory.lua",
    "bingus_runtime": "vendor/bingus_runtime.lua",
    "lut_catalog_match": "src/weapons/lut_catalog_match.lua",
}


def digest(body):
    return hashlib.sha256(body).hexdigest()


def catalog_bytes(path):
    body = path.read_bytes()
    assert 16 <= len(body) <= 294912, "Catalog byte budget exceeded"
    lines = body.decode("ascii").splitlines()
    assert 1 <= len(lines) <= 16384, "Catalog item budget exceeded"
    assert all(re.fullmatch(r"[0-9a-fA-F]{16}", line) for line in lines), "Malformed texture ID"
    return body, len(lines)


def atomic_write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_name(path.name + ".next")
    pending.write_bytes(body)
    os.replace(pending, path)
    assert path.read_bytes() == body, f"Prepared bytes differ: {path}"


def prepare(addon, catalog):
    addon = addon.resolve()
    assert (addon / "README.md").is_file() and (addon / "tools/llm.py").is_file(), "Expected LLM kit root"
    body, count = catalog_bytes(catalog)
    files = {"r6_weapon_catalog.txt": body,
             "scripts/r6_weapon_probe.lua": (HERE / "probe.lua").read_bytes(),
             "r6_weapon_probe_LICENSE-CowboyBingus.txt": (ROOT / "vendor/LICENSE").read_bytes()}
    records = []
    for name, relative in SOURCES.items():
        source = ROOT / relative
        target = f"scripts/{PREFIX}{name}.lua"
        files[target] = source.read_bytes()
        records.append({"source": relative, "target": target, "sha256": digest(files[target])})
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    manifest = {"schema": 1, "diagnostic_only": True, "readonly": True,
                "source_root": str(ROOT), "git_head": head,
                "version": (ROOT / "VERSION").read_text().strip(),
                "catalog_items": count, "catalog_sha256": digest(body), "modules": records,
                "probe_sha256": digest(files["scripts/r6_weapon_probe.lua"])}
    files["r6_weapon_probe_manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    files["r6_weapon_probe_manifest.sha256"] = digest(files["r6_weapon_probe_manifest.json"]).encode()
    for relative, contents in files.items():
        atomic_write(addon / relative, contents)
    return {"addon_root": str(addon), "files": len(files), **manifest,
            "command": "run r6_weapon_probe", "report": str(addon / "r6_weapon_probe.tsv")}


def prepare_pilot(addon, resource, weapon, dds):
    assert re.fullmatch(r"[0-9a-fA-F]{16}", resource), "Pilot texture ID must be exact"
    assert re.fullmatch(r"[0-9a-fA-F]{16}", weapon), "Pilot weapon ID must be exact"
    assert dds.name.lower().endswith(f"-{resource.lower()}-original.dds"), "Pilot must use the cache file for its exact texture ID"
    contents = dds.read_bytes()
    assert 128 <= len(contents) <= 1048576 and contents[:4] == b"DDS ", "Pilot source DDS invalid"
    import struct
    assert struct.unpack_from("<II", contents, 12) == (8, 23), "Pilot requires 23 x 8 DDS"
    records = []
    files = {"scripts/r6_weapon_pilot.lua": (HERE / "pilot.lua").read_bytes(),
             "r6_weapon_pilot_dds.hex": contents.hex().encode(),
             "r6_weapon_pilot.cfg": f"resource={resource.lower()}\nweapon={weapon.lower()}\ndds_sha256={digest(contents)}\n".encode()}
    for name, relative in {"weapon_runtime": "src/weapons/weapon_runtime.lua",
                           "binding_session": "src/gear/binding_session.lua", "dds": "src/core/dds.lua"}.items():
        target = f"scripts/{PREFIX}{name}.lua"
        files[target] = (ROOT / relative).read_bytes()
        records.append({"source": relative, "target": target, "sha256": digest(files[target])})
    manifest = {"schema": 1, "diagnostic_only": True, "requires_explicit_execution": True,
                "weapon": weapon.lower(), "resource": resource.lower(), "original_dds_sha256": digest(contents),
                "script_sha256": digest(files["scripts/r6_weapon_pilot.lua"]), "modules": records,
                "report": str(addon / "r6_weapon_pilot.tsv"), "command": "run r6_weapon_pilot"}
    files["r6_weapon_pilot_manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    for relative, body in files.items():
        atomic_write(addon / relative, body)
    return manifest


def run(addon):
    status_path = addon / "status.txt"
    status = status_path.read_text(encoding="utf-8") if status_path.exists() else ""
    assert "running batch" not in status and "running command" not in status, "Another LLM driver is active"
    spec = importlib.util.spec_from_file_location("r6_links_driver", addon / "tools/llm.py")
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    driver.FOLDER = str(addon)
    return driver.run(["module game.dll", "module helldivers2.exe", "run r6_weapon_probe", "journal", "calls"], timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addon-root", type=Path,
                        default=Path(os.environ.get("LOCALAPPDATA", ".")) / "LinksLinkToMemory")
    parser.add_argument("--catalog", type=Path,
                        default=ROOT / "dist/review/weapons/completed-primary-probe/catalog.txt")
    parser.add_argument("--run", action="store_true", help="Explicitly send one read-only diagnostic batch after preparation")
    parser.add_argument("--pilot-resource", help="Stage an optional exact primary-body RGB apply/restore pilot; does not run it")
    parser.add_argument("--expected-weapon", help="Exact current primary configuration ID required by the optional pilot")
    parser.add_argument("--pilot-dds", type=Path, help="Exact cached original 23 x 8 DDS for the optional pilot")
    args = parser.parse_args()
    if any((args.pilot_resource, args.expected_weapon, args.pilot_dds)) and not all((args.pilot_resource, args.expected_weapon, args.pilot_dds)):
        parser.error("--pilot-resource, --expected-weapon and --pilot-dds must be provided together")
    prepared = prepare(args.addon_root, args.catalog)
    print(json.dumps({key: prepared[key] for key in
                     ("addon_root", "files", "git_head", "version", "catalog_items", "catalog_sha256", "probe_sha256", "command", "report")}, indent=2))
    if args.pilot_resource:
        pilot = prepare_pilot(args.addon_root, args.pilot_resource, args.expected_weapon, args.pilot_dds)
        print(json.dumps({key: pilot[key] for key in ("weapon", "resource", "original_dds_sha256", "script_sha256", "command", "report")}, indent=2))
    if args.run:
        print(run(args.addon_root))


if __name__ == "__main__":
    main()
