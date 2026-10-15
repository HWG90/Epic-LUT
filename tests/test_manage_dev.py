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
        files['INSTALL-MDL.md' if loader == 'mdl' else 'INSTALL-MDL-LLL.md'] = b'standalone instructions'
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        for filename, data in files.items():
            archive.writestr(filename, data)
    return path


def modular_package(path, mode, stamp=None, module=b'return {shared=true}\n', defaults=None, extra=None, version='R5.5.4'):
    animated = mode == 'animation'
    name = 'Epic LUT '+version+(' Preview Animation Test' if animated else '')
    main = ('local m={}\nmod.scope.m=m\n'+
            'm.version='+json.dumps(version)+'\n'+
            'm.preview_animation='+json.dumps('authored_salute' if animated else 'disabled')+'\n'+
            ('m.dev_build_id='+json.dumps(stamp)+'\n' if stamp is not None else '')+
            'm.description='+json.dumps(name)+'\n'+
            'm.build_label='+json.dumps('Dev-'+mode)+'\n'+
            'mod.scope.PREVIEW_ANIMATION_ENABLED='+('true' if animated else 'false')+'\n').encode()
    modules = {'src/preview/player_animation.lua': module, 'src/preview/player_preview_candidate.lua': b'return editor\n'}
    manifest = {'id': 'armor_lut_editor', 'name': name, 'version': version, 'author': 'Goose',
                'lll': {'entry': 'main.lua', 'defaults': 'config/defaults.cfg', 'modules': sorted(modules)}}
    files = {'main.lua': main, 'manifest.json': json.dumps(manifest).encode(), dev.NATIVE: DLL,
             'library.txt': dev.NATIVE.encode(), 'config/defaults.cfg': defaults if defaults is not None else b'{"preferences":{}}\n',
             'LICENSE-CowboyBingus.txt': b'license', 'INSTALL.txt': b'LLL R30 instructions', **modules, **HELPER_BYTES, **(extra or {})}
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

    def test_explicit_native_upgrade_retains_old_helper_and_settings(self):
        (self.target/dev.NATIVE).rename(self.target/dev.LEGACY_NATIVE)
        (self.target/'library.txt').write_bytes(dev.LEGACY_NATIVE.encode())
        with patch.object(dev,'LEGACY_NATIVE_SHA',dev.sha(DLL)):
            before=dev.installed_files(self.target)
            candidate=dev.read_package(self.paths['static','lll'])
            with self.assertRaisesRegex(RuntimeError,'upgrade-input-runtime'):
                dev.deploy(self.root,candidate,'static',expect_installed=dev.sha(before['mod.lua']),install=True,target=self.target)
            receipt=dev.deploy(self.root,candidate,'static',expect_installed=dev.sha(before['mod.lua']),install=True,target=self.target,upgrade_input=True)
            self.assertEqual((self.target/dev.LEGACY_NATIVE).read_bytes(),DLL)
            self.assertEqual((self.target/dev.NATIVE).read_bytes(),DLL)
            self.assertEqual((self.target/'settings.ini').read_bytes(),b'keep settings')
            self.assertIn(dev.NATIVE,receipt['changed_files'])

    def test_modular_native_upgrade_preserves_old_dll(self):
        self.install_modular_fixture()
        old=(self.target/dev.NATIVE).read_bytes()
        (self.target/dev.NATIVE).rename(self.target/dev.LEGACY_NATIVE)
        (self.target/'library.txt').write_bytes(dev.LEGACY_NATIVE.encode())
        index=self.target/'FILES-SHA256.txt'
        entries=dev.checksum_inventory(index.read_bytes())
        entries[dev.LEGACY_NATIVE]=entries.pop(dev.NATIVE)
        entries['library.txt']=dev.sha(dev.LEGACY_NATIVE.encode())
        index.write_bytes(''.join(d+'  '+n+'\n'for n,d in sorted(entries.items())).encode())
        with patch.object(dev,'LEGACY_NATIVE_SHA',dev.sha(old)):
            before=dev.installed_files(self.target)
            path=modular_package(self.root/'new-helper.zip','static')
            candidate=dev.read_package(path)
            with self.assertRaisesRegex(RuntimeError,'upgrade-input-runtime'):
                dev.deploy(self.root,candidate,'static',expect_installed=dev.sha(before['main.lua']),target=self.target)
            receipt=dev.deploy(self.root,candidate,'static',expect_installed=dev.sha(before['main.lua']),target=self.target,install=True,upgrade_input=True)
            self.assertEqual((self.target/dev.LEGACY_NATIVE).read_bytes(),old)
            self.assertEqual((self.target/dev.NATIVE).read_bytes(),DLL)
            self.assertEqual(receipt['installed_hashes'],dev.hashes(dev.installed_files(self.target)))

    def test_requested_cursor_and_confirmation_defaults_are_additive_and_typed(self):
        old=json.dumps({'preferences':{'font_size':16}}).encode()
        good={'preferences':{'font_size':16,'cursor_mode':1,'confirm_preset_overwrites':True}}
        dev.authorize_pattern_default(old,json.dumps(good).encode())
        for key,bad in [('cursor_mode',True),('cursor_mode',2),('confirm_preset_overwrites',1),('confirm_preset_overwrites',False)]:
            candidate={'preferences':dict(good['preferences'])};candidate['preferences'][key]=bad
            with self.assertRaisesRegex(RuntimeError,'may only add'):
                dev.authorize_pattern_default(old,json.dumps(candidate).encode())
        good['preferences']['font_size']=12
        with self.assertRaisesRegex(RuntimeError,'unrelated'):
            dev.authorize_pattern_default(old,json.dumps(good).encode())

    def test_pair_and_unrelated_lua_rejection(self):
        receipt = dev.validate_pair(self.paths)
        self.assertEqual(len(receipt['archives']), 6)
        self.assertFalse(receipt['reload_requested'])
        for loader in dev.LOADERS:
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
        for loader in dev.LOADERS:
            change_member(self.paths['animation', loader], 'README.md', b'unrelated docs')
        with self.assertRaisesRegex(RuntimeError, 'Unrelated paired payload'):
            dev.validate_pair(self.paths)

    def test_build_checks_once_and_changed_input_rejection(self):
        def fixture_build(command, **_):
            if command[1] in ('build.py', 'tools/build_lll.py'):
                mode = 'animation' if '--preview-animation' in command else 'static'
                loader = command[command.index('--loader')+1] if command[1] == 'build.py' else 'lll'
                stamp = command[command.index('--dev-stamp')+1]
                package(self.paths[mode, loader], mode, loader, stamp=stamp)
        with patch.object(dev, 'snapshot_inputs', return_value={'input': 'stable'}), patch.object(dev.subprocess, 'run', side_effect=fixture_build) as run:
            receipt = dev.build_pair(self.root)
            self.assertEqual(dev.select_package(self.root, 'static')['path'], str(self.paths['static', 'lll'].resolve()))
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(sum(command[1] == 'verify.py' for command in commands), 1)
        self.assertEqual(sum(command[1] == 'build.py' for command in commands), 4)
        self.assertEqual(sum(command[1] == 'tools/build_lll.py' for command in commands), 2)
        self.assertEqual(sum(command[1] == 'build.py' and command[command.index('--loader')+1] == 'mdl' for command in commands), 2)
        mdl_checks = [command for command in commands if command[1] == 'tests/test_mdl_package.py']
        self.assertEqual(len(mdl_checks), 2)
        self.assertEqual({command[command.index('--mode')+1] for command in mdl_checks}, {'static', 'animation'})
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

    def test_cli_defaults_static_lll_and_animation_requires_explicit_option(self):
        artifacts = {key: path.read_bytes() for key, path in self.paths.items()}
        cases = [
            ([], 'static', False),
            (['--install'], 'static', True),
            (['--static', '--install'], 'static', True),
            (['--animation', '--install'], 'animation', True),
            (['--rollback'], 'rollback', False),
            (['--build', '--install'], 'static', True),
        ]
        for argv, mode, installing in cases:
            with self.subTest(argv=argv):
                chosen = {'entry': 'main.lua', 'format': 'modular', 'path': 'LLL-only fixture'}
                with patch.object(dev, 'ROOT', self.root), patch.object(dev, 'require_physical_runtime'), patch.object(dev, 'build_pair') as build, patch.object(dev, 'select_package', return_value=chosen) as select, patch.object(dev, 'deploy', return_value={'mode': mode}) as deploy, patch('builtins.print'):
                    dev.main(argv)
                select.assert_called_once_with(self.root, mode)
                deploy.assert_called_once_with(self.root, chosen, mode, None, installing)
                self.assertEqual(build.call_count, int('--build' in argv))
        self.assertEqual(artifacts, {key: path.read_bytes() for key, path in self.paths.items()})
        self.assertEqual(set(dev.LOADERS), {'bsl', 'lll', 'mdl'})

    def test_cli_preview_modes_are_mutually_exclusive(self):
        for argv in (['--animation', '--static'], ['--animation', '--rollback']):
            with self.subTest(argv=argv), patch('sys.stderr'), patch.object(dev, 'deploy') as deploy:
                with self.assertRaises(SystemExit) as error:
                    dev.main(argv)
                self.assertEqual(error.exception.code, 2)
                deploy.assert_not_called()

    def test_mdl_pair_model_payload_provider_and_stamp_guards(self):
        receipt = dev.validate_pair(self.paths)
        self.assertEqual({entry['loader'] for entry in receipt['archives']}, {'bsl', 'lll', 'mdl'})
        for mode in ('static', 'animation'):
            self.assertEqual(self.paths[mode, 'mdl'], self.root/'dist'/f'Epic-LUT-Dev-{mode.title()}-MDL.zip')
            mdl = dev.read_package(self.paths[mode, 'mdl'])
            bsl = dev.read_package(self.paths[mode, 'bsl'])
            self.assertEqual(mdl['lua'], bsl['lua'])
            self.assertIsNone(mdl['startup'])
        package(self.paths['animation', 'mdl'], 'animation', 'mdl', extra='local MDL_only_behavior=99\n')
        with self.assertRaisesRegex(RuntimeError, 'BSL/MDL Lua bytes differ'):
            dev.validate_pair(self.paths)
        package(self.paths['animation', 'mdl'], 'animation', 'mdl')
        change_member(self.paths['static', 'mdl'], dev.RUNTIME+'library.txt', b'unrelated DLL registration')
        with self.assertRaisesRegex(RuntimeError, 'BSL/MDL runtime payload differs|Unknown input runtime selector'):
            dev.validate_pair(self.paths)
        package(self.paths['static', 'mdl'], 'static', 'mdl')
        change_member(self.paths['static', 'mdl'], 'README.md', b'MDL changed shared documentation')
        with self.assertRaisesRegex(RuntimeError, 'BSL/MDL shared payload differs'):
            dev.validate_pair(self.paths)
        package(self.paths['static', 'mdl'], 'static', 'bsl')
        with self.assertRaisesRegex(RuntimeError, 'loader differs from pair identity'):
            dev.validate_pair(self.paths)
        package(self.paths['static', 'mdl'], 'static', 'mdl')
        change_member(self.paths['static', 'mdl'], 'data/unrelated.patch_0', b'unexpected provider')
        with self.assertRaisesRegex(RuntimeError, 'must not contain a startup provider'):
            dev.validate_pair(self.paths)
        modular_package(self.paths['static', 'mdl'], 'static')
        with self.assertRaisesRegex(RuntimeError, 'MDL requires'):
            dev.validate_pair(self.paths)
        package(self.paths['static', 'mdl'], 'static', 'mdl')
        package(self.paths['animation', 'mdl'], 'animation', 'mdl', stamp='b'*32)
        with self.assertRaisesRegex(RuntimeError, 'development build IDs differ'):
            dev.validate_pair(self.paths)

    def test_published_mdl_archives_are_protected_inputs(self):
        source = self.root/'source.lua'
        source.write_bytes(b'return maintained_source')
        native = self.root/'reviewed.dll'
        native.write_bytes(DLL)
        release = self.root/'dist/releases/R5.5.5/Epic-LUT-R5.5.5-MDL.zip'
        release.parent.mkdir(parents=True)
        release.write_bytes(b'preserved published MDL fixture')
        with patch.dict(dev.os.environ, {'EPIC_LUT_INPUT_LIBRARY': str(native)}), patch.object(dev.subprocess, 'check_output', side_effect=[str(self.root), b'source.lua\0']):
            inputs = dev.snapshot_inputs(self.root)
        self.assertEqual(inputs['protected:'+str(release.resolve())], dev.sha(release.read_bytes()))
        self.assertFalse(any(name.startswith('protected:') and 'Epic-LUT-Dev-' in name for name in inputs))

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

    def install_modular_fixture(self, module=b'old shared module\n', defaults=None, extra=None):
        path = modular_package(self.root/'initial-modular.zip', 'static', module=module, defaults=defaults, extra=extra)
        package_data = dev.read_package(path)
        (self.target/'mod.lua').unlink(missing_ok=True)
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

    def test_public_modular_document_additions_updates_and_inventory(self):
        before = self.install_modular_fixture()
        docs = {'README.md': b'public readme', 'CHANGELOG.md': b'public changelog',
                'docs/RELEASE-R5.5.4.md': b'current release notes'}
        settings = self.target/'config/settings.cfg'
        settings.write_bytes(b'preserved saved settings')
        candidate = dev.read_package(modular_package(self.root/'public-docs.zip', 'static', '1'*32, extra=docs))
        preflight = dev.deploy(self.root, candidate, 'static', target=self.target)
        self.assertTrue(docs.keys() <= set(preflight['changed_files']))
        self.assertEqual(dev.installed_files(self.target), before)
        receipt = dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
        for name, data in docs.items():
            self.assertEqual((self.target/name).read_bytes(), data)
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])
        updated = {name: data+b' updated' for name, data in docs.items()}
        candidate = dev.read_package(modular_package(self.root/'updated-public-docs.zip', 'static', '2'*32, extra=updated))
        receipt = dev.deploy(self.root, candidate, 'static', install=True, target=self.target)
        for name, data in updated.items():
            self.assertEqual((self.target/name).read_bytes(), data)
            self.assertEqual((Path(receipt['backup'])/name).read_bytes(), docs[name])
        self.assertNotIn(dev.NATIVE, receipt['changed_files'])
        self.assertNotIn('library.txt', receipt['changed_files'])
        self.assertNotIn('config/defaults.cfg', receipt['changed_files'])
        self.assertNotIn('config/settings.cfg', receipt['changed_files'])
        self.assertEqual(settings.read_bytes(), b'preserved saved settings')
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])

    def test_public_modular_docs_do_not_authorize_other_noncode_payloads(self):
        before = self.install_modular_fixture()
        for index, name in enumerate(('README.txt', 'readme.md', 'docs/README.md', 'docs/RELEASE-R5.5.5.md',
                                      'config/settings.cfg', 'private.md', 'LICENSE-CowboyBingus.txt', 'INSTALL.txt')):
            with self.subTest(name=name):
                candidate = dev.read_package(modular_package(self.root/f'noncode-{index}.zip', 'static',
                    extra={'README.md': b'allowed docs', name: b'unapproved payload'}))
                with self.assertRaisesRegex(RuntimeError, 'Non-code modular payload differs'):
                    dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
                self.assertEqual(dev.installed_files(self.target), before)
                self.assertFalse((self.root/'dist/deployment/active.json').exists())

    def test_prerelease_upgrade_retains_prior_notes_and_protects_noncurrent_docs(self):
        old_name = 'docs/RELEASE-R5.5.4.md'
        before = self.install_modular_fixture(extra={old_name: b'published notes'})
        new_name = 'docs/RELEASE-R6.0.0-alpha1.md'
        docs = {old_name: before[old_name], new_name: b'development notes'}
        candidate = dev.read_package(modular_package(self.root/'r6-alpha.zip', 'static', '4'*32,
            extra=docs, version='R6.0.0-alpha1'))
        receipt = dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
        self.assertEqual((self.target/old_name).read_bytes(), before[old_name])
        self.assertNotIn(old_name, receipt['changed_files'])
        self.assertIn(new_name, receipt['changed_files'])
        self.assertNotIn(dev.NATIVE, receipt['changed_files'])
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])
        docs[old_name] = b'changed prior notes'
        candidate = dev.read_package(modular_package(self.root/'r6-alpha-changed.zip', 'static', '5'*32,
            extra=docs, version='R6.0.0-alpha1'))
        with self.assertRaisesRegex(RuntimeError, 'Non-code modular payload differs'):
            dev.deploy(self.root, candidate, 'static', install=True, target=self.target)

    def test_release_transition_preserves_previous_notes_but_refuses_code_removal(self):
        old_name = 'docs/RELEASE-R6.0.0-alpha1.md'
        before = self.install_modular_fixture(extra={old_name: b'previous release notes'})
        candidate = dev.read_package(modular_package(self.root/'alpha2.zip', 'static', '3'*32,
            extra={'docs/RELEASE-R6.0.0-alpha2.md': b'current release notes'}, version='R6.0.0-alpha2'))
        receipt = dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
        self.assertEqual((self.target/old_name).read_bytes(), before[old_name])
        self.assertEqual(receipt['retained_documents'][old_name], dev.sha(before[old_name]))
        self.assertNotIn(old_name, receipt['installed_hashes'])
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])
        self.assertEqual(dev.deploy(self.root, candidate, 'static', target=self.target)['changed_files'], [])

    def test_scoped_release_help_docs_are_backed_up_without_settings_changes(self):
        before = self.install_modular_fixture()
        docs = {'docs/PRESET-PATCH-RESTORE.md': b'public restore help',
                'docs/SHARING-COMPRESSION.md': b'public compression help'}
        candidate = dev.read_package(modular_package(self.root/'release-help.zip', 'static',
                                                     extra=docs))
        receipt = dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
        for name, content in docs.items():
            self.assertEqual((self.target/name).read_bytes(), content)
            self.assertIn(name, receipt['changed_files'])
        self.assertEqual((self.target/'config/defaults.cfg').read_bytes(), before['config/defaults.cfg'])
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])

    def test_public_modular_docs_partial_failure_restores_updates_and_removes_additions(self):
        before = self.install_modular_fixture(extra={'README.md': b'old readme'})
        docs = {'README.md': b'updated readme', 'CHANGELOG.md': b'new changelog',
                'docs/RELEASE-R5.5.4.md': b'new release notes'}
        candidate = dev.read_package(modular_package(self.root/'failed-public-docs.zip', 'static', '3'*32, extra=docs))
        original_replace = dev.replace_pair
        def replacing(*args, **kwargs):
            def fail_main(source, target):
                if target.name == 'main.lua':
                    raise OSError('Public documentation main failure')
                os.replace(source, target)
            return original_replace(*args, **kwargs, replace=fail_main)
        with patch.object(dev, 'replace_pair', side_effect=replacing):
            with self.assertRaisesRegex(RuntimeError, 'Public documentation main failure'):
                dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
        self.assertEqual(dev.installed_files(self.target), before)
        self.assertEqual((self.target/'README.md').read_bytes(), b'old readme')
        self.assertFalse((self.target/'CHANGELOG.md').exists())
        self.assertFalse((self.target/'docs/RELEASE-R5.5.4.md').exists())
        self.assertFalse((self.root/'dist/deployment/active.json').exists())

    def test_authorized_pattern_default_migration_backs_up_and_preserves_settings(self):
        old_defaults = b'{"preferences":{"menu_key":121,"include_capes_in_armor_exports":true},"other":{"keep":[false,1,"x"]}}\n'
        updated = json.loads(old_defaults)
        updated['preferences']['include_patterns_in_exports'] = True
        updated['preferences']['tools_docked'] = True
        new_defaults = (json.dumps(updated, indent=2)+'\n').encode()
        before = self.install_modular_fixture(defaults=old_defaults)
        settings = self.target/'config/settings.cfg'
        settings.write_bytes(b'{"preferences":{"menu_key":45,"include_patterns_in_exports":false,"tools_docked":false}}\n')
        settings_before = settings.read_bytes()
        candidate = dev.read_package(modular_package(self.root/'pattern-default.zip', 'static', 'e'*32, defaults=new_defaults))
        preflight = dev.deploy(self.root, candidate, 'static', target=self.target)
        self.assertIn('config/defaults.cfg', preflight['changed_files'])
        self.assertEqual(dev.installed_files(self.target), before)
        order = []
        original_replace = dev.replace_pair
        def replacing(*args, **kwargs):
            def record(source, target):
                order.append(target.relative_to(self.target).as_posix())
                os.replace(source, target)
            return original_replace(*args, **kwargs, replace=record)
        with patch.object(dev, 'replace_pair', side_effect=replacing):
            receipt = dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
        self.assertEqual(order[-1], 'main.lua')
        self.assertIn('config/defaults.cfg', order)
        self.assertNotIn('config/settings.cfg', order)
        self.assertNotIn(dev.NATIVE, order)
        self.assertNotIn('library.txt', order)
        self.assertEqual((self.target/'config/defaults.cfg').read_bytes(), new_defaults)
        self.assertEqual((Path(receipt['backup'])/'config/defaults.cfg').read_bytes(), old_defaults)
        self.assertEqual(settings.read_bytes(), settings_before)
        self.assertEqual((self.target/'settings.ini').read_bytes(), b'keep settings')
        inventory = dev.checksum_inventory((self.target/'FILES-SHA256.txt').read_bytes())
        self.assertEqual(inventory['config/defaults.cfg'], dev.sha(new_defaults))
        self.assertEqual(dev.hashes(dev.installed_files(self.target)), receipt['installed_hashes'])
        self.assertEqual(dev.deploy(self.root, candidate, 'static', target=self.target)['changed_files'], [])

    def test_pattern_default_partial_failure_restores_defaults_and_inventory(self):
        old_defaults = b'{"preferences":{"menu_key":121,"include_patterns_in_exports":true}}\n'
        new_defaults = b'{"preferences":{"menu_key":121,"include_patterns_in_exports":true,"tools_docked":true}}\n'
        before = self.install_modular_fixture(defaults=old_defaults)
        settings = self.target/'config/settings.cfg'
        settings.write_bytes(b'{"preferences":{"include_capes_in_armor_exports":false,"tools_docked":false}}\n')
        settings_before = settings.read_bytes()
        candidate = dev.read_package(modular_package(self.root/'failed-pattern-default.zip', 'animation', 'f'*32, defaults=new_defaults))
        original_replace = dev.replace_pair
        order = []
        def replacing(*args, **kwargs):
            def fail_main(source, target):
                order.append(target.relative_to(self.target).as_posix())
                if target.name == 'main.lua':
                    raise OSError('Pattern migration main failure')
                os.replace(source, target)
            return original_replace(*args, **kwargs, replace=fail_main)
        with patch.object(dev, 'replace_pair', side_effect=replacing):
            with self.assertRaisesRegex(RuntimeError, 'Pattern migration main failure'):
                dev.deploy(self.root, candidate, 'animation', dev.sha(before['main.lua']), True, self.target)
        self.assertIn('config/defaults.cfg', order)
        self.assertEqual(dev.installed_files(self.target), before)
        self.assertEqual(settings.read_bytes(), settings_before)
        backup = list((self.root/'dist/deployment/backups').glob('*/config/defaults.cfg'))
        self.assertEqual(len(backup), 1)
        self.assertEqual(backup[0].read_bytes(), old_defaults)
        self.assertFalse((self.root/'dist/deployment/active.json').exists())

    def test_pattern_default_migration_rejects_unrelated_and_existing_changes(self):
        baseline = {'preferences': {'menu_key': 121, 'include_capes_in_armor_exports': True}, 'other': {'keep': [False, 1, 'x']}}
        before = self.install_modular_fixture(defaults=json.dumps(baseline).encode())
        variants = []
        def variant(change):
            value = json.loads(json.dumps(baseline))
            value['preferences']['include_patterns_in_exports'] = True
            value['preferences']['tools_docked'] = True
            change(value)
            variants.append(value)
        variant(lambda v: v['preferences'].update(menu_key=45))
        variant(lambda v: v['preferences'].update(menu_key=121.0))
        variant(lambda v: v['preferences'].update(include_capes_in_armor_exports=1))
        variant(lambda v: v['preferences'].pop('menu_key'))
        variant(lambda v: v['preferences'].update(unrelated=True))
        variant(lambda v: v.update(unrelated=True))
        variant(lambda v: v['other']['keep'].__setitem__(0, 0))
        variant(lambda v: v['preferences'].update(include_patterns_in_exports=False))
        variant(lambda v: v['preferences'].update(include_patterns_in_exports=1))
        variant(lambda v: v['preferences'].update(tools_docked=False))
        variant(lambda v: v['preferences'].update(tools_docked=1))
        for index, defaults in enumerate(variants):
            with self.subTest(index=index):
                candidate = dev.read_package(modular_package(self.root/f'rejected-{index}.zip', 'static', defaults=json.dumps(defaults).encode()))
                with self.assertRaisesRegex(RuntimeError, 'Protected modular defaults'):
                    dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
                self.assertEqual(dev.installed_files(self.target), before)
        for key in ('include_patterns_in_exports', 'tools_docked'):
            with self.subTest(existing_false=key):
                existing = {'preferences': {key: False}}
                before = self.install_modular_fixture(defaults=json.dumps(existing).encode())
                existing['preferences'][key] = True
                candidate = dev.read_package(modular_package(self.root/f'changed-{key}.zip', 'static', defaults=json.dumps(existing).encode()))
                with self.assertRaisesRegex(RuntimeError, 'may only add'):
                    dev.deploy(self.root, candidate, 'static', dev.sha(before['main.lua']), True, self.target)
                self.assertEqual(dev.installed_files(self.target), before)


if __name__ == '__main__':
    unittest.main()
