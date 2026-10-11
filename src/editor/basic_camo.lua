-- Basic's checked-region camo recipes. Native ownership stays in the controller.
local C = {}
C.CHOICES = { 'Current / mixed', 'Off', 'Pattern 0', 'Pattern 1', 'Pattern 2', 'Pattern 3', 'Pattern 4', 'Pattern 5' }
-- Generated RGB palettes with camo controls verified against weapon schemes.
-- MYC copies C17-C20 RGBA, C21 A, C22 RGBA and C23 A as one camo recipe.
-- C22 B is camo UV scale; C23 A blends roughness (zero is valid for Desert).
C.COLORWAYS = {
    {
        name = 'Jungle',
        colors = { '64744C', '3E4B2D', '8B7551', '242A20' },
        mask = { 216.625, -0.98974609375, 2, 3 },
        blend = 0.82958984375,
    },
    {
        name = 'Desert',
        colors = { 'C9B98B', 'AB9366', '826A45', '544735' },
        mask = { 216.625, -0.98974609375, 3.5, 1 },
        blend = 0,
    },
    {
        name = 'Urban',
        colors = { 'B0B5B1', '7D8581', '505955', '29312E' },
        mask = { 216.625, -1, 1.19921875, 1 },
        blend = 0.82958984375,
    },
    {
        name = 'Arctic',
        colors = { 'EDF0E8', 'C3CBC8', '8C9B9A', '536368' },
        mask = { 216.625, -0.98974609375, 5, 3 },
        blend = 0.82958984375,
    },
}
local camo_alpha = { 0.52978515625, 2, -1, 4 }
local function nonzero(value)
    return type(value) == 'number' and value == value and value ~= 0 and math.abs(value) < math.huge
end
local function ready(data, offset)
    return nonzero(data[offset + 21 * 4]) and nonzero(data[offset + 21 * 4 + 2])
end
local function active(data, offset)
    local mask = data[offset + 21 * 4 + 3]
    return ready(data, offset) and mask >= 0 and mask <= 5 and mask % 1 == 0
