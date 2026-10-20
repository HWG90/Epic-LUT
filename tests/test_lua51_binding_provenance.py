"""Provenance SHA256 dispatch contracts against independent hashlib and BCrypt."""
from pathlib import Path
import hashlib
import os
import unittest

from lupa.lua51 import LuaRuntime as Lua51
from lupa.luajit21 import LuaRuntime as LuaJIT

ROOT = Path(__file__).resolve().parents[1]


def portable_runtime():
    lua = Lua51(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""
        ffi, bit, jit = nil, nil, nil
        local old_require = require
        function require(name)
            assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
            return old_require(name)
        end
    """)

    def start():
        digest = hashlib.sha256()
        return lua.table_from({
            b'update': lambda chunk: digest.update(chunk),
            b'finish': lambda: digest.hexdigest().encode('ascii'),
        })

    lua.globals()[b'sha256_start'] = start
    return lua


class BindingProvenancePortability(unittest.TestCase):
    def setUp(self):
        self.previous = Path.cwd()
        os.chdir(ROOT)
        (ROOT / 'tests/tmp').mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        os.chdir(self.previous)

    def test_real_sha256_service_contract_and_cooperative_readers(self):
        portable_runtime().execute((ROOT / 'tests/binding_provenance_portable.lua').read_bytes())

    def test_full_binding_cache_with_portable_sha256(self):
        lua = portable_runtime()
        lua.execute(b"""
            m = { platform = { digest = function(bytes)
                local hash = sha256_start()
                if type(bytes) == 'string' then hash.update(bytes)
                else while true do local chunk = bytes(); if chunk == nil then break end; hash.update(chunk) end end
                return hash.finish()
            end } }
        """)
        lua.execute((ROOT / 'tests/binding_source_cache.lua').read_bytes())

    def test_legacy_bcrypt_provenance_regression(self):
        lua = LuaJIT(encoding=None, unpack_returned_tuples=True)
        lua.execute((ROOT / 'tests/binding_provenance.lua').read_bytes())


if __name__ == '__main__':
    unittest.main()
