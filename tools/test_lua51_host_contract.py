"""Check Epic LUT's usable modular LLL host contract under actual Lua 5.1.

This loads maintained LLL source, not a simulated replacement implementation.
Filesystem effects are injected in memory; no game, helper or installed files run.
"""
from pathlib import Path
import argparse
import unittest

from lupa import lua51


DEFAULT_LLL = Path.home() / "OneDrive/Documents/GitHub/DBF-Suite/LLL"
LLL = DEFAULT_LLL


class HostContract(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(encoding=None)
        self.lua.execute(b"""
            ffi=nil;bit=nil;jit=nil
            require=function(name) error('Unavailable native dependency: '..name) end
        """)
        for variable, filename in ((b"LLL_METADATA", "metadata.lua"),
                                   (b"LLL_CONFIG", "config.lua"),
                                   (b"Project", "project.lua")):
            self.lua.globals()[variable] = self.lua.execute((LLL / "src" / filename).read_bytes())
        self.lua.execute(b"""
            disk={
                ['mod/main.lua']='return mod',
                ['mod/palette.dds']='opaque palette bytes',
                ['mod/config/defaults.cfg']='{"ui_scale":100,"enabled":true}'
            }
            calls={read=0,write=0,mkdir=0}; fail_write=false
            platform={native_ffi=false, settings='settings',
                read=function(path,limit)
                    calls.read=calls.read+1
                    local bytes=disk[path]
                    if bytes and #bytes<=limit then return bytes end
                end,
                write=function(path,bytes)
                    calls.write=calls.write+1
                    if fail_write then return false end
                    disk[path]=bytes;return true
                end,
                mkdir=function()calls.mkdir=calls.mkdir+1;return true end
            }
            entry={id='epic_contract',dir='mod'}
            spec={entry='main.lua',defaults='config/defaults.cfg',modules={}}
            function restart()
                return Project.instantiate(platform,entry,Project.snapshot(platform,entry,spec),function()end)
            end
            api=restart()
        """)

    def test_modular_paths_and_bounded_relative_read(self):
        self.lua.execute(b"""
            assert(api.dir=='mod' and api.config_dir=='settings/epic_contract')
            assert(api.config_path=='settings/epic_contract/config.cfg')
            assert(api.read('palette.dds')=='opaque palette bytes')
            for _,path in ipairs({'../palette.dds','/palette.dds','a//b','C:/a','a\\\\b'}) do
                local before=calls.read
                assert(not pcall(api.read,path),'Unsafe path accepted: '..path)
                assert(calls.read==before,'Invalid path reached filesystem')
            end
        """)

    def test_config_roundtrip_retains_unrelated_values(self):
        self.lua.execute(b"""
            local original=api.config
            assert(api.config.ui_scale==100 and api.config.enabled)
            local before=calls.write
            assert(api.set('palette',{slot='armor',rgba='001122ff'}))
            assert(calls.write==before+1,'Save did not issue exactly one write')
            assert(api.config==original,'Config table identity changed')
            api=restart()
            assert(api.config.ui_scale==100 and api.config.enabled)
            assert(api.config.palette.slot=='armor' and api.config.palette.rgba=='001122ff')
            assert(not disk['mod/config/defaults.cfg']:find('rgba',1,true),'Defaults modified')
        """)

    def test_failed_save_does_not_publish_unsaved_config(self):
        self.lua.execute(b"""
            local before=calls.write
            assert(not api.set('palette',function()end))
            assert(calls.write==before and api.config.palette==nil)
            fail_write=true
            assert(not api.set('ui_scale',120))
            assert(api.config.ui_scale==100,'Failed save changed config')
            fail_write=false
            api=restart()
            assert(api.config.ui_scale==100)
        """)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lll-root", type=Path, default=DEFAULT_LLL)
    args, rest = parser.parse_known_args()
    LLL = args.lll_root.resolve()
    if not (LLL / "src/project.lua").is_file():
        parser.error("--lll-root must name the maintained LLL checkout")
    unittest.main(argv=[__file__, *rest])
