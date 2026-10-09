-- Own editor logic. Only primary-color RGB (column zero) changes; alpha and all other columns stay exact.
local P = {}
function P.rgb(hex)
    assert(type(hex) == 'string' and hex:match('^#%x%x%x%x%x%x$'), 'Invalid RGB color')
    return tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255
end
function P.hex(values, row, width)
    local at = row * width * 4
    local function byte(v)
        return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
    end
    return string.format('#%02X%02X%02X', byte(values[at]), byte(values[at + 1]), byte(values[at + 2]))
end
function P.copy(original, width, height, overrides, allocate, copy)
    assert(width >= 1 and width <= 64 and height >= 1 and height <= 64, 'Unsupported LUT dimensions')
    local out = allocate(width * height * 4)
    copy(out, original, width * height * 16)
    for row, hex in pairs(overrides) do
        assert(type(row) == 'number' and row % 1 == 0 and row >= 0 and row < height, 'Invalid LUT row')
        local r, g, b = P.rgb(hex)
        local at = row * width * 4
        out[at], out[at + 1], out[at + 2] = r, g, b
    end
    return out
end
function P.value_tooltip(document, row, column)
    if
        not document
        or not document.data
        or row < 1
        or row > document.height
        or column < 1
        or column > document.width
    then
        return nil
    end
    local at = ((row - 1) * document.width + column - 1) * 4
    return string.format(
        'Row %d / Col %d\nR: %.6g\nG: %.6g\nB: %.6g\nA: %.6g',
        row,
        column,
        tonumber(document.data[at]),
        tonumber(document.data[at + 1]),
        tonumber(document.data[at + 2]),
        tonumber(document.data[at + 3])
    )
end
function P.swatch(ui, x, y, w, h, color, alpha, show_alpha)
    alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
    if not show_alpha or alpha == 1 then
        ui.rect(x, y, w, h, color, nil, 'swatch_fill')
        return
    end
    local columns, rows = w > 80 and 8 or 2, h > 25 and 4 or 2
    for row = 0, rows - 1 do
        for col = 0, columns - 1 do
            local background = (row + col) % 2 == 0 and 220 or 125
            local blended = {}
            for ch = 1, 3 do
                blended[ch] = math.floor(color[ch] * alpha + background * (1 - alpha) + 0.5)
            end
            ui.rect(x + col * w / columns, y + row * h / rows, w / columns, h / rows, blended, nil, 'swatch_fill')
        end
    end
end
return P
