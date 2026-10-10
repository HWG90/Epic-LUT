"""Build matching preview variants and update the existing integrated LLL profile.

Dry run by default. This helper never reloads a loader or starts/stops the game.
"""
from __future__ import annotations

import argparse
import ast
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.runtime_guard import blocked_path, require_physical_runtime

NATIVE = 'mcm_input_9bc2033ffbb3.dll'
NATIVE_SHA = '7e9a41484881fa851184b64a7b09f568b2f42637646bc85426a89fb5fb182350'
RUNTIME = 'armor_lut_editor/'
# The loader watches Lua. Publish matching metadata before its watched file.
PAIR_FILES = ('manifest.json', 'mod.lua')
COMPANIONS = (NATIVE, 'library.txt', 'LICENSE-CowboyBingus.txt', 'runtime-manifest.json')
PATCH = 'data/9ba626afa44a3aa3.patch_0'
HELPERS = {'debug_lut_dds_hex': 'assets/debug-lut.dds',
           'original_snapshot_script': 'tools/original_snapshots.ps1',
           'original_snapshot_reader': 'tools/original_snapshots.cs',
           'authored_preview_script': 'tools/authored_preview.ps1',
           'authored_preview_reader': 'tools/authored_preview_reader.cs',
           'zip_import_script': 'tools/import_zip.ps1'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def atomic_write(path, data, expected=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name+'.', suffix='.pending', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if expected is not None:
            require(path.is_file() and sha(path.read_bytes()) == expected, 'File changed before atomic replacement: '+str(path))
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def write_json(path, value):
    atomic_write(path, (json.dumps(value, indent=2)+'\n').encode())


def normalize_lua(data, entry='mod.lua'):
    text = data.decode('utf-8').replace('\r\n', '\n')
    patterns = [r'^m\.preview_animation=.*$', r'^m\.description=.*$', r'^m\.build_label=.*$']
    patterns += [r'^mod\.scope\.PREVIEW_ANIMATION_ENABLED=(?:true|false)$'] if entry == 'main.lua' else [r'\A-- Epic LUT [^\n]*', r'^local PREVIEW_ANIMATION_ENABLED=(?:true|false)$']
    for pattern in patterns:
        text, count = re.subn(pattern, '<build mode>', text, flags=re.MULTILINE)
        require(count == 1, 'Missing or duplicated build metadata: '+pattern)
    return text.encode()


def lua_value(text, field, optional=False):
    values = re.findall(r'^m\.'+re.escape(field)+r'=(.*)$', text, re.M)
    require(len(values) == 1 or (optional and not values), 'Archive metadata is missing or duplicated: '+field)
    if not values:
        return None
    value = ast.literal_eval(values[0])
    require(isinstance(value, str), 'Archive metadata must be text: '+field)
    return value


def relative_name(name):
    require(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9._/-]+', name) is not None
            and not name.startswith('/') and all(part not in ('', '.', '..') for part in name.split('/')),
            'Invalid runtime inventory path: '+str(name))
    return name


def checksum_inventory(data):
    result = {}
    for line in data.decode('utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        require(match is not None, 'Invalid modular checksum record')
        name = relative_name(match[2])
        require(name not in result and name != 'FILES-SHA256.txt', 'Duplicated/self-referential modular checksum')
        result[name] = match[1]
    require('main.lua' in result and 'manifest.json' in result, 'Modular entry/manifest checksums required')
    return result


def read_package(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)) and archive.testzip() is None, 'Invalid ZIP: '+str(path))
        files = {name: archive.read(name) for name in names}
    entry = 'main.lua' if RUNTIME+'main.lua' in files else 'mod.lua'
    require(not (RUNTIME+'main.lua' in files and RUNTIME+'mod.lua' in files), 'Archive contains duplicate entrypoints')
    lua = files[RUNTIME+entry]
    text = lua.decode('utf-8').replace('\r\n', '\n')
    manifest = json.loads(files[RUNTIME+'manifest.json'])
    animation = lua_value(text, 'preview_animation')
    require(animation in ('disabled', 'garment_poses', 'authored_salute'), 'Archive animation mode is invalid')
    mode = 'static' if animation == 'disabled' else 'animation'
    build_id = lua_value(text, 'dev_build_id', True) or None
    require(build_id is None or re.fullmatch(r'[A-Za-z0-9._-]{1,64}', build_id), 'Archive development build ID is invalid')
    version = lua_value(text, 'version')
    gate_pattern = r'^mod\.scope\.PREVIEW_ANIMATION_ENABLED=(true|false)$' if entry == 'main.lua' else r'^local PREVIEW_ANIMATION_ENABLED=(true|false)$'
    gate = re.findall(gate_pattern, text, re.M)
    require(manifest.get('version') == version, 'Archive version differs from Lua')
    require(gate == ['true' if mode == 'animation' else 'false'], 'Archive animation gate differs from metadata')
    require(manifest.get('author') == 'Goose', 'Unexpected runtime author')
    require(('Preview Animation Test' in manifest.get('name', '')) == (mode == 'animation'), 'Manifest mode differs from Lua')
    require(sha(files[RUNTIME+NATIVE]) == NATIVE_SHA, 'Archive native DLL differs from reviewed runtime')
    if entry == 'main.lua':
        require(manifest.get('id') == 'armor_lut_editor' and manifest.get('lll', {}).get('entry') == entry, 'Modular manifest entry differs')
        runtime = {name[len(RUNTIME):]: data for name, data in files.items() if name.startswith(RUNTIME)}
        inventory = checksum_inventory(runtime['FILES-SHA256.txt'])
        require(set(inventory) == set(runtime)-{'FILES-SHA256.txt'}, 'Modular checksum inventory differs from ZIP')
        require(all(sha(runtime[name]) == digest for name, digest in inventory.items()), 'Modular checksum differs from ZIP bytes')
        require(all(relative_name(name) in runtime for name in manifest['lll']['modules']), 'Modular declaration is missing from ZIP')
    startup = None
    if PATCH in files:
        from tools.lua_archive import hash_name, read
        entries = read(files[PATCH])
        resource_entry = hash_name('mods/goose/epic_lut/startup')
        require(list(entries) == [resource_entry], 'Unexpected BSL resources')
        body = entries[resource_entry][1]
        length, envelope = struct.unpack_from('<II', body)
        require(envelope == 2 and length == len(body)-8, 'Invalid BSL startup envelope')
        startup = body[8:].decode('utf-8').replace('\r\n', '\n')
        require(startup.count(text) == 1, 'BSL startup does not contain its exact loose Lua model')
        manager = json.loads(files['manifest.json'])
        require(manager.get('Name') == manifest['name'] and manager.get('Author') == 'Goose', 'BSL manifest differs from runtime')
    return {'path': str(path.resolve()), 'sha256': sha(path.read_bytes()), 'files': files,
            'lua': lua, 'manifest': manifest, 'version': version, 'mode': mode,
            'entry': entry, 'format': 'modular' if entry == 'main.lua' else 'legacy',
            'development_build_id': build_id, 'startup': startup}


