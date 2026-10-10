-- All retained GUI surfaces draw and measure one frozen font descriptor.
local View = dofile('vendor/menu/view.lua')
local debug_font = 'core/performance_hud/debug'
local face = { font = '1234567890abcdef', material = '234567890abcdef1', atlas = '34567890abcdef12' }
local descriptor, frame, next_gui, next_id = face, 1, 0, 0
local failure, fail_newer_than, bind_attempts = nil, nil, 0
local live_world, width, height = {}, 1920, 1080
local texts, bindings, measures, destroyed, resolutions = {}, {}, {}, 0, 0
local function hex(value)
    if type(value) == 'string' then
        return value
    end
    assert(value.frame == frame, 'ID retained across frames')
    return value.hex
end
local function id()
    next_id = next_id + 1
    return next_id
end
local sr = {
    Application = {
        main_world = function()
            return live_world
        end,
        worlds = function()
            return { live_world }
        end,
    },
    IdString64 = {
        from_hex = function(value)
            return { hex = value, frame = frame }
        end,
    },
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Color = function(...)
        return { ... }
    end,
    World = {
        create_screen_gui = function(world)
            next_gui = next_gui + 1
            return { serial = next_gui, world = world }
        end,
        destroy_gui = function(_, gui)
            assert(gui.world == live_world)
            destroyed = destroyed + 1
        end,
    },
    Material = {
        set_texture = function(handle, slot, atlas)
            if failure == 'texture_throw' then
                error('texture unavailable')
            end
            if failure == 'texture_false' then
                return false
            end
            assert(handle.gui.world == live_world, 'Mutated material outside owned live GUI')
            assert(hex(slot) == '88BAC99B00000000' and hex(atlas) == face.atlas, 'Wrong game font atlas binding')
            bindings[handle.gui.serial] = hex(atlas)
        end,
    },
    Gui = {
        resolution = function()
            return width, height
        end,
        material = function(gui, material)
            bind_attempts = bind_attempts + 1
            if failure == 'material_throw' then
                error('material unavailable')
            end
            if failure == 'material_nil' or (fail_newer_than and gui.serial > fail_newer_than) then
                return nil
            end
            assert(gui.world == live_world and hex(material) == face.material, 'Wrong GUI font material')
            return { gui = gui }
        end,
        rect = id,
        text = function(gui, label, font, size, material)
            font, material = hex(font), hex(material)
            if font == face.font then
                assert(
                    material == face.material and bindings[gui.serial] == face.atlas,
                    'Text drew without its owned atlas'
                )
            end
            texts[#texts + 1] = { gui = gui.serial, font = font, text = label, material = material }
            return id()
        end,
        text_extents = function(gui, label, font, size)
            font = hex(font)
            measures[#measures + 1] = font
            assert(gui.world == live_world, 'Measured dead GUI')
            local scale = font == face.font and 0.45 or 0.7
            return { x = 0, y = -0.2 * size }, { x = #label * size * scale, y = 0.7 * size }
        end,
        destroy_text = function()
            destroyed = destroyed + 1
        end,
        destroy_rect = function()
            destroyed = destroyed + 1
        end,
    },
}
local view = View.new(sr)
local source = {
    resolve = function()
        resolutions = resolutions + 1
        return descriptor
    end,
}
view.set_font_source(source)
assert(not view.refresh_font() and view.font_key == debug_font, 'Game face accepted before owned GUI was ready')
local commands = {
    { type = 'text', text = 'Menu', x = 1, y = 1, size = 12, a = 1, c = { 255, 255, 255 } },
    { type = 'text', text = 'Popup', x = 1, y = 1, size = 12, a = 1, c = { 255, 255, 255 }, popup = true },
    { type = 'text', text = 'Preview', x = 1, y = 1, size = 12, a = 1, c = { 255, 255, 255 }, hud_preview = true },
}
view.draw(commands)
assert(#texts == 3 and next_gui == 3, 'Three GUI surfaces were not rendered')
for _, text in ipairs(texts) do
    assert(text.font == debug_font, 'Cold first paint mixed game metrics and stock text')
end
local metric_key = view.metric_key
assert(
    view.refresh_font() and view.metric_key ~= metric_key and view.font_key:find(face.font, 1, true),
    'Warm owned GUI did not adopt verified font'
)
texts = {}
view.draw(commands)
for _, text in ipairs(texts) do
    assert(text.font == face.font, 'Child GUI did not share main font')
end
assert(math.abs(view.measure('F', 20) - 9) < 0.001, 'Measured different face than rendered')
local m = view.text_metrics(20, 'Ag0#')
assert(m.min_y == -4 and m.max_y == 14, 'Game font bearings unavailable')
local cached = #measures
assert(view.measure('F', 20) == 9 and #measures == cached, 'Same font metric cache missed')
frame = 2
assert(not view.refresh_font(), 'Unchanged warm descriptor invalidated GUI')
texts = {}
view.draw(commands)
assert(#texts == 0, 'Unchanged font recreated retained primitives')
-- Descriptor changes only at explicit frame boundary, not within draw/layout.
descriptor = nil
view.draw(commands)
assert(resolutions == 3 and view.measure('F', 20) == 9, 'Draw refreshed font during a composed frame')
assert(view.refresh_font() and view.font_key == debug_font, 'Unavailable game face did not fall back')
texts = {}
view.draw(commands)
assert(#texts == 3 and texts[1].font == debug_font, 'Fallback retained old native text')
assert(math.abs(view.measure('F', 20) - 14) < 0.001, 'Fallback retained game glyph width')
width, height = 0, 0
descriptor = face
local before = resolutions
local before_measures = #measures
assert(not view.refresh_font() and resolutions == before, 'Minimized view resolved native font')
view.measure('new glyph', 20)
assert(#measures == before_measures, 'Minimized view called native text measurement')
width, height = 1920, 1080
frame = 3
assert(view.refresh_font(), 'Game face did not return after valid dimensions')
live_world = {}
texts = {}
view.draw(commands)
assert(#texts == 3 and next_gui == 6, 'World transition retained stale GUI font handles')
assert(math.abs(view.measure('F', 20) - 9) < 0.001, 'New world did not recover metrics')
-- Explicit stock-font commands keep their specified face/material.
view.draw({
    {
        type = 'text',
        text = 'Explicit',
        x = 1,
        y = 1,
        size = 12,
        a = 1,
        c = { 255, 255, 255 },
        font_resource = 'explicit/font',
        font_material = 'explicit/material',
    },
})
assert(
    texts[#texts].font == 'explicit/font' and texts[#texts].material == 'explicit/material',
    'Explicit font override was lost'
)
view.release()
-- Binding APIs may be present while the owned GUI's material is unavailable.
-- Fallback occurs before the next composition and never closes the menu.
for _, mode in ipairs({ 'material_nil', 'material_throw', 'texture_throw', 'texture_false' }) do
    failure = nil
    view.set_font_source(source)
    view.draw(commands)
    view.refresh_font()
    view.draw(commands)
    failure = mode
    assert(
        view.refresh_font() and view.font_key == debug_font,
        'Binding failure did not fall back before composing: ' .. mode
    )
    local attempts = bind_attempts
    assert(not view.refresh_font() and bind_attempts == attempts, 'Failed descriptor was retried every frame')
    texts = {}
    view.draw(commands)
    for _, text in ipairs(texts) do
        assert(text.font == debug_font, 'Failed binding mixed drawn and measured faces')
    end
end
failure = nil
view.release()
-- Opening a new popup can introduce a GUI after the frame's font is frozen.
-- Defer that paint on failure, then switch all surfaces together next frame.
local other = View.new(sr)
other.set_font_source(source)
other.refresh_font()
local single = { commands[1] }
other.draw(single)
assert(other.refresh_font())
other.draw(single)
fail_newer_than = next_gui
texts = {}
other.draw({ commands[1], commands[2] })
assert(#texts == 0, 'New GUI binding failure painted mixed-face content')
assert(other.refresh_font() and other.font_key == debug_font, 'New child failure did not propagate stock fallback')
other.draw({ commands[1], commands[2] })
assert(#texts == 2 and texts[1].font == debug_font and texts[2].font == debug_font, 'Shared fallback missed main/popup')
fail_newer_than = nil
other.release()
print(
    'PASS font rendering: frozen face/metrics, owned per-GUI atlas, temporary IDs, caches, fallback, explicit overrides and world/minimize lifecycle'
)
