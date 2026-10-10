-- Native Gui draw layers are integers. Quantize every primitive before sorting
-- by native depth/allocation order, then assert retained pixel ownership.
-- https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Gui.html
local View = dofile('vendor/menu/view.lua')
local world, items, next_id, allocations = {}, {}, 0, 0
local function allocate(item)
    local native_z = math.floor(tonumber(item.z))
    assert(native_z == item.z, 'Fractional native layer: ' .. tostring(item.z))
    item.z = native_z
    next_id, allocations = next_id + 1, allocations + 1
    item.order = next_id
    items[next_id] = item
    return next_id
end
local sr = {
    Application = {
        worlds = function()
            return { world }
        end,
        main_world = function()
            return world
        end,
        can_get = function(kind, value)
            return kind == 'material' and value == 'test/preview'
        end,
    },
    World = {
        create_screen_gui = function()
            return {}
        end,
        destroy_gui = function() end,
    },
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Color = function(a, r, g, b)
        return { a = a, r = r, g = g, b = b }
    end,
    Material = { set_scalar = function() end },
    Gui = {
        rect = function(_, p, size, color)
            return allocate({ x = p.x, y = p.y, z = p.z, w = size.x, h = size.y, color = color })
        end,
        text = function(_, label, _, size, _, p, color)
            return allocate({
                x = p.x,
                y = p.y,
                z = p.z,
                w = #label * size * 0.5,
                h = size,
                color = color,
                text = label,
            })
        end,
        triangle = function(_, a, b, c, z, color)
            local x, y = math.min(a.x, b.x, c.x), math.min(a.z, b.z, c.z)
            return allocate({
                x = x,
                y = y,
                z = z,
                w = math.max(a.x, b.x, c.x) - x,
                h = math.max(a.z, b.z, c.z) - y,
                color = color,
                triangle = true,
            })
        end,
        material = function()
            return {}
        end,
        destroy_rect = function(_, id)
            items[id] = nil
        end,
        destroy_text = function(_, id)
            items[id] = nil
        end,
        destroy_triangle = function(_, id)
            items[id] = nil
        end,
    },
}
local view = View.new(sr, true)
local gray, gold, red, blue, white =
    { 25, 35, 45 }, { 244, 202, 53 }, { 220, 25, 35 }, { 25, 50, 220 }, { 240, 240, 240 }
local function rect(x, y, w, h, color, role, plane)
    return {
        type = 'rect',
        x = x,
        y = y,
        w = w,
        h = h,
        a = 1,
        c = color,
        ui_role = role,
        paint_plane = plane,
        paint_span = plane and 32 or nil,
    }
end
local function text(x, y, label, color, plane)
    return {
        type = 'text',
        x = x,
        y = y,
        size = 12,
        text = label,
        a = 1,
        c = color,
        paint_plane = plane,
        paint_span = plane and 32 or nil,
    }
end
local function pixel(x, y)
    local winner
    for _, item in pairs(items) do
        if
            x >= item.x
            and x < item.x + item.w
            and y >= item.y
            and y < item.y + item.h
            and (not winner or item.z > winner.z or item.z == winner.z and item.order > winner.order)
        then
            winner = item
        end
    end
    return assert(winner, 'No native pixel at ' .. x .. ',' .. y)
end
local parent = rect(0, 0, 220, 180, gray, 'content_background')
local cell_border = rect(10, 10, 24, 24, gray, 'swatch_border')
local cell_fill = rect(12, 12, 20, 20, red, 'swatch_fill')
local widget = rect(60, 10, 120, 30, blue, 'control_fill')
local label = text(68, 18, 'Export', white)
local slider_track = rect(60, 60, 120, 8, gray, 'slider_track')
local slider_fill = rect(60, 60, 80, 8, blue, 'slider_fill')
local thumb_border = rect(95, 54, 14, 20, gray, 'slider_thumb_border')
local thumb = rect(97, 56, 10, 16, gold, 'slider_thumb')
local gradient = rect(10, 90, 160, 60, red, 'control_fill')
local marker_border = rect(38, 106, 16, 16, gray, 'marker_border')
local marker = rect(40, 108, 12, 12, white, 'marker_fill')
local selection = rect(60, 110, 90, 16, gold, 'text_selection')
local field = text(64, 111, 'Hex', white)
local caret = rect(82, 108, 1, 20, blue, 'text_caret')
local preview = rect(185, 90, 25, 25, blue, 'swatch_fill')
preview.preview_material = 'test/preview'
local commands = {
    parent,
    cell_border,
    cell_fill,
    widget,
    label,
    slider_track,
    slider_fill,
    thumb_border,
    thumb,
    gradient,
    marker_border,
    marker,
    selection,
    field,
    caret,
    preview,
}
view.draw(commands)
local cell, button, letters, handle, marker_id, field_id, caret_id =
    pixel(20, 20), pixel(65, 14), pixel(70, 20), pixel(100, 62), pixel(46, 114), pixel(66, 114), pixel(82.5, 110)
assert(cell.color.r == 220 and button.color.b == 220 and letters.text == 'Export', 'Initial child controls covered')
assert(
    handle.color.r == 244 and marker_id.color.r == 240 and field_id.text == 'Hex' and caret_id.color.b == 220,
    'Initial native handle/text ordering incorrect'
)
cell_border.c = gold
parent.c = { 55, 65, 75 }
view.draw(commands)
assert(
    pixel(20, 20) == cell and pixel(65, 14) == button and pixel(70, 20) == letters,
    'Recreated parent/border covered retained RGB/control/text'
)
assert(pixel(10.5, 10.5).color.r == 244, 'Selection edge did not turn gold')
slider_fill.c = red
gradient.c = blue
view.draw(commands)
assert(pixel(100, 62) == handle and pixel(46, 114) == marker_id, 'Refreshed gradient/slider covered retained markers')
assert(pixel(66, 114) == field_id and pixel(82.5, 110) == caret_id, 'Small pane update covered retained text/caret')
local stable = allocations
view.draw(commands)
assert(allocations == stable, 'Stable integer-layer frame reallocated primitives')
-- Entire foreground windows outrank every rear primitive, even new rear text
-- and frame allocations. Their counts have no influence on semantic depth.
local rear_bg = rect(250, 0, 220, 180, gray, 'window_background', 1000)
local rear_frame = rect(250, 0, 220, 2, gold, 'window_frame', 1000)
local rear_text = text(300, 20, 'Rear', white, 1000)
local front_bg = rect(280, 0, 150, 180, blue, 'window_background', 1032)
commands[#commands + 1] = rear_bg
commands[#commands + 1] = rear_frame
commands[#commands + 1] = rear_text
commands[#commands + 1] = front_bg
view.draw(commands)
local front = pixel(302, 22)
assert(not front.text and front.color.b == 220, 'Foreground body failed to occlude rear text')
rear_text.text = 'Rear changed'
rear_frame.c = white
view.draw(commands)
assert(pixel(302, 22) == front, 'Reallocated rear content escaped its integer range')
for i = 1, 1000 do
    commands[#commands + 1] = rect(460, 170, 1, 1, red, 'control_fill', 1000)
end
view.draw(commands)
assert(pixel(302, 22).color.b == 220, 'Dense rear content changed window ordering')
local triangle_found = false
for _, item in pairs(items) do
    assert(item.z == math.floor(tonumber(item.z)), 'Non-integer retained layer')
    triangle_found = triangle_found or item.triangle
end
assert(triangle_found, 'Native triangle path was not exercised')
view.release()
print(
    'PASS integer native layers: retained swatches/controls/text/handles, parent and child updates, triangle path, foreground occlusion and stable allocations'
)