def metadata_parity(a, b, excluded):
    left, right = json.loads(a), json.loads(b)
    for field in excluded:
        left.pop(field, None)
        right.pop(field, None)
    require(left == right, 'Unrelated manifest fields differ between variants')


def validate_pair(paths):
    packages = {key: read_package(path) for key, path in paths.items()}
    require(set(packages) == {(mode, loader) for mode in ('static', 'animation') for loader in ('bsl', 'lll')}, 'Four paired archives required')
    version = packages['static', 'lll']['version']
    build_id = packages['static', 'lll']['development_build_id']
    require(all(package['development_build_id'] == build_id for package in packages.values()), 'Paired development build IDs differ')
    for (mode, loader), package in packages.items():
        require(package['mode'] == mode and package['version'] == version, 'Paired archive metadata differs')
        require((package['startup'] is not None) == (loader == 'bsl'), 'Archive loader differs from pair identity')
    for mode in ('static', 'animation'):
        a, b = packages[mode, 'bsl'], packages[mode, 'lll']
        if b['format'] == 'legacy':
            require(a['lua'] == b['lua'], 'BSL/LLL Lua bytes differ')
            for name in set(a['files']) & set(b['files']):
                require(a['files'][name] == b['files'][name], 'BSL/LLL shared payload differs: '+name)
        else:
            for name in (NATIVE, 'library.txt'):
                require(a['files'][RUNTIME+name] == b['files'][RUNTIME+name], 'BSL/modular runtime payload differs: '+name)
            for field, name in HELPERS.items():
                payload = lua_value(a['lua'].decode().replace('\r\n', '\n'), field)
                require(re.fullmatch(r'[0-9a-f]+', payload) and bytes.fromhex(payload) == b['files'][RUNTIME+name], 'BSL/modular helper payload differs: '+name)
    shared = normalize_lua(packages['static', 'bsl']['lua'])
    for loader in ('bsl', 'lll'):
        a, b = packages['static', loader], packages['animation', loader]
        require(a['entry'] == b['entry'] and normalize_lua(a['lua'], a['entry']) == normalize_lua(b['lua'], b['entry']), 'Unrelated Lua changes between Static and Animation')
        require(set(a['files'])-set(b['files']) == set(), 'Static-only payload in paired build')
        extras = set(b['files'])-set(a['files'])
        require(extras == {'README-ANIMATION-TEST.txt'} if a['format'] == 'legacy' else extras <= {'README-ANIMATION-TEST.txt', RUNTIME+'README-ANIMATION-TEST.txt'}, 'Unexpected animation-only payload')
        for name in set(a['files']) & set(b['files']):
            if name == RUNTIME+a['entry'] or (a['format'] == 'modular' and name == RUNTIME+'FILES-SHA256.txt'):
                continue
            if name == RUNTIME+'manifest.json':
                metadata_parity(a['files'][name], b['files'][name], ('name', 'description'))
            elif name == 'manifest.json':
                metadata_parity(a['files'][name], b['files'][name], ('Name', 'Description'))
            elif name == PATCH:
                left = a['startup'].replace(a['lua'].decode().replace('\r\n', '\n'), '<shared Lua>')
                right = b['startup'].replace(b['lua'].decode().replace('\r\n', '\n'), '<shared Lua>')
                require(left == right, 'Unrelated BSL startup changes between variants')
            else:
                require(a['files'][name] == b['files'][name], 'Unrelated paired payload differs: '+name)
    return {'version': version, 'development_build_id': build_id,
            'shared_lua_sha256': sha(shared), 'reload_requested': False,
            'archives': [{'mode': mode, 'loader': loader, 'path': package['path'], 'sha256': package['sha256'],
                          'entry': package['entry'], 'format': package['format'],
                          'mod_sha256': sha(package['lua']), 'manifest_sha256': sha(package['files'][RUNTIME+'manifest.json'])}
                         for (mode, loader), package in sorted(packages.items())]}


