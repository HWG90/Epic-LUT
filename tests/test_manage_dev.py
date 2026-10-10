"""Paired-build and real filesystem deployment fixtures; never touch installed mods."""
from pathlib import Path
import json
import os
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import manage_dev as dev
from tools.lua_archive import hash_name, write

DLL = b'reviewed fixture DLL'
HELPER_BYTES = {name: field.encode() for field, name in dev.HELPERS.items()}


def package(path, mode, loader, extra='', stamp=None):
    animated = mode == 'animation'
    name = 'Epic LUT R5.5.4'+(' Preview Animation Test' if animated else '')
    description = name+(' - development candidate' if animated else ' - full release')
    lua = (f'-- {name}: fixture\n'
           "local m={}\nm.version='R5.5.4'\n"
           +(f"m.dev_build_id='{stamp}'\n" if stamp is not None else '')+
           f"m.preview_animation='{'garment_poses' if animated else 'disabled'}'\n"
           f"m.description='{description}'\nm.build_label='Dev-{mode}'\n"
           f"local PREVIEW_ANIMATION_ENABLED={'true' if animated else 'false'}\n"
           'local shared_behavior=42\n'+extra+
           ''.join("m."+field+"='"+HELPER_BYTES[name].hex()+"'\n" for field, name in dev.HELPERS.items())+
           "return {author='Goose'}\n").encode()
    manifest = {'name': name, 'description': description, 'version': 'R5.5.4', 'author': 'Goose', 'credits': 'fixture'}
    files = {dev.RUNTIME+'mod.lua': lua, dev.RUNTIME+'manifest.json': json.dumps(manifest).encode(),
             dev.RUNTIME+dev.NATIVE: DLL, dev.RUNTIME+'library.txt': dev.NATIVE.encode(), 'README.md': b'shared docs'}
    if animated:
        files['README-ANIMATION-TEST.txt'] = b'candidate instructions'
    if loader == 'bsl':
        files['manifest.json'] = json.dumps({'Name': name, 'Description': description, 'Author': 'Goose', 'Version': 1}).encode()
        startup = b'-- HD2-Addon: mods/goose/epic_lut/startup\nlocal make=function()\n'+lua+b'\nend\nreturn make\n'
        files[dev.PATCH] = write({hash_name('mods/goose/epic_lut/startup'): struct.pack('<II', len(startup), 2)+startup})
        files[dev.PATCH+'.stream'] = b''
        files[dev.PATCH+'.gpu_resources'] = b''
    else:
        files['INSTALL-MDL-LLL.md'] = b'LLL instructions'
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        for filename, data in files.items():
            archive.writestr(filename, data)
    return path


def modular_package(path, mode, stamp=None, module=b'return {shared=true}\n'):
    animated = mode == 'animation'
    name = 'Epic LUT R5.5.4'+(' Preview Animation Test' if animated else '')
    main = ('local m={}\nmod.scope.m=m\n'+
            'm.version="R5.5.4"\n'+
            'm.preview_animation='+json.dumps('authored_salute' if animated else 'disabled')+'\n'+
            ('m.dev_build_id='+json.dumps(stamp)+'\n' if stamp is not None else '')+
            'm.description='+json.dumps(name)+'\n'+
            'm.build_label='+json.dumps('Dev-'+mode)+'\n'+
            'mod.scope.PREVIEW_ANIMATION_ENABLED='+('true' if animated else 'false')+'\n').encode()
    modules = {'src/preview/player_animation.lua': module, 'src/preview/player_preview_candidate.lua': b'return editor\n'}
    manifest = {'id': 'armor_lut_editor', 'name': name, 'version': 'R5.5.4', 'author': 'Goose',
                'lll': {'entry': 'main.lua', 'defaults': 'config/defaults.cfg', 'modules': sorted(modules)}}
    files = {'main.lua': main, 'manifest.json': json.dumps(manifest).encode(), dev.NATIVE: DLL,
             'library.txt': dev.NATIVE.encode(), 'config/defaults.cfg': b'{"preferences":{}}\n',
             'LICENSE-CowboyBingus.txt': b'license', 'INSTALL.txt': b'LLL R30 instructions', **modules, **HELPER_BYTES}
    files['FILES-SHA256.txt'] = ''.join(dev.sha(data)+'  '+name+'\n' for name, data in sorted(files.items())).encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        for filename, data in files.items():
            archive.writestr(dev.RUNTIME+filename, data)
    return path


def change_member(path, name, value):
    with zipfile.ZipFile(path) as archive:
        files = {filename: archive.read(filename) for filename in archive.namelist()}
    files[name] = value
    with zipfile.ZipFile(path, 'w') as archive:
        for filename, data in files.items():
            archive.writestr(filename, data)


