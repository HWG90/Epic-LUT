"""Real stock Lua 5.1 document/copy/preset contracts; no native substitutes."""
import os
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)

class Documents(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        self.lua.execute(b"""
            ffi, bit, jit = nil, nil, nil
            local base = require
            function require(name)
                assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', name)
                return base(name)
            end
            B = require('src.core.float_buffer')
        """)

    def test_independent_history_and_metadata(self):
        self.lua.execute(b"""
            local State = dofile('src/core/basic_state.lua')
            local d = {width=23,height=2,data=B.new(184),original=B.new(184),revision=9,
                kind='weapon',weapon_slot=2,family='material',weapon_resource='fedcba9876543210'}
            for i=0,183 do d.data[i]=(i-83)/8;d.original[i]=i/8 end
            d.data[3]=-1/math.huge
            local before=B.bytes(d.data,184)
            d.binding_documents={first=d,second=d}
            local copy=State.clone(d)
            assert(copy.binding_documents.first==copy and copy.binding_documents.second==copy)
            copy.data[0]=99;assert(d.data[0]~=99 and copy.weapon_slot==2)
            local copier=State.copier();local historic=copier.copy(d)
            assert(copier.copy(d)==historic and historic.revision==9)
            d.data[3]=2;assert(B.bytes(historic.data,184)==before)
            local dst={width=23,height=3,data=B.new(276),revision=2}
            dst.data[275]=17;assert(State.copy(dst,historic)==2)
            assert(B.bytes(dst.data,184)==before and dst.data[275]==17 and dst.revision==3)
            assert(not pcall(State.copy,{width=3,height=1,data=B.new(12)},historic))
        """)

    def test_legacy_edit_row_history_and_presets(self):
        self.lua.execute(b"""
            local DDS=dofile('src/core/dds.lua')
            local Documents=dofile('src/legacy/document.lua')
            local Presets=dofile('src/legacy/presets.lua')
            local values=B.new(184)
            for i=0,183 do values[i]=(i-50)/16 end
            local name='0123456789abcdef'
            local lut={name=name,width=23,height=2,values=values}
            local catalog={identity={target_kind='armor',target_id=123,body=4},luts={lut}}
            local h={get=function(key)
                if key=='enabled' then return true end
                if key=='preserve_effects' then return false end
                if key:match('_on$') then return false end
                if key:match('_color$') then return '#123456' end
            end}
            local docs=Documents.new(DDS)
            docs.attach(catalog,'tests/tmp/nonexistent-lua51-path',h)
            local before=B.bytes(docs.documents[name].data,184)
            docs.edit(name,{[0]=12.5,[3]=-0.25})
            docs.row_copy(name,1);docs.row_paste(name,2)
            assert(B.bytes(docs.documents[name].data,92)==B.bytes(docs.documents[name].data,92,92))
            assert(docs.undo()==name and docs.undo()==name)
            assert(B.bytes(docs.documents[name].data,184)==before)
            docs.redo();local bytes=Presets.encode(catalog,h,docs)
            local settings,restored,version=Presets.decode(bytes,catalog)
            assert(version==2 and settings.enabled and not settings.preserve_effects)
            assert(B.bytes(restored[name],184)==B.bytes(docs.documents[name].data,184))
            local frozen=B.bytes(docs.documents[name].data,184)
            assert(not pcall(docs.edit,name,{[184]=1}))
            assert(B.bytes(docs.documents[name].data,184)==frozen)
        """)

    def test_preserved_effect_channels(self):
        self.lua.execute(b"""
            local S=dofile('src/core/semantics.lua')
            local old,new=B.new(92),B.new(92)
            for i=0,91 do old[i]=i/8;new[i]=-5 end
            local changed=S.protect(old,new,23,1)
            for col=1,23 do for ch=1,4 do
                local i=(col-1)*4+ch-1
                assert(changed[i]==(S.safe_lookup_cell(23,col,ch) and -5 or old[i]))
            end end
            assert(old[0]==0)
        """)

if __name__=='__main__': unittest.main()