def snapshot_inputs(root):
    top = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=root, text=True).strip()
    require(Path(top).resolve() == root.resolve(), 'Use the canonical Epic LUT Git root')
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    result = {name: sha((root/name).read_bytes()) if (root/name).is_file() else None for name in names if name}
    native = Path(os.environ['EPIC_LUT_INPUT_LIBRARY']) if os.environ.get('EPIC_LUT_INPUT_LIBRARY') else root.parent/'DBF-MCM/native/build'/NATIVE
    result['external:'+str(native.resolve())] = sha(native.read_bytes())
    for base in (root/'dist', root/'dist/deployment/baselines/R5.5.4'):
        for loader in ('BSL', 'LLL'):
            path = base/f'Epic-LUT-R5.5.4-{loader}.zip'
            if path.exists():
                result['protected:'+str(path.resolve())] = sha(path.read_bytes())
    return result


def pair_paths(root):
    return {(mode, loader): (root/'dist' if loader == 'bsl' else root/'dist/releases/modular-20261010')/f'Epic-LUT-Dev-{mode.title()}-{loader.upper()}.zip'
            for mode in ('static', 'animation') for loader in ('bsl', 'lll')}


def build_pair(root):
    before = snapshot_inputs(root)
    paths = pair_paths(root)
    stamp = uuid.uuid4().hex
    for mode in ('static', 'animation'):
        for loader in ('bsl', 'lll'):
            args = [sys.executable, 'build.py' if loader == 'bsl' else 'tools/build_lll.py',
                    '--output', paths[mode, loader].name, '--dev-stamp', stamp]
            if loader == 'bsl':
                args += ['--loader', 'bsl']
            if mode == 'animation':
                args.append('--preview-animation')
            subprocess.run(args, cwd=root, check=True)
        subprocess.run([sys.executable, 'tests/test_build_inventory.py'], cwd=root, check=True)
        subprocess.run([sys.executable, 'tests/test_release.py', str(paths[mode, 'bsl'])], cwd=root, check=True)
    # Full editor checks once, then the distinct preview contracts and BSL envelopes.
    for script in ('verify.py', 'tools/verify_player_preview.py', 'tests/test_lll_modular.py'):
        subprocess.run([sys.executable, script], cwd=root, check=True)
    receipt = validate_pair(paths)
    require(receipt['development_build_id'] == stamp, 'Paired archives do not contain this development build ID')
    require(snapshot_inputs(root) == before, 'Maintained build inputs changed during paired build; rebuild before deployment')
    receipt['inputs'] = before
    write_json(root/'dist/deployment/pair.json', receipt)
    return receipt


