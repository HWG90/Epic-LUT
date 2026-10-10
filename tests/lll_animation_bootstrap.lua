-- Execute generated main.lua through the actual LLL private project loader.
LLL_METADATA = {}
LLL_CONFIG = {
    serialize = function()
        return '{}'
    end,
}
local Project = dofile('../DBF-Suite/LLL/src/project.lua')
local root = assert(os.getenv('EPIC_LUT_MODULAR_TEST_DIR'))
local inv_file = assert(io.open(root .. '/modules.txt', 'rb'))
local module_paths = {}
for path in inv_file:lines() do
    module_paths[#module_paths + 1] = path:gsub('\r$', '')
end
inv_file:close()
local old_m, old_gate = _G.m, _G.PREVIEW_ANIMATION_ENABLED
_G.m, _G.PREVIEW_ANIMATION_ENABLED = { foreign = true }, true
local foreign_m = _G.m
local function run(mode, enabled)
    local source = assert(io.open(root .. '/' .. mode .. '-main.lua', 'rb'))
    local main = source:read('*a')
    source:close()
    local fixture = { starts = 0 }
    local registry = {
        ['dbf.epic_lut.frontend.v1'] = {
            menu = { visible = false },
            input = {
                focused = function()
                    return true
                end,
            },
        },
    }
    fixture.environment = {
        io = {
            open = function()
                return nil
            end,
        },
        os = {
            getenv = function()
                return 'fixture'
            end,
            remove = function() end,
        },
        package = { loaded = registry },
        stingray = { Gui = {
            resolution = function()
                return 1920, 1080
            end,
        } },
    }
    fixture['src/editor/direct_editor.lua'] = {
        on_enable = function() end,
        on_update = function() end,
        on_disable = function()
            return true
        end,
        on_cleanup_poll = function()
            return true
        end,
    }
    fixture['vendor/bingus_memory.lua'] = {
        new = function()
            return {
                module = function()
                    return 100000
                end,
                address = function(v)
                    return v
                end,
                time = function()
                    return 0
                end,
            }
        end,
    }
    fixture['vendor/engine.lua'] = {
        open = function()
            return {}
        end,
    }
    fixture['src/preview/player_preview_submit.lua'] = {
        new = function()
            return function() end
        end,
    }
    fixture['src/preview/player_preview_controls.lua'] = dofile('src/preview/player_preview_controls.lua')
    fixture['src/preview/player_preview.lua'] = dofile('src/preview/player_preview.lua')
    fixture['src/preview/player_preview_native.lua'] = {
        new = function(_, m, host)
            assert(
                host.animate == enabled and host.authored == enabled,
                'Generated modular gate never reached the native adapter'
            )
            assert(m.preview_animation == (enabled and 'authored_salute' or 'disabled'))
            assert((host.animation_source ~= nil) == enabled)
            fixture.metadata = m
            return {
                quiesce = function()
                    return true
                end,
            }
        end,
    }
    fixture['src/preview/player_authored_source.lua'] = {
        new = function()
            return {
                start = function()
                    fixture.starts = fixture.starts + 1
                end,
                tick = function() end,
                get = function()
                    return {}
                end,
                close = function()
                    return true
                end,
            }
        end,
    }
    _G.EPIC_BOOTSTRAP_FIXTURE = fixture
    local snapshot = { spec = { entry = 'main.lua', retain_until_exit = true }, defaults = {}, user = {}, chunks = {} }
    snapshot.chunks['main.lua'] = assert(loadstring(main))
    for _, path in ipairs(module_paths) do
        if path == 'src/preview/player_preview_candidate.lua' then
            snapshot.chunks[path] = assert(loadfile('src/preview/player_preview_candidate.lua'))
        else
            snapshot.chunks[path] = assert(
                loadstring(
                    'for key,value in pairs(EPIC_BOOTSTRAP_FIXTURE.environment)do mod.scope[key]=value end\n'
                        .. 'return EPIC_BOOTSTRAP_FIXTURE['
                        .. string.format('%q', path)
                        .. '] or {}'
                )
            )
        end
    end
    local definition, api = Project.instantiate({
        read = function()
            return '#'
        end,
    }, { id = 'armor_lut_editor', dir = 'fixture', metadata = { name = 'Epic LUT' } }, snapshot, function() end)
    assert(api.scope.PREVIEW_ANIMATION_ENABLED == enabled and api.scope.m ~= foreign_m)
    definition.on_enable({ log = function() end, on_cleanup = function() end })
    assert(fixture.starts == (enabled and 1 or 0), 'Authored worker startup differs from modular build mode')
    assert(definition.on_disable())
    assert(_G.m == foreign_m and _G.PREVIEW_ANIMATION_ENABLED == true, 'Modular bootstrap changed global flags')
    return api.scope.m
end
local animated = run('animation', true)
local static = run('static', false)
assert(
    animated ~= static and animated.preview_animation == 'authored_salute' and static.preview_animation == 'disabled'
)
_G.EPIC_BOOTSTRAP_FIXTURE = nil
_G.m, _G.PREVIEW_ANIMATION_ENABLED = old_m, old_gate
print(
    'PASS actual modular bootstrap: private authored/static gates, native host, worker startup and isolated instances'
)
