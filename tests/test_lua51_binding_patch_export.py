"""Production binding exports: stock Lua 5.1 and preserved LuaJIT byte output."""
from pathlib import Path
import hashlib
import os
import unittest

from lupa.lua51 import LuaRuntime as Lua51
from lupa.luajit21 import LuaRuntime as LuaJIT

ROOT = Path(__file__).resolve().parents[1]

FIXTURE = b"""local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function hash(id)
    local out={}
    for at=15,1,-2 do out[#out+1]=string.char(tonumber(id:sub(at,at+1),16)) end
    return table.concat(out)
end
local function replace(bytes,at,value)return bytes:sub(1,at)..value..bytes:sub(at+#value+1)end
local function source(resource,kind,main)
    return {resource=resource,main=main,toc=hash(resource)..hash(kind)..string.rep('\\0',24)
        ..string.rep('1',16)..word(#main)..word(0)..word(0)..word(32)..word(128)..word(7)}
end
local texture,material_id,unit_id='cf0cc31b981786c9','1234567890abcdef','abcdef0123456789'
local material=source(material_id,B.MATERIAL,
    replace(string.rep('\\0',136),64,word(1))..word(0x81d4c49d)..hash(texture))
local main=replace(replace(string.rep('\\0',152),112,word(116)),96,word(144))
main=replace(main,116,word(2)..word(1)..word(2)..hash(material_id)..hash(material_id))
local unit=source(unit_id,B.UNIT,main)
local original={resource=texture,main=string.rep('\\0',184)..'template',gpu='baseline',stream=''}
local entries,patches={},{}
for index=1,2 do
    local kind=index==1 and 'armor' or 'helmet'
    local key='p:0:'..(index-1)..':1:0'
    entries[index]={kind=kind,key=key,document={width=3,height=1},binding_source={
        version=1,verified=true,kind=kind,key=key,section=index,section_owned=true,
        original_texture=texture,texture_slot=0x81d4c49d,kit_override=false,material=material,unit=unit}}
    patches[index]={resource=texture,main=original.main,gpu=payload..string.char(index),stream=''}
end
local queries={}
local function encode()
    return B.encode('0102030405060708',entries,patches,{
        original_patch=function()return original end,
        id_available=function(kind,id)
            queries[#queries+1]=kind..':'..id
            return id~=rejected
        end})
end
local first=encode()
local requested=table.concat(queries,'|')
if retry then
    rejected=queries[1]:match(':([%x]+)$')
    queries={};first=encode();requested=table.concat(queries,'|')
    assert(not first.main:find(hash(rejected),1,true),'Collision candidate remained in archive')
end
return first.main,first.gpu,first.stream,requested
"""


def encode(runtime, payload, *, native=False, retry=False):
    lua = runtime(encoding=None, unpack_returned_tuples=True)
    if native:
        lua.execute(b"bit=require('bit')")
    else:
        lua.execute(b"""
            ffi,bit,jit=nil,nil,nil
            local previous=require
            require=function(name)
                assert(name~='ffi' and name~='bit' and name~='jit','Forbidden dependency: '..name)
                return previous(name)
            end
        """)
    lua.globals()[b"B"] = lua.execute((ROOT / "src/presets/binding_patch_export.lua").read_bytes())
    lua.globals()[b"payload"] = payload
    lua.globals()[b"retry"] = retry
    return lua.execute(FIXTURE)


class BindingPatchCompatibility(unittest.TestCase):
    def test_previous_export_and_collision_retry_bytes(self):
        # Captured from the unchanged bit-based writer on both maintained branches.
        expected = {
            False: (
                '47416173386e5e2d19888e5a4adecf5f527d10b4db0b0dc26e08dc993feb352f',
                '31b48d1eeb3d8cb6cb7f044f6aa118cedde805615a7cc48a8090ada765aa94b7',
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                'ca01fafe12a7af486dd785ce9829ccfbaff160864df3e14ddd34e21281249e48'),
            True: (
                '6e3b22275c07d764c17dcb8caac85281178022f976168ef23cd7542247135b71',
                'c68b24925d94ef4742d7e4e8af24b5ddae3f984889bce0c1a7f5c30ccf39fb07',
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                '0c31dfa095e88817a44a7cf75dd4cfc3eacb60f94ebeb29e5e41c28438182378'),
        }
        for retry, checksums in expected.items():
            result = encode(Lua51, b'123456789', retry=retry)
            self.assertEqual(tuple(hashlib.sha256(value).hexdigest() for value in result), checksums)

    def test_global_bit_fastpath_initializes_only_on_export(self):
        lua = LuaJIT(encoding=None, unpack_returned_tuples=True)
        lua.execute(b"""
            bit=require('bit');xor_calls=0
            local original=bit.bxor
            bit.bxor=function(...)xor_calls=xor_calls+1;return original(...)end
        """)
        lua.globals()[b'B'] = lua.execute((ROOT / 'src/presets/binding_patch_export.lua').read_bytes())
        self.assertEqual(lua.globals()[b'xor_calls'], 0)
        lua.globals()[b'payload'] = b'123456789'
        lua.execute(FIXTURE)
        self.assertGreater(lua.globals()[b'xor_calls'], 0)

    def test_portable_archives_match_native_fingerprint_bytes(self):
        payloads = [b"", b"123456789", bytes(range(256)), b"\0\xff\x80" * 128]
        for payload in payloads:
            for retry in (False, True):
                with self.subTest(length=len(payload), retry=retry):
                    expected = encode(LuaJIT, payload, native=True, retry=retry)
                    self.assertEqual(encode(Lua51, payload, retry=retry), expected)
                    self.assertEqual(encode(LuaJIT, payload, retry=retry), expected)

    def test_existing_native_fixture(self):
        before = Path.cwd()
        try:
            os.chdir(ROOT)
            (ROOT / "tests/tmp").mkdir(parents=True, exist_ok=True)
            lua = LuaJIT(encoding=None)
            lua.execute(b"bit=require('bit')")
            lua.execute((ROOT / "tests/binding_patch_export.lua").read_bytes())
        finally:
            os.chdir(before)


if __name__ == "__main__":
    unittest.main()
