"""Generate bounded factual SDK catalogs; never import or execute the Blender addon."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import struct
import urllib.request
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = "5a886256e54db52b5d228335eae20ce796f87fc0"
SOURCE = "https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition"
CACHE = ROOT / "dist" / "sdk-reference" / REVISION
OUTPUT = ROOT / "src" / "gear" / "sdk_catalog.lua"
MAX_INPUT = 4 * 1024 * 1024
MAX_OUTPUT = 96 * 1024

# Pin the bytes as well as the revision. References remain ignored build inputs.
INPUTS = {
    "__init__.py": "b750e252d8972b9b1c1ffcd2033d870a498686ab15f2557f917f29844f74d135",
    "hashlists/archivehashes.json": "f5f8c4a7af31d4cbd1f171ccb00d10169a027c6b8b226b961b9cbabaeb5790d7",
    "hashlists/friendlynames.txt": "c897b0f2278df45f607e939a318d3948e7f5bd3e992c31050f2058ad5e7e8a46",
    "hashlists/shadervariables.txt": "d20d66fcb747ebb0bf597a7c0cd4a8caf07e8667d4ea8424fa7f7c100c447e9a",
    "hashlists/texturetypes.txt": "2710aa680dae3951d7be8d9ae1749340aecb48987a42f281cc5db7d53a21b79b",
    "stingray/material.py": "d1fb1e2d5f85d6cc69fce37d1dba86e5e6fdc72e1ff25b1b10a079b4b995ab4d",
    "materials/advanced.material": "3819c9a883719f1d655d9236ff91068f5a479f15f322180e29b6344a40a81ebb",
    "materials/alphaclip+.material": "4824dc303875629e474435fa569bc86a6f511b1aa5ce1c4c7e645572e6865398",
    "materials/alphaclip.material": "91173c8919e6ba8bae2510cc6ce75f5ae9b0533011d4ef3e03028306c4e49679",
    "materials/armorlut.material": "70bf6d93b1917e87d35870ca7ab11ffd02eb1ae164d162b3da7e02b5d943c69d",
    "materials/basic+.material": "e90f5d954869f539c9e2556280fafac3ade8a11996edb5235d41e75ab6bb7e10",
    "materials/basic.material": "80e49e4a6ba765de9c9c64f9567cc04edc6c6361cbd5eccc9301610f32b61f83",
    "materials/emissive.material": "a1f821dcca4973fdfab214baa5cf625e70c6459fd467b7b34e5a084709db33dd",
    "materials/original.material": "5d821ab7d7ba2cd4f43220a1ad7216f897930da47a9f8eb06f16a13d6922779b",
    "materials/scope.material": "ad8b54acdd7de7b088318ab072889162d6608cc1d06d055c09a9440ceacf48ae",
    "materials/translucent.material": "be3670421f4cdb0a7a5250c139cc23febcd64d3e6e2fc61c32c697a6d4e1553f",
}
GEAR = ("Armor", "Helmet", "Cape")
VARIABLES = frozenset("""
    Alpha AlphaMult AlphaMultiplier AlphaThreshold Opacity OpacityMult
    OpacityMultiplier OpacityThreshold MaterialLut ColorLut PatternData
    PatternLut PatternMasksArray PatternTiling PatternValueTint
    BloodColor BloodColor0 BloodColor1 BloodGunkNormalIntensity BloodLut
    BloodMaskBackwardHeight BloodMaskBackwardOpacity BloodMaskFadeDistance
    BloodMaskForwardHeight BloodMaskForwardOpacity BloodMaskLeftHeight
    BloodMaskLeftOpacity BloodMaskRightHeight BloodMaskRightOpacity
    BloodNormalFade BloodOverlayAmountBackward BloodOverlayAmountDown
    BloodOverlayAmountForward BloodOverlayAmountLeft BloodOverlayAmountRight
    BloodOverlayAmountUp BloodOverlayColor BloodOverlayInvScale BloodOverlayMetallic
    BloodOverlayNormalBlend BloodOverlayNormalGrayscale BloodOverlayRoughness
    BloodRoughness BloodScalarField BloodScale BloodSplatterTiler BloodSubsurface
    BloodTiler BloodWeightsNegative BloodWeightsPositive
    MudFadeDistance MudHeight MudNormalBlendAmount MudNormalsGrayscale MudOpacity
    MudOverlayColor MudOverlayHeightMask MudOverlayHeightMaskFade
    MudOverlayHeightMaskMaxOpacity MudOverlayInvScale MudWetness
    TearAmount TearAmountCape TearColor TearMap TearNormalsGrayscale TearOverlayInvScale
    DirtAmount DirtColor DirtGlobalAmount DirtIntensity DirtMetallic DirtRoughness DirtScale
    WoundData WoundDerivative WoundLutToAdd WoundNormal WoundPaintingEnabled
    WoundParallaxScale WoundTileScale