def select_package(root, mode):
    if mode == 'rollback':
        folder = root/'dist/deployment/baselines/R5.5.4'
        path = folder/'Epic-LUT-R5.5.4-LLL.zip'
        baseline = json.loads((folder/'baseline.json').read_text())
        records = [item for item in baseline['archives'] if Path(item['path']).resolve() == path.resolve()]
        require(len(records) == 1 and sha(path.read_bytes()) == records[0]['sha256'], 'Preserved R5.5.4 baseline changed')
        package = read_package(path)
        require(package['mode'] == 'static' and package['version'] == 'R5.5.4' and sha(package['lua']) == records[0]['mod_sha256'], 'Invalid static rollback baseline')
        return package
    receipt = json.loads((root/'dist/deployment/pair.json').read_text())
    current = validate_pair(pair_paths(root))
    require(current == {key: value for key, value in receipt.items() if key != 'inputs'}, 'Paired archives changed since verification')
    require(snapshot_inputs(root) == receipt['inputs'], 'Maintained source changed; run --build before development deployment')
    return read_package(pair_paths(root)[mode, 'lll'])


def installed_files(target):
    require(target.is_dir() and target.resolve() == target.absolute(), 'Existing physical LLL editor directory required')
    require(not blocked_path(target), 'Virtualized installed path is unsupported')
    entry = 'main.lua' if (target/'main.lua').exists() else 'mod.lua'
    require(not (entry == 'main.lua' and (target/'mod.lua').exists()), 'Duplicate installed entrypoints; do not deploy a legacy mod.lua beside main.lua')
    inventory = checksum_inventory((target/'FILES-SHA256.txt').read_bytes()) if entry == 'main.lua' else None
    names = set(inventory or PAIR_FILES) | set(COMPANIONS)
    if inventory is not None:
        names.add('FILES-SHA256.txt')
    files = {name: data for name, data in runtime_state(target, names).items() if data is not None}
    require(all(name in files for name in ('manifest.json', entry, NATIVE)), 'Installed Lua, manifest and reviewed DLL required')
    require(sha(files[NATIVE]) == NATIVE_SHA, 'Installed native DLL differs; it will not be replaced')
    if inventory is not None:
        require(all(name in files and sha(files[name]) == digest for name, digest in inventory.items()), 'Installed FILES-SHA256 inventory differs from actual bytes')
        require(json.loads(files['manifest.json']).get('lll', {}).get('entry') == entry, 'Installed modular manifest entry differs')
    return files


