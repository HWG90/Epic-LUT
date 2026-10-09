-- Optional MCM presentation. Epic LUT remains the only settings writer.
local M = {}
local mod_id = 'epic_lut_settings'
local groups = {
    {
        'shortcuts',
        'Shortcuts',
        1,
        { 'configuration_basic_key', 'configuration_menu_key', 'configuration_preview_key', 'configuration_reset_key' },
    },
    {
        'appearance',
        'Appearance',
        1,
        {
            'configuration_ui_scale',
            'configuration_font_size',
            'configuration_font_bold',
            'configuration_window_width',
            'configuration_window_height',
        },
    },
    { 'gear', 'Gear and Player Preview', 2, { 'auto_populate_worn', 'disable_player_preview', 'resource_format' } },
    { 'exports', 'Exports', 2, { 'include_capes_in_armor_exports' } },
    { 'sharing', 'Squad sharing', 2, { 'share_appearance', 'sharing_status' } },
    { 'updates', 'Updates', 2, { 'update_status', 'check_updates', 'auto_updates', 'open_updates' } },
}
local function copy(t)
    local result = {}
    for key, value in pairs(t) do
        result[key] = value
    end
    return result
end

function M.new(deps)
    local source_api = assert(deps.api, 'Epic LUT settings API required')
    local source_id = deps.source_mod_id or 'epic_direct_lut'
    local discover = deps.discover or function()
        return rawget(_G, 'DBFMCM')
    end
    local log = deps.log or function() end
    local self, framework, registration, source, failed = {}, nil, nil, nil, nil
    local routes, displays, local_actions = {}, {}, {}
    local source_revision

    local function detach()
        if registration then
            pcall(registration.unregister)
        end
        framework, registration, source, failed, source_revision = nil, nil, nil, nil, nil
        routes, displays, local_actions = {}, {}, {}
    end
    local function route(id)
        local presentation = assert(routes[id], 'Unknown Epic LUT setting: ' .. tostring(id))
        local current = assert(source_api.mods[source_id], 'Epic LUT settings unavailable')
        local owner = current
        if presentation.source_mod_id then
            owner = source_api.mods[presentation.source_mod_id]
        end
        local key = presentation.source_control_id or id
        local control = owner and owner.controls[key]
        assert(control, 'Epic LUT setting unavailable: ' .. id)
        return owner.handle, key, control, presentation
    end
    local function call(id, method, ...)
        local handle, key, control, presentation = route(id)
        if method ~= 'get' and method ~= 'preview' then
            assert(not control.disabled and not presentation.disabled, 'Setting unavailable')
        end
        return assert(handle[method] or (method == 'preview' and handle.get), 'Unsupported setting action')(key, ...)
    end
    local function open_editor(fn)
        if framework and type(framework.close) == 'function' then
            local ok, why = framework.close()
            if ok == false then
                return false, why or 'MCM cursor restoration pending'
            end
        end
        return fn()
    end
    local function define(current)
        local controls, used = {}, {}
        local page
        for _, candidate in ipairs(current.pages) do
            if candidate.id == 'save' then
                page = candidate
                break
            end
        end
        if not page then
            return
        end
        local definitions = {}
        for _, control in ipairs(page.controls) do
            if control.id then
                definitions[control.id] = control
            end
        end
        local function add(id, column, target)
            local original = definitions[id]
            if not original or used[id] then
                return
            end
            used[id] = true
            local control = copy(original)
            control.page, control.groups, control.depth, control.children = nil, nil, nil, nil
            control.source_mod_id, control.source_control_id = nil, nil
            control.on_change, control.validate = nil, nil
            control.column, control.require_confirmation = column, false
            routes[id] = original
            if original.type ~= 'text' and original.type ~= 'section' then
                local _, _, authoritative = route(id)
                if original.type ~= 'button' then
                    control.default = authoritative.default
                else
                    control.on_activate = function()
                        local ok, result = call(id, 'activate')
                        if not ok then
                            error(result, 0)
                        end
                        return result
                    end
                end
            end
            target[#target + 1] = control
        end
        for _, entry in ipairs({
            { 'open_basic', 'Open Basic Mode', deps.open_basic },
            { 'open_advanced', 'Open LUT Editor', deps.open_advanced },
        }) do
            if entry[3] then
                local id, fn = entry[1], entry[3]
                local_actions[id] = function()
                    return open_editor(fn)
                end
                controls[#controls + 1] = {
                    id = id,
                    type = 'button',
                    label = entry[2],
                    column = 1,
                    require_confirmation = false,
                    on_activate = function()
                        local ok, why = local_actions[id]()
                        if ok == false then
                            error(why, 0)
                        end
                        return why
                    end,
                }
            end
        end
        for _, entry in ipairs(groups) do
            local children = {}
            for _, id in ipairs(entry[4]) do
                add(id, entry[3], children)
            end
            if #children > 0 then
                controls[#controls + 1] = {
                    id = entry[1],
                    type = 'section',
                    label = entry[2],
                    column = entry[3],
                    collapsed = false,
                    children = children,
                }
            end
        end
        local manual, extras = {}, {}
        for _, control in ipairs(page.controls) do
            if control.id and not used[control.id] and control.type ~= 'section' then
                local fallback = false
                for _, group in ipairs(control.groups or {}) do
                    if group == 'manual_fallback' then
                        fallback = true
                    end
                end
                add(control.id, 2, fallback and manual or extras)
            end
        end
        for _, entry in ipairs({
            { 'additional', 'Additional settings', extras },
            { 'manual', 'Manual file fallback', manual },
        }) do
            if #entry[3] > 0 then
                controls[#controls + 1] = {
                    id = entry[1],
                    type = 'section',
                    label = entry[2],
                    column = 2,
                    collapsed = true,
                    children = entry[3],
                }
            end
        end
        return {
            id = mod_id,
            name = 'Epic LUT Settings' .. (deps.version and (' ' .. deps.version) or ''),
            version = deps.version,
            author = 'Goose',
            description = 'Shared settings for the Epic LUT editor. Changes also appear in its Configuration page.',
            -- The handle below delegates all writes; MCM must not load or save a second copy.
            storage = {
                load = function()
                    return {}
                end,
                save = function()
                    return true
                end,
            },
            pages = { { id = 'settings', name = 'Configuration', require_confirmation = false, controls = controls } },
        }
    end
    local function synchronize()
        local changed = source_revision ~= source_api.revision
        for _, display in ipairs(displays) do
            local original = routes[display.id]
            if original then
                local disabled = original.disabled
                if original.type ~= 'text' and original.type ~= 'section' then
                    local _, _, control = route(display.id)
                    disabled = disabled or control.disabled
                end
                for _, key in ipairs({ 'label', 'description', 'disabled', 'choices' }) do
                    local value = key == 'disabled' and disabled or original[key]
                    if display[key] ~= value then
                        display[key], changed = value, true
                    end
                end
            end
        end
        if changed then
            framework.revision = (framework.revision or 0) + 1
        end
        source_revision = source_api.revision
    end
    function self.tick()
        if self.closed then
            return
        end
        local api, current = discover(), source_api.mods[source_id]
        if
            registration
            and (
                framework ~= api
                or source ~= current
                or type(api) ~= 'table'
                or not api.mods[mod_id]
                or api.mods[mod_id].handle ~= registration
            )
        then
            detach()
        end
        if
            type(api) ~= 'table'
            or api == source_api
            or api.api ~= 1
            or type(api.register) ~= 'function'
            or type(api.mods) ~= 'table'
            or not current
        then
            return
        end
        if not registration then
            local marker = tostring(api)
                .. ':'
                .. tostring(current)
                .. ':'
                .. tostring(source_api.revision)
                .. ':'
                .. tostring(api.mods[mod_id])
            if failed == marker then
                return
            end
            if api.mods[mod_id] then
                failed = marker
                log('Epic LUT MCM settings registration already owned')
                return
            end
            routes, displays, local_actions = {}, {}, {}
            local ok, result = pcall(function()
                local spec = define(current)
                if not spec then
                    return
                end
                return api.register(spec)
            end)
            if not ok then
                failed = marker
                log('Epic LUT MCM settings unavailable: ' .. tostring(result))
                return
            end
            if not result then
                return
            end
            framework, registration, source, failed = api, result, current, nil
            local mod = api.mods[mod_id]
            for _, p in ipairs(mod.pages) do
                for _, control in ipairs(p.controls) do
                    displays[#displays + 1] = control
                end
            end
            local function active()
                assert(
                    not self.closed and framework == api and api.mods[mod_id] and api.mods[mod_id].handle == result,
                    'Retired MCM settings registration'
                )
            end
            for _, method in ipairs({ 'get', 'preview', 'set', 'edit', 'reset', 'activate', 'queue' }) do
                local operation = method
                registration[operation] = function(id, ...)
                    active()
                    if local_actions[id] then
                        if operation == 'get' or operation == 'preview' then
                            return nil
                        end
                        assert(operation == 'activate' or operation == 'queue', 'Editor shortcut is not a setting')
                        local ok, result, why = pcall(local_actions[id])
                        if not ok then
                            return false, result
                        end
                        return result, why
                    end
                    -- This page commits immediately, through the source's persistence and callbacks.
                    return call(
                        id,
                        operation == 'edit' and 'set' or operation == 'queue' and 'activate' or operation,
                        ...
                    )
                end
            end
            function registration.set_many(values)
                active()
                assert(type(values) == 'table', 'Settings table required')
                local owner, changes = nil, {}
                for id, value in pairs(values) do
                    local handle, key, control, presentation = route(id)
                    assert(not control.disabled and not presentation.disabled, 'Setting unavailable')
                    if owner and owner ~= handle then
                        return false, 'Import settings for one Epic LUT preference group at a time'
                    end
                    owner, changes[key] = handle, value
                end
                if not owner then
                    return true
                end
                return owner.set_many(changes)
            end
            for _, method in ipairs({ 'confirm', 'discard' }) do
                registration[method] = function(page_id)
                    active()
                    assert(page_id == 'settings', 'Unknown MCM settings page')
                    return true -- Immediate settings have no second draft to commit or discard.
                end
            end
            log('Epic LUT Settings registered in MCM')
        end
        local ok, why = pcall(synchronize)
        if not ok then
            log('Epic LUT MCM settings synchronization deferred: ' .. tostring(why))
            detach()
        end
    end
    function self.close()
        detach()
        self.closed = true
    end
    return self
end
return M
