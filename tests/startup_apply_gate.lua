local ffi = require('ffi')
local Core = dofile(assert(os.getenv('MCM_SOURCE_DIR')) .. '/src/core.lua')
DBFMCM = Core.new()
ModOptionsMenu = nil
local data = ffi.new('float[?]', 23 * 4)
local ready = false
local applies = 0
local clock = 0
local identity = { player = 1, avatar = 2, armor = 123, helmet = 234, body = 0, units_at = 100 }
local memory = {
    verify_build = function()
        return true
    end,
    module = function()
        return 65536
    end,
    address = function(a)
        return a
    end,
    time = function()
        clock = clock + 0.002
        return clock
    end,
}
local m = {
    presets = dofile('src/presets.lua'),
    palette = dofile('src/palette.lua'),
    bingus_runtime = {},
    bingus_memory = {
        new = function()
            return memory
        end,
    },
    engine = {
        open = function()
            return {
                alive = function()
                    return 1
                end,
            }
        end,
    },
    avatar = {
        reader = function()
            return function() end
        end,
        resolve = function()
            return identity
        end,
        units = function()
            return { { unit = 1, type = 0, slot = 2 } }
        end,
    },
    catalog = {
        new = function(_, _, _, target)
            return {
                close = function() end,
                load = function(id, yield)
                    if target == 'Helmet' then
                        while not ready do
                            yield()
                        end
                    end
                    return {
                        identity = id,
                        pieces = {},
                        luts = {
                            { name = '0123456789abcdef', width = 23, height = 1, values = data },
                        },
                    }
                end,
            }
        end,
    },
    session = {
        new = function()
            return {
                bindings = {},
                restore = function()
                    return true
                end,
                capture = function() end,
                apply = function()
                    applies = applies + 1
                end,
            }
        end,
    },
}
local file = assert(io.open('src/editor.lua'))
local source = file:read('*a')
file:close()
local editor = assert(loadstring('local m=...\n' .. source))(m)
local ctx = { log = function() end, dir = 'tests/tmp', on_cleanup = function() end }
editor.on_enable(ctx)
editor.on_update(ctx, 0.016)
local h = assert(DBFMCM.mods.dbf_armor_lut_0000007b_0).handle
assert(h.set('0123456789abcdef_r1_color', '#123456'))
editor.on_update(ctx, 0.016)
assert(applies == 0, 'Saved edits applied while helmet discovery was pending')
ready = true
editor.on_update(ctx, 0.016)
editor.on_update(ctx, 0.016)
assert(applies == 1, 'Queued edit did not apply after both catalogues became ready')
assert(editor.on_disable(ctx))
local captures = 0
m.diagnostic_discovery_only = true
m.session.new = function()
    return {
        bindings = {},
        restore = function()
            return true
        end,
        capture = function()
            captures = captures + 1
        end,
        apply = function()
            error('Diagnostic must not apply native textures')
        end,
    }
end
editor.on_enable(ctx)
editor.on_update(ctx, 0.016)
editor.on_update(ctx, 0.016)
local diagnostic_handle = assert(DBFMCM.mods.dbf_armor_lut_0000007b_0).handle
assert(diagnostic_handle.set('0123456789abcdef_r1_color', '#654321'))
editor.on_update(ctx, 0.016)
assert(captures == 0, 'Discovery-only diagnostic captured native bindings')
assert(editor.on_disable(ctx))
print('PASS application waits for both catalogues; discovery-only registers controls without native capture or writes')
m.diagnostic_without_menu = true
m.frontend = {
    new = function()
        error('No-menu diagnostic initialized frontend')
    end,
}
m.editor_features = {
    new = function()
        error('No-menu diagnostic initialized editing features')
    end,
}
m.provider_menu = {
    new = function()
        error('No-menu diagnostic initialized provider menu')
    end,
}
editor.on_enable(ctx)
editor.on_update(ctx, 0.016)
editor.on_update(ctx, 0.016)
assert(package.loaded['dbf.armor_lut_editor.owner.v1'].result, 'No-menu diagnostic skipped armor discovery')
assert(package.loaded['dbf.helmet_lut_editor.owner.v1'].result, 'No-menu diagnostic skipped helmet discovery')
assert(not DBFMCM.mods.dbf_armor_lut_0000007b_0, 'No-menu diagnostic registered controls')
assert(captures == 0)
assert(editor.on_disable(ctx))
print('PASS no-menu diagnostic discovers both catalogs without frontend, features, provider menu, or binding capture')
