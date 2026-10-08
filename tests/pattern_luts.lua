local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local source = { width = 3, height = 1, data = ffi.new('float[12]') }
for i = 0, 11 do
    source.data[i] = i / 10
end
source.data[3], source.data[11] = 2.75, -0.25
local current, created, writes = 100, 200, 0
local binding = { unit = 1, mesh = 2, material = 3, helmet = true, slot = 987, save_key = '0:0:0:0' }
local deps = {
    present = function()
        return true
    end,
    binding = function(b)
        assert(b.slot == 987)
        return current
    end,
    key = function()
        return 'pattern'
    end,
    retain = { records = {}, cache = {}, bytes = 0 },
    create_texture = function(w, h, data)
        assert(w == 3 and h == 1)
        created = created + 1
        return { object = created }
    end,
    bind = function(b, object)
        assert(b.slot == 987, 'Pattern wrote into the material LUT slot')
        current = object
        writes = writes + 1
    end,
}
local session = dofile('src/gear/binding_session.lua').new(deps)
local exported
local pattern = dofile('src/editor/pattern_luts.lua').new({
    session = session,
    key = deps.key,
    binding = deps.binding,
    discover = function()
        return { binding }
    end,
    original = function(object)
        assert(object == 100)
        return source
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    swatch = dofile('src/core/palette.lua').swatch,
    note = function(text)
        return text
    end,
    resource_id = function()
        return '[0x123]'
    end,
    export = function(name, document)
        exported = { name = name, pixels = ffi.string(document.data, 48) }
    end,
})
local handle = api.register({
    id = 'patterns',
    name = 'Patterns',
    pages = {
        {
            id = 'advanced',
            name = 'Material',
            controls = (function()
                local list = pattern.controls()
                list[#list + 1] = { id = 'show_alpha', type = 'toggle', label = 'Show Alpha', default = false }
                return list
            end)(),
        },
    },
})
pattern.attach(handle, api.mods.patterns.controls)
pattern.gear = 'helmet'
assert(handle.activate('pattern_load'))
assert(writes == 0, 'Loading original pattern changed native binding')
assert(handle.set('pattern_color', '#FF0000'))
assert(pattern.document.data[0] == 1 and pattern.document.data[1] == 0 and pattern.document.data[2] == 0)
assert(pattern.document.data[3] == 2.75 and pattern.document.data[11] == -0.25, 'Color edit changed unknown channels')
assert(handle.set('pattern_opacity', 0.4))
assert(math.abs(pattern.document.data[7] - 0.4) < 0.00001)
assert(handle.activate('pattern_undo'))
assert(pattern.document.data[7] == source.data[7])
assert(handle.activate('pattern_redo'))
assert(math.abs(pattern.document.data[7] - 0.4) < 0.00001)
local imported = { width = 3, height = 1, data = ffi.new('float[12]') }
imported.data[0], imported.data[7] = 0.25, 0.8
local before_import = current
assert(pattern.import(imported))
assert(current == before_import, 'Import applied before explicit button')
assert(handle.activate('pattern_import_apply'))
assert(pattern.document.data[0] == imported.data[0] and pattern.document.data[7] == imported.data[7])
assert(handle.activate('pattern_export'))
assert(exported and #exported.pixels == 48)
assert(pattern.close() and current == 100)
pattern.gear = 'helmet'
assert(handle.activate('pattern_load'))
assert(handle.set('pattern_color', '#00FF00'))
current = 999 -- A competing mod now owns the binding.
assert(pattern.close() and current == 999, 'Pattern restore overwrote a foreign binding')
print(
    'PASS Pattern LUTs: separate native slot, 3x1 values, unknown-channel preservation, undo/redo, export and foreign ownership'
)

pattern.show('helmet')
local palette = dofile('src/core/palette.lua')
local rects, labels = {}, {}
local ui = {
    rect = function(x, y, w, h, c)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h, c = c }
    end,
    bounded = function(x, y, text)
        labels[text] = true
    end,
    hit = function() end,
    choice = function() end,
    number = function() end,
    activate = function() end,
    floating = function(id, draw, w, h, close)
        assert(id == 'pattern_lut_editor')
        draw(0, 0, w, h)
    end,
}
pattern.popup(ui)
assert(
    labels['Pattern LUT Editor']
        and labels['1: Accent color']
        and labels['2: Material / opacity']
        and labels['3: Unknown']
)
local unchanged = ffi.string(pattern.document.data, 48)
assert(handle.set('show_alpha', true))
pattern.popup(ui)
assert(ffi.string(pattern.document.data, 48) == unchanged, 'Show Alpha changed LUT values')
local samples = {}
local display = {
    rect = function(x, y, w, h, c)
        samples[#samples + 1] = c
    end,
}
palette.swatch(display, 0, 0, 10, 10, { 255, 0, 0 }, 0, true)
assert(#samples == 4 and samples[1][1] == 220 and samples[2][1] == 125, 'Transparent swatch does not show checkerboard')
samples = {}
palette.swatch(display, 0, 0, 10, 10, { 255, 0, 0 }, 1, true)
assert(#samples == 1 and samples[1][1] == 255, 'Opaque swatch was checkerboard')

pattern.column = 2
local picker = api.mods.patterns.controls.pattern_picker
assert(picker.picker_commit({255,0,0},.6))
assert(pattern.document.data[4] == 1 and math.abs(pattern.document.data[7]-.6)<.00001)
assert(picker.picker_alpha() == tonumber(pattern.document.data[7]))
assert(handle.activate('pattern_undo'))

current = binding.original -- Simulate the game resetting an already-edited pattern to its original.
assert(api.mods.patterns.controls.pattern_picker.picker_commit({0,0,255},1))
assert(current ~= binding.original,'Known original reset prevented Use Color')
current = 123456 -- A different writer owns this slot now.
assert(not pcall(api.mods.patterns.controls.pattern_picker.picker_commit,{255,0,255},1),'Unexpected binding was overwritten')
assert(current == 123456)

-- Armor/Helmet switching must clear unavailable values and finish an async load.
local ready_helmet = false
local armor_pixels,helmet_pixels=ffi.new('float[12]'),ffi.new('float[12]')
armor_pixels[0],helmet_pixels[0]=.1,.8
local tab_pattern = dofile('src/editor/pattern_luts.lua').new({
    session={owned={},restore=function() return true end},
    key=function(b) return b.material end,binding=function(b) return b.material end,
    discover=function() return {{material=400,armor=true,helmet=false},{material=500,armor=false,helmet=true}} end,
    original=function(object)
        if object==500 and not ready_helmet then return nil end
        return {width=3,height=1,data=object==400 and armor_pixels or helmet_pixels}
    end,
    resource_id=function(object) return '['..object..']' end,
    rgb=dofile('src/core/palette.lua').rgb, note=function(t) return t end,
})

local tabs_handle=api.register({id='pattern_tabs_test',name='Tabs',pages={{id='p',name='Patterns',controls=tab_pattern.controls()}}})
tab_pattern.attach(tabs_handle,api.mods.pattern_tabs_test.controls)
assert(tab_pattern.switch('armor'))
assert(math.abs(tab_pattern.document.data[0]-.1)<.00001)
assert(tab_pattern.switch('helmet'))
assert(tab_pattern.document==nil and tab_pattern.waiting,'Old Armor values remained visible while Helmet was loading')
ready_helmet=true
tab_pattern.tick(.3)
assert(tab_pattern.gear=='helmet' and math.abs(tab_pattern.document.data[0]-.8)<.00001)
assert(tab_pattern.switch('armor') and math.abs(tab_pattern.document.data[0]-.1)<.00001)

-- Clicking Flash again must snapshot the restored binding, never the previous magenta texture.
current=100
local indicator=dofile('src/gear/region_indicator.lua').new({present=deps.present,binding=deps.binding,apply=session.apply,bind=deps.bind})
local flashing=dofile('src/editor/pattern_luts.lua').new({session=session,indicator=indicator,key=deps.key,binding=deps.binding,
    discover=function() return {binding} end,original=function() return source end,
    rgb=dofile('src/core/palette.lua').rgb,note=function(t) return t end,resource_id=function() return '[pattern]' end})
local fh=api.register({id='pattern_flash_test',name='Flash',pages={{id='p',name='Pattern',controls=flashing.controls()}}})
flashing.attach(fh,api.mods.pattern_flash_test.controls)
flashing.show('helmet')
flashing.flash()
assert(current~=100)
flashing.flash()
assert(current~=100)
flashing.tick(4.1)
assert(current==100 and not flashing.flashing(),'Repeated Flash captured magenta as its restore target')

current=100
pattern.show('helmet')
local pcontrol=api.mods.patterns.controls.pattern_picker
local old_pixels=ffi.string(pattern.document.data,48)
pcontrol.picker_begin();pcontrol.picker_preview({1,99,201},.5)
assert(ffi.string(pattern.document.data,48)~=old_pixels)
pcontrol.picker_end(false)
assert(ffi.string(pattern.document.data,48)==old_pixels,'Pattern picker cancel did not restore its values')