def runtime_state(target, names):
    result = {}
    for name in names:
        path = target/relative_name(name)
        require(path.resolve() == path.absolute(), 'Installed runtime file is redirected: '+name)
        require(not path.exists() or path.is_file(), 'Installed runtime path is not a file: '+name)
        result[name] = path.read_bytes() if path.exists() else None
    return result


def hashes(files):
    return {name: sha(data) if data is not None else None for name, data in files.items()}


def replace_pair(target, desired, before, backup, replace=os.replace, entry='mod.lua'):
    """Stage changed files, publish entry last, and restore only owned writes."""
    backup.mkdir(parents=True, exist_ok=False)
    for name, data in before.items():
        atomic_write(backup/name, data)
    expected = hashes(before)
    names = set(before) | set(desired)
    require(hashes({name: (backup/name).read_bytes() for name in before}) == expected, 'Backup verification failed')
    expected.update({name: None for name in names-set(before)})
    require(hashes(runtime_state(target, names)) == expected, 'Installed files changed during backup')
    order = sorted(desired, key=lambda name: (3 if name == entry else 2 if name == 'FILES-SHA256.txt' else 1 if name == 'manifest.json' else 0, name))
    staged, written = {}, []
    try:
        for name in order:
            destination = target/name
            destination.parent.mkdir(parents=True, exist_ok=True)
            fd, temporary = tempfile.mkstemp(prefix=destination.name+'.', suffix='.pending', dir=destination.parent)
            staged[name] = Path(temporary)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(desired[name])
                stream.flush()
                os.fsync(stream.fileno())
        for name in order:
            require(hashes(runtime_state(target, names)) == expected, 'Installed files changed before replacement')
            replace(staged[name], target/name)
            written.append(name)
            expected[name] = sha(desired[name])
        require(hashes(runtime_state(target, names)) == expected, 'Installed pair verification failed')
    except Exception as error:
        conflicts = []
        for name in reversed(written):
            try:
                if name in before:
                    atomic_write(target/name, before[name], expected=sha(desired[name]))
                else:
                    require((target/name).is_file() and sha((target/name).read_bytes()) == sha(desired[name]), 'New runtime file changed before rollback')
                    (target/name).unlink()
            except (OSError, RuntimeError):
                conflicts.append(name)
        suffix = '; unowned files preserved: '+', '.join(conflicts) if conflicts else ''
        raise RuntimeError(f'Deployment failed; backup: {backup}{suffix}; {error}') from error
    finally:
        for path in staged.values():
            path.unlink(missing_ok=True)