""".split())


def read_inputs(cache: Path, refresh: bool = False) -> dict[str, bytes]:
    result = {}
    for name, expected in INPUTS.items():
        path = cache / name
        if refresh:
            url = f"https://raw.githubusercontent.com/Boxofbiscuits97/HD2SDK-CommunityEdition/{REVISION}/{name}"
            request = urllib.request.Request(url, headers={"User-Agent": "Epic-LUT-catalog-build"})
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(MAX_INPUT + 1)
            if len(data) > MAX_INPUT or hashlib.sha256(data).hexdigest() != expected:
                raise ValueError(f"Pinned SDK input changed or exceeds size limit: {name}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        data = path.read_bytes()
        if len(data) > MAX_INPUT or hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Pinned SDK input changed or exceeds size limit: {name}")
        result[name] = data
    return result


def literal_templates(source: str) -> tuple:
    """Only read the literal enum; no SDK Python module is imported."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", SyntaxWarning)
        module = ast.parse(source)
    for node in module.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == "Global_Materials" for target in node.targets
        ):
            return ast.literal_eval(node.value)
    raise ValueError("SDK material template descriptions were not found")


def id_labels(source: str, wanted: frozenset | None = None) -> dict[str, str]:
    labels = {}
    for line in source.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"(\S+)\s+0x([0-9a-fA-F]{1,8})\s*", line)
        if not match:
            raise ValueError(f"Malformed SDK slot/variable label: {line[:80]}")
        name, value = match.groups()
        if wanted is not None and name not in wanted:
            continue
        key = f"{int(value, 16):08x}"
        if key in labels and labels[key] != name:
            raise ValueError(f"Conflicting SDK labels for {key}")
        labels[key] = name
    return labels