class ManagedDevelopment(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='epic-managed-dev-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        native = patch.object(dev, 'NATIVE_SHA', dev.sha(DLL))
        native.start()
        self.addCleanup(native.stop)
        self.paths = dev.pair_paths(self.root)
        for (mode, loader), path in self.paths.items():
            package(path, mode, loader)
        self.target = self.root/'installed/armor_lut_editor'
        self.target.mkdir(parents=True)
        for name, data in {'mod.lua': b'old Lua', 'manifest.json': b'{"version":"old"}',
                           dev.NATIVE: DLL, 'library.txt': dev.NATIVE.encode(),
                           'LICENSE-CowboyBingus.txt': b'license', 'settings.ini': b'keep settings'}.items():
            (self.target/name).write_bytes(data)
        self.before = dev.installed_files(self.target)

    def test_pair_and_unrelated_lua_rejection(self):
        receipt = dev.validate_pair(self.paths)
        self.assertEqual(len(receipt['archives']), 4)
        self.assertFalse(receipt['reload_requested'])
        for loader in ('bsl', 'lll'):
            package(self.paths['animation', loader], 'animation', loader, 'local unrelated_change=true\n')
        with self.assertRaisesRegex(RuntimeError, 'Unrelated Lua'):
            dev.validate_pair(self.paths)

    def test_mode_manifest_and_shared_payload_rejection(self):
        path = self.paths['animation', 'lll']
        with zipfile.ZipFile(path) as archive:
            manifest = json.loads(archive.read(dev.RUNTIME+'manifest.json'))
        manifest['name'] = 'Epic LUT R5.5.4'
        change_member(path, dev.RUNTIME+'manifest.json', json.dumps(manifest).encode())
        with self.assertRaisesRegex(RuntimeError, 'Manifest mode'):
            dev.read_package(path)
        package(path, 'animation', 'lll')
        for loader in ('bsl', 'lll'):
            change_member(self.paths['animation', loader], 'README.md', b'unrelated docs')
        with self.assertRaisesRegex(RuntimeError, 'Unrelated paired payload'):
            dev.validate_pair(self.paths)

    def test_build_checks_once_and_changed_input_rejection(self):
        def fixture_build(command, **_):
            if command[1] in ('build.py', 'tools/build_lll.py'):
                mode = 'animation' if '--preview-animation' in command else 'static'
                loader = 'bsl' if command[1] == 'build.py' else 'lll'
                stamp = command[command.index('--dev-stamp')+1]
                package(self.paths[mode, loader], mode, loader, stamp=stamp)
        with patch.object(dev, 'snapshot_inputs', return_value={'input': 'stable'}), patch.object(dev.subprocess, 'run', side_effect=fixture_build) as run:
            receipt = dev.build_pair(self.root)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(sum(command[1] == 'verify.py' for command in commands), 1)
        self.assertEqual(sum(command[1] == 'build.py' for command in commands), 2)
        self.assertEqual(sum(command[1] == 'tools/build_lll.py' for command in commands), 2)
        stamps = [command[command.index('--dev-stamp')+1] for command in commands if command[1] in ('build.py', 'tools/build_lll.py')]
        self.assertEqual(set(stamps), {receipt['development_build_id']})
        self.assertRegex(stamps[0], r'^[0-9a-f]{32}$')
        with patch.object(dev, 'snapshot_inputs', side_effect=[{'input': 'before'}, {'input': 'changed'}]), patch.object(dev.subprocess, 'run', side_effect=fixture_build):
            with self.assertRaisesRegex(RuntimeError, 'inputs changed'):
                dev.build_pair(self.root)

    def test_matching_build_stamp_and_mixed_stamp_rejection(self):
        stamp = 'a'*32
        for (mode, loader), path in self.paths.items():
            package(path, mode, loader, stamp=stamp)
        self.assertEqual(dev.validate_pair(self.paths)['development_build_id'], stamp)
        package(self.paths['animation', 'lll'], 'animation', 'lll', stamp='b'*32)
        with self.assertRaisesRegex(RuntimeError, 'development build IDs differ'):
            dev.validate_pair(self.paths)

    def test_guarded_pair_backups_static_switch_and_settings(self):
        animation = dev.read_package(self.paths['animation', 'lll'])
        with self.assertRaisesRegex(RuntimeError, 'First installation'):
            dev.deploy(self.root, animation, 'animation', install=True, target=self.target)
        receipt = dev.deploy(self.root, animation, 'animation', install=False, target=self.target)
        self.assertFalse(receipt['installed'])
        self.assertEqual(dev.installed_files(self.target), self.before)
        receipt = dev.deploy(self.root, animation, 'animation', dev.sha(self.before['mod.lua']), True, self.target)
        backup = Path(receipt['backup'])
        for name, data in self.before.items():
            self.assertEqual((backup/name).read_bytes(), data)
        self.assertEqual((self.target/'mod.lua').read_bytes(), animation['lua'])
        self.assertEqual((self.target/'manifest.json').read_bytes(), animation['files'][dev.RUNTIME+'manifest.json'])
        self.assertFalse(receipt['reload_requested'])
        static = dev.read_package(self.paths['static', 'lll'])
        dev.deploy(self.root, static, 'static', install=True, target=self.target)
        self.assertEqual((self.target/'mod.lua').read_bytes(), static['lua'])
        self.assertEqual((self.target/'settings.ini').read_bytes(), b'keep settings')
        self.assertEqual((self.target/dev.NATIVE).read_bytes(), DLL)
        (self.target/'manifest.json').write_bytes(b'foreign metadata')
        with self.assertRaisesRegex(RuntimeError, 'untracked changes'):
            dev.deploy(self.root, animation, 'animation', install=True, target=self.target)

    def test_expected_hash_race_is_rejected_without_writes(self):
        desired = {name: b'new '+name.encode() for name in dev.PAIR_FILES}
        (self.target/'mod.lua').write_bytes(b'other deployment')
        with self.assertRaisesRegex(RuntimeError, 'changed during backup'):
            dev.replace_pair(self.target, desired, self.before, self.root/'backup-race')
        self.assertEqual((self.target/'mod.lua').read_bytes(), b'other deployment')
        self.assertEqual((self.target/'manifest.json').read_bytes(), self.before['manifest.json'])

    def test_partial_failure_restores_only_owned_manifest(self):
        desired = {name: b'new '+name.encode() for name in dev.PAIR_FILES}
        seen = []
        def fail_lua(source, target):
            seen.append(target.name)
            if target.name == 'mod.lua':
                raise OSError('fixture replacement failure')
            os.replace(source, target)
        with self.assertRaisesRegex(RuntimeError, 'fixture replacement failure'):
            dev.replace_pair(self.target, desired, self.before, self.root/'backup-partial', replace=fail_lua)
        self.assertEqual(seen, ['manifest.json', 'mod.lua'])
        self.assertEqual(dev.installed_files(self.target), self.before)
        def foreign_change(source, target):
            if target.name == 'mod.lua':
                (self.target/'manifest.json').write_bytes(b'foreign owner')
                raise OSError('second writer')
            os.replace(source, target)
        with self.assertRaisesRegex(RuntimeError, 'unowned files preserved: manifest.json'):
            dev.replace_pair(self.target, desired, self.before, self.root/'backup-foreign', replace=foreign_change)
        self.assertEqual((self.target/'manifest.json').read_bytes(), b'foreign owner')
        self.assertEqual((self.target/'mod.lua').read_bytes(), self.before['mod.lua'])

    def test_race_between_pair_writes_preserves_foreign_lua(self):
        desired = {name: b'new '+name.encode() for name in dev.PAIR_FILES}
        def racing_write(source, target):
            os.replace(source, target)
            (self.target/'mod.lua').write_bytes(b'foreign Lua')
        with self.assertRaisesRegex(RuntimeError, 'changed before replacement'):
            dev.replace_pair(self.target, desired, self.before, self.root/'backup-mid-race', replace=racing_write)
        self.assertEqual((self.target/'manifest.json').read_bytes(), self.before['manifest.json'])
        self.assertEqual((self.target/'mod.lua').read_bytes(), b'foreign Lua')

    def test_immutable_release_baseline(self):
        folder = self.root/'dist/deployment/baselines/R5.5.4'
        baseline = package(folder/'Epic-LUT-R5.5.4-LLL.zip', 'static', 'lll')
        item = dev.read_package(baseline)
        dev.write_json(folder/'baseline.json', {'version': 'R5.5.4', 'archives': [
            {'path': str(baseline), 'sha256': item['sha256'], 'mod_sha256': dev.sha(item['lua'])}]})
        self.assertEqual(dev.select_package(self.root, 'rollback')['lua'], item['lua'])
        change_member(baseline, 'README.md', b'changed baseline')
        with self.assertRaisesRegex(RuntimeError, 'baseline changed'):
            dev.select_package(self.root, 'rollback')

    def install_modular_fixture(self, module=b'old shared module\n'):
        path = modular_package(self.root/'initial-modular.zip', 'static', module=module)
        package_data = dev.read_package(path)
        (self.target/'mod.lua').unlink()
        for name, data in package_data['files'].items():
            relative = name[len(dev.RUNTIME):]
            target = self.target/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        return dev.installed_files(self.target)

    def test_modular_gate_checksums_shared_modules_and_bsl_helpers(self):
        stamp = 'c'*32
        for (mode, loader), path in self.paths.items():
            if loader == 'lll':
                modular_package(path, mode, stamp)
            else:
                package(path, mode, loader, stamp=stamp)
        receipt = dev.validate_pair(self.paths)
        self.assertEqual(receipt['development_build_id'], stamp)
        self.assertEqual(dev.read_package(self.paths['animation', 'lll'])['entry'], 'main.lua')
        modular_package(self.paths['animation', 'lll'], 'animation', stamp, module=b'unrelated code\n')
        with self.assertRaisesRegex(RuntimeError, 'Unrelated paired payload'):
            dev.validate_pair(self.paths)
        modular_package(self.paths['animation', 'lll'], 'animation', stamp)
        change_member(self.paths['animation', 'lll'], dev.RUNTIME+'main.lua', b'changed after checksums')
        with self.assertRaisesRegex(RuntimeError, 'metadata'):
            dev.read_package(self.paths['animation', 'lll'])
        modular_package(self.paths['animation', 'lll'], 'animation', stamp)
        change_member(self.paths['animation', 'lll'], dev.RUNTIME+'tools/authored_preview_reader.cs', b'changed worker')
        with self.assertRaisesRegex(RuntimeError, 'checksum differs'):
            dev.read_package(self.paths['animation', 'lll'])

    def test_modular_adoption_changed_files_main_last_and_foreign_guard(self):
        before = self.install_modular_fixture()
        candidate = dev.read_package(modular_package(self.root/'authored.zip', 'animation', 'd'*32))
        dev.write_json(self.root/'dist/deployment/active.json', {
            'target': str(self.target), 'installed_hashes': {'mod.lua': 'legacy receipt'}})
        with self.assertRaisesRegex(RuntimeError, 'Adopting modular'):
            dev.deploy(self.root, candidate, 'animation', install=True, target=self.target)
        order = []
        original_replace = dev.replace_pair
        def replacing(*args, **kwargs):
            def record(source, target):
                order.append(target.relative_to(self.target).as_posix())
                os.replace(source, target)
            return original_replace(*args, **kwargs, replace=record)
        with patch.object(dev, 'replace_pair', side_effect=replacing):
            receipt = dev.deploy(self.root, candidate, 'animation', dev.sha(before['main.lua']), True, self.target)
        self.assertEqual(order[-1], 'main.lua')
        self.assertIn('src/preview/player_animation.lua', order)
        self.assertNotIn(dev.NATIVE, order)
        self.assertNotIn('library.txt', order)
        self.assertNotIn('config/defaults.cfg', order)
        self.assertFalse((self.target/'mod.lua').exists())
        self.assertEqual((self.target/'settings.ini').read_bytes(), b'keep settings')
        for name, data in before.items():
            self.assertEqual((Path(receipt['backup'])/name).read_bytes(), data)
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])
        baseline = dev.read_package(self.paths['static', 'lll'])
        with self.assertRaisesRegex(RuntimeError, 'use --static'):
            dev.deploy(self.root, baseline, 'rollback', install=True, target=self.target)
        (self.target/'src/preview/player_animation.lua').write_bytes(b'foreign code')
        with self.assertRaisesRegex(RuntimeError, 'inventory differs'):
            dev.deploy(self.root, candidate, 'animation', install=True, target=self.target)

    def test_modular_partial_failure_restores_inventory_and_no_duplicate_entry(self):
        before = self.install_modular_fixture()
        candidate = dev.read_package(modular_package(self.root/'authored.zip', 'animation'))
        desired = {name[len(dev.RUNTIME):]: data for name, data in candidate['files'].items()
                   if before.get(name[len(dev.RUNTIME):]) != data}
        def fail_main(source, target):
            if target.name == 'main.lua':
                raise OSError('modular main failure')
            os.replace(source, target)
        with self.assertRaisesRegex(RuntimeError, 'modular main failure'):
            dev.replace_pair(self.target, desired, before, self.root/'modular-backup', replace=fail_main, entry='main.lua')
        self.assertEqual(dev.installed_files(self.target), before)
        self.assertFalse((self.target/'mod.lua').exists())


if __name__ == '__main__':
    unittest.main()