def deploy(root, package, mode, expect_installed=None, install=False, target=None):
    target = target or Path(os.environ['LOCALAPPDATA'])/'LLL/Helldivers2/Mods/armor_lut_editor'
    before = installed_files(target)
    expected = hashes(before)
    entry = 'main.lua' if 'main.lua' in before else 'mod.lua'
    if entry == 'main.lua' and mode == 'rollback':
        raise RuntimeError('Frozen R5.5.4 uses legacy mod.lua; use --static for this modular profile instead')
    require(package['entry'] == entry, 'Candidate entry differs from existing profile; this helper does not migrate entrypoints')
    active_path = root/'dist/deployment/active.json'
    active = json.loads(active_path.read_text()) if active_path.exists() else None
    if expect_installed:
        require(re.fullmatch('[0-9a-fA-F]{64}', expect_installed) is not None and expect_installed.lower() == expected[entry], 'Expected installed Lua SHA-256 differs')
    if active:
        if active.get('entry', 'mod.lua') != entry:
            require(not install or expect_installed, 'Adopting modular installation requires --expect-installed with current main.lua SHA-256')
        else:
            require(Path(active['target']).resolve() == target.resolve() and active['installed_hashes'] == expected, 'Installed files contain untracked changes; refusing replacement')
    require(not install or active or expect_installed, 'First installation requires --expect-installed with the current Lua SHA-256')
    runtime = {name[len(RUNTIME):]: data for name, data in package['files'].items() if name.startswith(RUNTIME)}
    if entry == 'main.lua':
        current_names = set(checksum_inventory(before['FILES-SHA256.txt']))
        require(current_names <= set(runtime), 'Modular candidate removes installed runtime files; migration is not authorized')
        for name in (NATIVE, 'library.txt', 'config/defaults.cfg'):
            require(name in before and runtime[name] == before[name], 'Protected modular runtime differs: '+name)
        writable = set(package['manifest']['lll']['modules']) | {'main.lua', 'manifest.json', 'FILES-SHA256.txt'}
        writable |= {name for name in runtime if name.startswith('tools/') and name.endswith(('.ps1', '.cs'))}
        desired = {}
        for name, data in runtime.items():
            if before.get(name) != data:
                require(name in writable, 'Non-code modular payload differs and will not be replaced: '+name)
                desired[name] = data
    else:
        desired = {name: runtime[name] for name in PAIR_FILES}
    require(package['files'][RUNTIME+NATIVE] == before[NATIVE], 'Candidate DLL differs from installed DLL')
    receipt = {'mode': mode, 'version': package['version'], 'archive': package['path'],
               'entry': entry, 'format': package['format'], 'changed_files': sorted(desired),
               'development_build_id': package['development_build_id'],
               'archive_sha256': package['sha256'], 'target': str(target.resolve()),
               'before_hashes': expected, 'installed_hashes': {**expected, **hashes(desired)},
               'reload_requested': False, 'installed': install}
    if not install:
        return receipt
    backup = root/'dist/deployment/backups'/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex)
    receipt['backup'] = str(backup)
    # The journal exists before mutations, including when replacement must roll back.
    backup.parent.mkdir(parents=True, exist_ok=True)
    write_json(backup.with_suffix('.json'), receipt)
    replace_pair(target, desired, before, backup, entry=entry)
    require(hashes(installed_files(target)) == receipt['installed_hashes'], 'Installed runtime inventory verification failed')
    write_json(backup/'receipt.json', receipt)
    write_json(active_path, receipt)
    return receipt


@contextmanager
def mutation_lock(root):
    folder = root/'dist/deployment'
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'manage.lock'
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        os.write(fd, str(os.getpid()).encode())
        os.close(fd)
        yield
    finally:
        path.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='Build and verify paired Static/Animation BSL+LLL archives')
    parser.add_argument('--install', action='store_true', help='Update changed runtime code/metadata; preserve native libraries, defaults and settings')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--static', action='store_true', help='Select current verified static development build')
    modes.add_argument('--rollback', action='store_true', help='Select immutable static R5.5.4 release')
    parser.add_argument('--expect-installed', help='Required first-install/adoption current main.lua or mod.lua SHA-256')
    args = parser.parse_args(argv)
    require_physical_runtime()
    mode = 'rollback' if args.rollback else 'static' if args.static else 'animation'
    def run():
        if args.build:
            build_pair(ROOT)
            print('PASS paired development builds; published release archives unchanged')
        if args.build and not args.install:
            return
        receipt = deploy(ROOT, select_package(ROOT, mode), mode, args.expect_installed, args.install)
        print(json.dumps(receipt, indent=2))
        print('Installed files verified; next normal loader lifecycle/game launch activates them.' if args.install else 'Preflight only; installed files unchanged.')
    if args.build or args.install:
        with mutation_lock(ROOT):
            run()
    else:
        run()


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, KeyError, ValueError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
