"""Verify built MDL ZIPs are standalone API-2 packages with BSL byte parity."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'armor_lut_editor/'
NATIVE = 'mcm_input_9bc2033ffbb3.dll'
NATIVE_SHA = '7e9a41484881fa851184b64a7b09f568b2f42637646bc85426a89fb5fb182350'
SCRIPTS = (
    'tools/import_zip.ps1',
    'tools/original_snapshots.ps1',
    'tools/original_snapshots.cs',
    'tools/binding_provenance.ps1',
    'tools/binding_provenance_reader.cs',
    'tools/authored_preview.ps1',
    'tools/authored_preview_reader.cs',
)


def verify(mdl_path, bsl_path, mode):
    with zipfile.ZipFile(mdl_path) as mdl, zipfile.ZipFile(bsl_path) as bsl:
        names = mdl.namelist()
        assert len(names) == len(set(names)), 'MDL contains duplicate ZIP members'
        assert not any(name.startswith('data/') for name in names), 'MDL contains a BSL startup archive'
        assert 'INSTALL-MDL.md' in names and 'INSTALL-MDL-LLL.md' not in names
        assert PREFIX + 'main.lua' not in names, 'MDL includes LLL modular main.lua'
        assert not any(name.startswith(PREFIX + 'config/') for name in names), 'MDL depends on LLL CFG defaults'
        model = mdl.read(PREFIX + 'mod.lua')
        assert model == bsl.read(PREFIX + 'mod.lua'), 'MDL and BSL bundled models differ'
        source = model.decode('utf-8')
        assert not any(api in source for api in ('mod.require(', 'mod.scope.', 'mod.config.')), 'MDL requires LLL APIs'
        for callback in ('on_enable', 'on_update', 'on_disable'):
            assert re.search(r'\b' + callback + r'\s*=', source), 'MDL lacks API-2 callback: ' + callback
        animated = mode == 'animation'
        assert "m.preview_animation='" + ('authored_salute' if animated else 'disabled') + "'" in source
        assert 'local PREVIEW_ANIMATION_ENABLED=' + ('true' if animated else 'false') in source
        manifest = json.loads(mdl.read(PREFIX + 'manifest.json'))
        assert 'lll' not in manifest, 'MDL manifest requires LLL modular lifecycle'
        assert manifest == json.loads(bsl.read(PREFIX + 'manifest.json')), 'MDL/BSL metadata differs'
        assert ('Preview Animation Test' in manifest['name']) == animated
        for credit in ('CowboyBingus', 'Scarpheon', 'Plain Furniture'):
            assert credit in manifest['credits'], 'MDL lost credit: ' + credit
        assert mdl.read(PREFIX + 'library.txt').decode('utf-8').strip() == NATIVE
        native = mdl.read(PREFIX + NATIVE)
        assert hashlib.sha256(native).hexdigest() == NATIVE_SHA, 'MDL native input companion differs'
        assert native == bsl.read(PREFIX + NATIVE)
        assert mdl.read(PREFIX + 'LICENSE-CowboyBingus.txt') == (ROOT / 'vendor/LICENSE').read_bytes()
        for name in SCRIPTS:
            assert mdl.read(name) == bsl.read(name) == (ROOT / name).read_bytes(), 'MDL script differs: ' + name
        instructions = mdl.read('INSTALL-MDL.md').decode('utf-8')
        assert 'MDL installation' in instructions and 'API-2' in instructions and 'mod.lua' in instructions
        assert 'cannot be used as an MDL package' in instructions, 'MDL instructions blur modular compatibility'
    print(f'PASS MDL {mode}: standalone API-2 layout, reviewed companions, preview gate and BSL model parity')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mdl', type=Path)
    parser.add_argument('--bsl', type=Path)
    parser.add_argument('--mode', choices=('static', 'animation'), default='static')
    args = parser.parse_args()
    if bool(args.mdl) != bool(args.bsl):
        parser.error('--mdl and --bsl must be supplied together')
    if args.mdl:
        verify(args.mdl, args.bsl, args.mode)
    else:
        for mode in ('static', 'animation'):
            stem = 'Epic-LUT-Dev-' + mode.title()
            verify(ROOT / 'dist' / (stem + '-MDL.zip'), ROOT / 'dist' / (stem + '-BSL.zip'), mode)


if __name__ == '__main__':
    main()
