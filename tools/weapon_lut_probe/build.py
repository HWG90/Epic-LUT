"""Build the isolated read-only R6 primary probe; deployment is separate."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "tools" / "weapon_lut_probe"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--catalog", type=Path, help="Private current-build original texture ID catalog")
args = parser.parse_args()
manifest = json.loads((PROBE / "manifest.json").read_text(encoding="utf-8"))
destination = ROOT / "dist" / "review" / "weapons" / "primary-readonly" / manifest["id"]
files = {"main.lua": (PROBE / "main.lua").read_bytes(), "manifest.json": (PROBE / "manifest.json").read_bytes()}
if args.catalog:
    catalog = args.catalog.read_bytes()
    assert 0 < len(catalog) <= 294912, "Original texture catalog exceeds the probe budget"
    files["catalog.txt"] = catalog
for name in manifest["lll"]["modules"]:
    path = Path(name)
    assert not path.is_absolute() and ".." not in path.parts and name not in files
    files[name] = (ROOT / path).read_bytes()
files["LICENSE-CowboyBingus.txt"] = (ROOT / "vendor" / "LICENSE").read_bytes()
inventory = {name: hashlib.sha256(body).hexdigest() for name, body in sorted(files.items())}
files["FILES-SHA256.txt"] = "".join(f"{digest}  {name}\n" for name, digest in inventory.items()).encode("utf-8")
for name, body in files.items():
    path = destination / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
assert all((destination / name).read_bytes() == body for name, body in files.items())
print(json.dumps({"candidate": str(destination), "id": manifest["id"], "files": len(files), "sha256": inventory}, indent=2))
