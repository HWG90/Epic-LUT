-- Basic's whole-table pattern selector. Native binding ownership stays in the controller.
local C = {}
C.CHOICES = { 'Current / mixed', 'Off', 'Pattern 0', 'Pattern 1', 'Pattern 2', 'Pattern 3', 'Pattern 4', 'Pattern 5' }
local function editable(d)
    return d and d.width == 23 and d.data and d.height >= 1 and d.height <= 64 and not d.stale and not d.read_only
end
function C.available(d)
    return editable(d) == true
end
function C.selection(d)
    if not editable(d) then
        return 1
    end
    local value = d.data[21 * 4 + 3]
    if value ~= value or value < -1 or value > 5 or value % 1 ~= 0 then
        return 1
    end
    for row = 2, d.height do
        if d.data[((row - 1) * 23 + 21) * 4 + 3] ~= value then
            return 1
        end
    end
    return value + 3
end
function C.apply(d, choice)
    assert(editable(d), 'Load a current 23-column material LUT first')
    assert(type(choice) == 'number' and choice % 1 == 0 and choice >= 2 and choice <= 8, 'Choose a camo pattern')
    local value = choice - 3
    for row = 1, d.height do
        d.data[((row - 1) * 23 + 21) * 4 + 3] = value
    end
    d.revision = (d.revision or 0) + 1
    return d.height
end
function C.controls(apply)
    local out = {}
    for _, kind in ipairs({ 'armor', 'helmet' }) do
        local target = kind
        local choices = {}
        for i, label in ipairs(C.CHOICES) do
            choices[i] = label
        end
        out[#out + 1] = {
            id = 'basic_' .. kind .. '_camo',
            type = 'choice',
            presentation = 'dropdown',
            label = (kind == 'armor' and 'Armor' or 'Helmet') .. ' camo pattern',
            choices = choices,
            default = 1,
            description = 'Changes the pattern on every region in this LUT. Stored camo colors, scale and material effects stay as they are. Previews show the pattern mask in neutral colors.',
            on_change = function(value)
                if value > 1 then
                    return apply(target, value)
                end
            end,
        }
    end
    return out
end
function C.thumbnails(atlas)
    if
        not atlas
        or type(atlas.layers) ~= 'table'
        or type(atlas.width) ~= 'number'
        or type(atlas.height) ~= 'number'
        or atlas.width % 1 ~= 0
        or atlas.height % 1 ~= 0
        or atlas.width < 1
        or atlas.width > 16
        or atlas.height < 1
        or atlas.height > 16
    then
        return nil
    end
    local result = {}
    for layer = 1, 6 do
        local mask = atlas.layers[layer]
        if type(mask) ~= 'string' or #mask ~= atlas.width * atlas.height * 4 then
            return nil
        end
        local colors = {}
        -- The texture packs several mask channels; neutral tints distinguish
        -- their regions without pretending to render the armor's full shader.
        for i = 1, #mask, 4 do
            local r, g, b = mask:byte(i, i + 2)
            local value = math.floor(math.min(255, 35 + r * 0.72 + g * 0.42 + b * 0.18))
            colors[#colors + 1] = { value, value, value }
        end
        result[layer + 2] = { width = atlas.width, height = atlas.height, colors = colors }
    end
    return result
end
return C
