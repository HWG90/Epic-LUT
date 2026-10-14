local ffi = require('ffi')
local Quick = dofile('src/editor/weapon_pattern_quick.lua')
local pixels = ffi.new('float[12]', { 1, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0.375 })
local target = { scope_id = 'body-only' }
local state = { pattern_ready = true, pattern_document = { data = pixels }, pattern_target = target }
local selected, opened
local quick = Quick.new({
    state = function()
        return state
    end,
    edit_pattern = function(column, expected)
        selected = { column, expected }
        return true
    end,
    open_pattern = function(expected)
        opened = expected
        return true
    end,
})
for _, scale in ipairs({ 0.7, 1, 1.5 }) do
    local colors, hits, labels = {}, {}, {}
    local ui = {
        theme = { text = { 255, 255, 255 } },
        spacing = function(n)
            return n * scale
        end,
        text_metrics = function(size)
            return { height = size * scale, min_y = -2 * scale }
        end,
        text_width = function(text, size)
            return #text * size * scale * 0.55
        end,
        bounded = function(_, _, text)
            labels[text] = true
        end,
        rect = function(x, y, w, h, color)
            assert(w <= 40 and h <= 40 and x >= 10 and y >= 20, 'Quick swatches escaped their table-sized bounds')
            colors[#colors + 1] = color
        end,
        hit = function(_, _, _, _, callback, _, _, label)
            hits[label] = callback
        end,
    }
    local bounds = { x = 10, y = 20, w = 360, h = quick.quick_height(ui, 28), cell_width = 28, row_height = 28 }
    quick.quick(ui, bounds)
    assert(labels['Quick Editor: Pattern LUT'] and labels.Color and labels['Mat/Opac'] and labels.Roughness)
    assert(
        #colors == 3 and colors[3][1] == 96 and colors[3][2] == 96 and colors[3][3] == 96,
        'Roughness swatch used unknown RGB instead of Alpha'
    )
    assert(hits.Roughness() and selected[1] == 3 and selected[2] == target, 'Quick picker lost its companion subset')
    state.pattern_ready = false
    hits = {}
    quick.quick(ui, bounds)
    assert(next(hits) == nil, 'Unavailable Pattern exposed a picker')
    state.pattern_ready = true
end
assert(quick.show() and opened == target, 'Pattern button did not open the selected companion')
print('PASS weapon Pattern quick controls: table-sized swatches, labels, Alpha roughness and exact companion routing')