end
local function rgb(value)
    if type(value) == 'table' then
        local r, g, b = value[1], value[2], value[3]
        for _, n in ipairs({ r, g, b }) do
            assert(type(n) == 'number' and n >= 0 and n <= 255 and n % 1 == 0, 'Use RGB integers 0-255')
        end
        assert(r and g and b, 'Choose three camo color channels')
        return { r / 255, g / 255, b / 255 }
    end
    assert(type(value) == 'string', 'Choose a camo color')
    local hex = value:gsub('^#', '')
    assert(#hex == 6 and hex:match('^%x+$'), 'Use six HEX digits')
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
local function editable(d)
    return d and d.width == 23 and d.data and d.height >= 1 and d.height <= 64 and not d.stale and not d.read_only
end
local function camo_row(kind, row)
    return kind ~= 'helmet' or row ~= 8
end
local function selected_rows(d, kind, rows)
    if rows ~= nil then
        assert(type(rows) == 'table', 'Choose a Camo region map')
        for row, checked in next, rows do
            assert(
                type(row) == 'number' and row % 1 == 0 and row >= 1 and row <= d.height,
                'Camo region must be an integer within this LUT'
            )
            assert(type(checked) == 'boolean', 'Camo region choices must be true or false')
        end
    end
    local selected = {}
    for row = 1, d.height do
        -- Explicit checkboxes override the legacy Helmet Region 8 default.
        if (rows ~= nil and rawget(rows, row) == true) or (rows == nil and camo_row(kind, row)) then
            selected[#selected + 1] = row
        end
    end
    return selected
end
local function recipe(data, offset, palette, include_colors)
    for color = 1, 4 do
        local at = offset + (15 + color) * 4
        if include_colors then
            local values = rgb(palette.colors[color])
            for channel = 0, 2 do
                data[at + channel] = values[channel + 1]
            end
        end
        data[at + 3] = camo_alpha[color]
    end
    data[offset + 20 * 4 + 3] = 0.8896484375
    for channel = 0, 2 do
        data[offset + 21 * 4 + channel] = palette.mask[channel + 1]
    end
    data[offset + 22 * 4 + 3] = palette.blend
end
local function recipe_matches(data, offset, palette)
    if
        not active(data, offset)
        or data[offset + 20 * 4 + 3] ~= 0.8896484375
        or data[offset + 22 * 4 + 3] ~= palette.blend
    then
        return false
    end
    for color = 1, 4 do
        if data[offset + (15 + color) * 4 + 3] ~= camo_alpha[color] then
            return false
        end
    end
    for channel = 0, 2 do
        if data[offset + 21 * 4 + channel] ~= palette.mask[channel + 1] then
            return false
        end
    end
    return true
end
local function black_colors(data, offset)
    for color = 1, 4 do
        for channel = 0, 2 do
            if data[offset + (15 + color) * 4 + channel] ~= 0 then
                return false
            end
        end
    end
    return true
end
function C.available(d)
    return editable(d) == true
end
function C.selection(d, kind, rows)
    if not editable(d) then
        return 1
    end
    local selected = selected_rows(d, kind, rows)
    if #selected == 0 then
        return 1
    end
    local value = d.data[((selected[1] - 1) * 23 + 21) * 4 + 3]
    if value ~= value or value < -1 or value > 5 or value % 1 ~= 0 then
        return 1
    end
    for _, row in ipairs(selected) do
        local offset = (row - 1) * 23 * 4
        if
            d.data[offset + 21 * 4 + 3] ~= value
            or (value >= 0 and (not ready(d.data, offset) or black_colors(d.data, offset)))
        then
            return 1
        end
    end
    return value + 3
end
function C.color(d, index, rows)
    assert(type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= 4, 'Choose Camo color 1-4')
    if not editable(d) then
        return '#000000'
    end
    local selected = selected_rows(d, nil, rows)
    if #selected == 0 then
        return '#000000'
    end
    local offset = (selected[1] - 1) * 23 * 4
    local values = {}
    for channel = 0, 2 do
        local value = tonumber(d.data[offset + (15 + index) * 4 + channel])
        value = value == value and math.max(0, math.min(1, value)) or 0
        values[#values + 1] = math.floor(value * 255 + 0.5)
    end
    return string.format('#%02X%02X%02X', values[1], values[2], values[3])
end
function C.colorway_selection(d, kind, rows)
    if editable(d) then
        local selected = selected_rows(d, kind, rows)
        if #selected == 0 then
            return 1
        end
        for index, palette in ipairs(C.COLORWAYS) do
            local matches = true
            for color, hex in ipairs(palette.colors) do
                local expected = rgb(hex)
                for _, row in ipairs(selected) do
                    if not recipe_matches(d.data, (row - 1) * 23 * 4, palette) then
                        matches = false
                    end
                    for channel = 0, 2 do
                        local value = tonumber(d.data[((row - 1) * 23 + 15 + color) * 4 + channel])
                        if value ~= value or math.abs(value - expected[channel + 1]) > 0.0000001 then
                            matches = false
                        end
                    end
                end
            end
            if matches then
                return index + 1
            end
        end
    end
    return 1
end
function C.apply(d, choice, mode, index, kind, rows)
    assert(editable(d), 'Load a current 23-column material LUT first')
    local selected = selected_rows(d, kind, rows)
    assert(#selected > 0, 'Select at least one Camo region')
    local colors, label, palette
    if mode == 'colorway' then
        assert(type(choice) == 'number' and choice % 1 == 0 and C.COLORWAYS[choice - 1], 'Choose a camo colorway')
        palette = C.COLORWAYS[choice - 1]
        colors, label = {}, palette.name .. ' colorway'
        for color, hex in ipairs(palette.colors) do
            colors[color] = rgb(hex)
        end
    elseif mode == 'color' then
        assert(type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= 4, 'Choose Camo color 1-4')
        colors, label = { [index] = rgb(choice) }, 'Camo color ' .. index
    else
        assert(
            mode == nil and type(choice) == 'number' and choice % 1 == 0 and choice >= 2 and choice <= 8,
            'Choose a camo pattern'
        )
        local value = choice - 3
        label = C.CHOICES[choice]
        for _, row in ipairs(selected) do
            local offset = (row - 1) * 23 * 4
            if value >= 0 then
                local black = black_colors(d.data, offset)
                if not ready(d.data, offset) or black then
                    recipe(d.data, offset, C.COLORWAYS[1], black)
                end
            end
            d.data[offset + 21 * 4 + 3] = value
        end
        if rows == nil and kind == 'helmet' and d.height >= 8 then
            d.data[(7 * 23 + 21) * 4 + 3] = -1
        end
    end
    if colors then
        if palette then
            for _, row in ipairs(selected) do
                local offset = (row - 1) * 23 * 4
                local mask = active(d.data, offset) and d.data[offset + 21 * 4 + 3] or palette.mask[4]
                recipe(d.data, offset, palette, false)
                d.data[offset + 21 * 4 + 3] = mask
            end
        end
        for color, values in pairs(colors) do
            for _, row in ipairs(selected) do
                local at = ((row - 1) * 23 + 15 + color) * 4
                for channel = 0, 2 do
                    d.data[at + channel] = values[channel + 1]
                end
            end
        end
    end
    d.revision = (d.revision or 0) + 1
    return #selected, label
end
function C.controls(apply)
    local out = {}
    for _, kind in ipairs({ 'armor', 'helmet' }) do
        local target = kind
        local scope = 'checked Camo regions'
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
            description = 'Changes the pattern on '
                .. scope
                .. ' in this LUT.'
                .. ' Check at least one Camo region first. Initializes dormant camo so the pattern can show. Existing working camo settings are kept. Previews show the pattern mask in neutral colors.',
            on_change = function(value)
                if value > 1 then
                    return apply(target, value)
                end
            end,
        }
    end
    for _, kind in ipairs({ 'armor', 'helmet' }) do
        local target = kind
        local scope = 'checked Camo regions'
        local choices = { 'Current / custom' }
        for _, palette in ipairs(C.COLORWAYS) do
            choices[#choices + 1] = palette.name
        end
        out[#out + 1] = {
            id = 'basic_' .. kind .. '_camo_colorway',
            type = 'choice',
            presentation = 'dropdown',
            label = (kind == 'armor' and 'Armor' or 'Helmet') .. ' camo colorway',
            choices = choices,
            default = 1,
            description = 'Generated Jungle, Desert, Urban and Arctic palettes with weapon camo settings. Applies colors and a complete camo setup to '
                .. scope
                .. ' in this LUT; keeps an existing active pattern. Check at least one Camo region first.',
            on_change = function(value)
                if value > 1 then
                    return apply(target, value, 'colorway')
                end
            end,
        }
        for color = 1, 4 do
            local selected = color
            out[#out + 1] = {
                id = 'basic_' .. kind .. '_camo_color_' .. color,
                type = 'color',
                default = '#000000',
                label = (kind == 'armor' and 'Armor' or 'Helmet') .. ' Camo color ' .. color,
                picker_mode = 1,
                description = 'Apply this camo color to '
                    .. scope
                    .. ' in the selected LUT. Check at least one Camo region first. The swatch starts from the first checked region; alpha, pattern and scale are preserved.',
                on_change = function(value)
                    return apply(target, value, 'color', selected)
                end,
                picker_commit = function(value)
                    -- A mixed table can need this color even when it already
                    -- equals the first row's displayed color.
                    return apply(target, value, 'color', selected)
                end,
            }
        end
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
