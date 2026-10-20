-- Lua 5.1 menu input through the loader's one shared input service v1.
-- The service owns cursor policy and suppresses mouse look, not gameplay keys.
local M = {}
local names = { [8]='backspace', [9]='tab', [13]='enter', [16]='left shift', [17]='left ctrl', [18]='left alt',
    [20]='caps lock', [27]='esc', [32]='space', [33]='page up', [34]='page down', [35]='end', [36]='home',
    [37]='left', [38]='up', [39]='right', [40]='down', [45]='insert', [46]='delete',
    [160]='left shift', [161]='right shift', [162]='left ctrl', [163]='right ctrl', [164]='left alt', [165]='right alt',
    [186]='semicolon', [187]='equal', [188]='comma', [189]='minus', [190]='period', [191]='slash',
    [192]='backtick', [219]='open bracket', [220]='backslash', [221]='close bracket', [222]='quote' }
for code = 48, 57 do names[code] = string.char(code) end
for code = 65, 90 do names[code] = string.char(code + 32) end
for code = 112, 135 do names[code] = 'f' .. (code - 111) end
local mouse_bits = { [1]=1, [2]=2, [4]=4, [5]=8, [6]=16 }
local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end
function M.new(sr, service, log)
    assert(type(service) == 'table' and (service.version == 1 or service.api_version == 1)
        and type(service.capabilities) == 'table' and service.capabilities.menu == true
        and service.capabilities.coordinates == 'client-top-left', 'Shared input service v1 menu capability required')
    for _, name in ipairs({ 'acquire', 'snapshot', 'owns', 'release', 'status' }) do
        assert(type(service[name]) == 'function', 'Shared input service operation missing: ' .. name)
    end
    assert(type(sr) == 'table' and sr.Window and type(sr.Window.has_focus) == 'function'
        and sr.Keyboard and type(sr.Keyboard.button_id) == 'function' and type(sr.Keyboard.button) == 'function'
        and sr.Gui and type(sr.Gui.resolution) == 'function', 'Documented Stingray menu input APIs required')
    local input, capture = {}, { active=false }
    local token, pending, reason
    local wanted, was_focused, attempted, focused = false, false, false, false
    local ids, keys, pointer = {}, {}, {}
    local sampled, wheel_taken = false, false
    local function clear_pointer()
        pointer.valid, sampled, wheel_taken = false, false, false
    end
    local function clear_lease()
        token, pending, capture.active = nil, false, false
        clear_pointer()
    end
    -- Revocation may already have restored and discarded our service token.
    -- A pending restoration keeps that exact token for explicit recovery.
    local function observe_loss(why)
        capture.active, pending, reason = false, token ~= nil, why or 'Input ownership lost'
        clear_pointer()
        local checked, status = pcall(service.status)
        if checked and type(status) == 'table' then
            if status.active == false and status.pending_restore == false and status.owner == nil then
                clear_lease()
            elseif status.active == true and status.pending_restore == false then
                local checked_owner, owned = pcall(service.owns, token)
                if checked_owner and owned == false then clear_lease() end
            end
        end
    end
    function capture.release()
        wanted, attempted = false, false
        clear_pointer()
        if token == nil then capture.active, pending = false, false; return true end
        local called, ready, why = pcall(service.release, token)
        if called and ready == true then
            clear_lease(); reason = nil
            return true
        end
        observe_loss(called and why or tostring(ready))
        if token == nil then return true end
        return false, reason or 'Epic LUT input restoration is pending'
    end
    function capture.status()
        return { owner=token and 'epic_lut' or nil, active=capture.active, pending_restore=pending == true,
            reason=reason, mode='menu', cursor_policy='shared', keyboard_isolation=false }
    end
    function capture.sync(visible, has_focus)
        local opening = visible == true and (not wanted or not was_focused and has_focus == true)
        local closing = wanted and (visible ~= true or has_focus ~= true)
        wanted, was_focused = visible == true, has_focus == true
        if not wanted or not was_focused then
            clear_pointer()
            if closing and token ~= nil then return capture.release() end
            return token == nil, token ~= nil and reason or nil
        end
        if token ~= nil then
            if pending then return false, reason or 'Previous input restoration is pending' end
            local checked, owned = pcall(service.owns, token)
            if not checked or owned ~= true then observe_loss(checked and 'Input ownership lost' or tostring(owned)) end
            if token ~= nil then return capture.active, reason end
            return false, reason or 'Input ownership lost; close and reopen Epic LUT'
        end
        if opening then attempted = false end
        if attempted then return false, reason or 'Close and reopen Epic LUT to retry input acquisition' end
        attempted = true
        local called, acquired, why, cleanup = pcall(service.acquire, 'epic_lut', 'menu')
        if not called then reason = tostring(acquired); return false, reason end
        if acquired == nil then
            token, pending, reason = cleanup, cleanup ~= nil, why or 'Cannot acquire shared menu input'
            return false, reason
        end
        token, pending, capture.active, reason = acquired, false, true, nil
        clear_pointer()
        if log then log('Epic LUT shared menu input acquired') end
        return true
    end
    capture.shutdown = capture.release
    local function sample()
        if not wanted or not focused or not capture.active or token == nil or pending then return end
        if sampled then return pointer.valid and pointer or nil end
        sampled = true
        local called, value, why = pcall(service.snapshot, token)
        if not called or type(value) ~= 'table' or value.valid ~= true then
            observe_loss(called and why or tostring(value))
            return
        end
        if not finite(value.x) or not finite(value.y) or not finite(value.width) or value.width <= 0
            or not finite(value.height) or value.height <= 0 or not finite(value.buttons)
            or value.buttons < 0 or value.buttons % 1 ~= 0 or not finite(value.wheel or 0) then
            local _, why = capture.release()
            reason, wanted, attempted = why or 'Malformed shared input sample', true, true
            return
        end
        -- The service reuses its sample table; copy scalars before another reader.
        pointer.valid, pointer.x, pointer.y = true, value.x, value.y
        pointer.width, pointer.height = value.width, value.height
        pointer.buttons, pointer.wheel = value.buttons, value.wheel or 0
        return pointer
    end
    function input.poll()
        clear_pointer()
        for code in pairs(keys) do keys[code] = nil end
        local ok, value = pcall(sr.Window.has_focus)
        focused = ok and value == true
        if capture.active and token ~= nil then
            local checked, owned = pcall(service.owns, token)
            if not checked or owned ~= true then observe_loss(checked and 'Input ownership lost' or tostring(owned)) end
        end
    end
    function input.focused() return focused end
    function input.window() return nil end -- This API supplies client pixels, not an HWND.
    local function keyboard_down(code)
        local id = ids[code]
        if id == nil then
            local name = names[code]
            local ok, value = false, nil
            if name then ok, value = pcall(sr.Keyboard.button_id, name) end
            id = ok and type(value) == 'number' and value or false
            ids[code] = id
        end
        if id == false then return false end
        local ok, value = pcall(sr.Keyboard.button, id)
        return ok and (value == true or type(value) == 'number' and value > 0.5) or false
    end
    function input.down(code)
        if type(code) ~= 'number' or code < 1 or code > 255 or code % 1 ~= 0 then return false end
        if not focused then return false end
        if mouse_bits[code] then
            local value = sample()
            return value ~= nil and math.floor(value.buttons / mouse_bits[code]) % 2 == 1 or false
        end
        if keys[code] ~= nil then return keys[code] end
        local value = keyboard_down(code)
        if code >= 16 and code <= 18 and not value then value = keyboard_down(161 + (code - 16) * 2) end
        keys[code] = value
        return value
    end
    function input.mouse()
        local value = sample()
        if not value then return end
        local w, h = sr.Gui.resolution()
        if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return end
        return value.x * w / value.width, h - value.y * h / value.height
    end
    function input.wheel()
        if wheel_taken then return 0 end
        local value = sample()
        wheel_taken = true
        return value and value.wheel or 0
    end
    return { input=input, capture=capture, resolution=sr.Gui.resolution, shared_input_service=service,
        capabilities={ menu=true, coordinates='client-top-left', keyboard_isolation=false, cursor_policy='shared' } }
end
return M