def derive(inputs: dict[str, bytes]) -> dict:
    groups = json.loads(inputs["hashlists/archivehashes.json"])
    archives, resource_names = {}, {}
    for kind in GEAR:
        for value, name in groups[kind].items():
            if not re.fullmatch(r"[0-9a-fA-F]{1,16}", value) or not isinstance(name, str):
                raise ValueError("Invalid SDK gear archive entry")
            label = [kind, name.strip()]
            key = f"{int(value, 16):016x}"
            if key in archives and archives[key] != label:
                raise ValueError(f"Ambiguous archive category for {key}")
            archives[key] = label
    # Membership is by a friendly resource entry's name, never by archive ID.
    # Explicit Helmet entries can contain several names sharing one resource.
    by_name = {kind: set(groups[kind].values()) for kind in GEAR}
    for line in inputs["hashlists/friendlynames.txt"].decode("utf-8-sig").splitlines():
        match = re.match(r"^(\d+)\s+(.+?)\s*$", line)
        if not match:
            continue
        decimal, name = match.groups()
        name = name.strip()
        kinds = [kind for kind in GEAR if name in by_name[kind] or name.startswith(kind + " ")]
        kinds = [kind for kind in kinds if not name.startswith(kind + " Icons")]
        if not kinds:
            continue
        value = int(decimal)
        if value < 0 or value >= 2**64 or len(kinds) != 1:
            raise ValueError("Invalid or ambiguous SDK friendly gear resource")
        key, label = f"{value:016x}", [kinds[0], name]
        if key in resource_names and resource_names[key] != label:
            raise ValueError(f"Conflicting SDK friendly gear resource {key}")
        resource_names[key] = label
    texture_names = id_labels(inputs["hashlists/texturetypes.txt"].decode("utf-8-sig"))
    variable_names = id_labels(inputs["hashlists/shadervariables.txt"].decode("utf-8-sig"), VARIABLES)
    if set(variable_names.values()) != VARIABLES:
        raise ValueError("One or more curated cosmetic shader variables are missing")
    templates = {}
    for filename, label, description in literal_templates(inputs["__init__.py"].decode("utf-8-sig")):
        material = inputs[f"materials/{filename}.material"]
        if len(material) < 32:
            raise ValueError("Truncated SDK material template")
        # SDK stingray/material.py Serialize: 12+4+8 then ParentMaterialID uint64.
        parent = f"{struct.unpack_from('<Q', material, 24)[0]:016x}"
        status = "unknown_ui"
        if "does not render in the UI" in description:
            status = "unsupported_ui"
        elif "renders in the UI" in description:
            status = "supports_ui"
        entry = [label, status]
        if parent in templates and templates[parent] != entry:
            raise ValueError(f"Conflicting material-template parent {parent}")
        templates[parent] = entry
    result = dict(resources=resource_names, archives=archives, textures=texture_names,
                  variables=variable_names, templates=templates)
    for name, limit in (("resources", 256), ("archives", 512), ("textures", 768), ("variables", 128), ("templates", 16)):
        if len(result[name]) > limit:
            raise ValueError(f"SDK {name} catalog exceeds its reviewed bound")
    return result


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render(data: dict) -> str:
    fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    lines = ["-- Generated by tools/generate_sdk_catalog.py. Factual IDs/labels only; no SDK runtime code.",
             f"-- Upstream revision: {REVISION}", "local C = {", f"    revision = '{REVISION}',",
             f"    source = '{SOURCE}',", f"    fingerprint = '{fingerprint}',", "}"]
    for category in ("resources", "archives", "textures", "variables", "templates"):
        lines.append(f"local {category} = {{")
        for key, value in sorted(data[category].items()):
            label = "{ " + ", ".join(lua_string(v) for v in value) + " }" if isinstance(value, list) else lua_string(value)
            lines.append(f"    ['{key}'] = {label},")
        lines.append("}")
    lines.extend([f"C.counts = {{ resources = {len(data['resources'])}, archives = {len(data['archives'])}, "
                  f"textures = {len(data['textures'])}, variables = {len(data['variables'])}, templates = {len(data['templates'])} }}", ""])
    lines.append(r"""-- Never pass a 64-bit resource ID through a Lua number: it may lose bits.
local function exact64(value)
    if type(value) ~= 'string' then return nil end
    value = value:lower():gsub('^0x', '')
    if #value == 16 and value:match('^%x+$') then return value end
end
local function exact32(value)
    if type(value) == 'number' then
        if value < 0 then value = value + 4294967296 end
        if value < 0 or value >= 4294967296 or value ~= math.floor(value) then return nil end
        return string.format('%08x', value)
    end
    if type(value) ~= 'string' then return nil end
    value = value:lower():gsub('^0x', '')
    if #value >= 1 and #value <= 8 and value:match('^%x+$') then
        return string.rep('0', 8 - #value) .. value
    end
end
function C.resource_name(value)
    local row = resources[exact64(value)]
    return row and row[2] or nil
end
function C.resource_kind(value)
    local row = resources[exact64(value)]
    return row and row[1] or nil
end
function C.archive_name(value)
    local row = archives[exact64(value)]
    return row and row[2] or nil
end
function C.archive_kind(value)
    local row = archives[exact64(value)]
    return row and row[1] or nil
end
function C.texture_name(value) return textures[exact32(value)] end
function C.variable_name(value) return variables[exact32(value)] end
function C.compatibility(parent)
    local row = templates[exact64(parent)]
    if row then return row[1], row[2] end
end
return C
""")
    output = "\n".join(lines)
    if len(output.encode()) > MAX_OUTPUT:
        raise ValueError("SDK runtime catalog exceeds its reviewed size limit")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Fetch bounded pinned inputs into ignored dist cache")
    parser.add_argument("--check", action="store_true", help="Compare generated bytes without rewriting the catalog")
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    data = derive(read_inputs(args.cache, args.refresh))
    output = render(data)
    if args.check:
        if args.output.read_text(encoding="utf-8") != output:
            raise SystemExit("SDK catalog differs; run tools/generate_sdk_catalog.py")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8", newline="\n")
    print(f"PASS SDK catalog {REVISION[:12]}: " + ", ".join(f"{name}={len(rows)}" for name, rows in data.items()))


if __name__ == "__main__":
    main()
