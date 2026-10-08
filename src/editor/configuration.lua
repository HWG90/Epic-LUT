-- Configuration presentation uses the existing preference store as its authority.
local C = {}
local preference_ids = {
    'basic_key',
    'menu_key',
    'preview_key',
    'ui_scale',
    'font_size',
    'font_bold',
    'window_width',
    'window_height',
    'reset_key',
}
local function link_preference(owner, id)
    local original = owner.controls[id]
    if not original then
        return
    end
    local linked = {}
    for key, value in pairs(original) do
        linked[key] = value
    end
    linked.id = 'configuration_' .. id
    linked.source_mod_id = owner.id
    linked.source_control_id = id
    if original.type ~= 'button' then
        linked.default = owner.handle.get(id)
        linked.on_change = function(value)
            return owner.handle.set(id, value)
        end
    end
    return linked
end
function C.append(pages, editor_pages, deps)
    local manual = table.remove(pages)
    for _, page in ipairs(editor_pages) do
        if page.id == 'save' then
            -- Editor actions remain registered for custom layouts, outside Configuration.
            for _, control in ipairs(page.controls) do
                pages[1].controls[#pages[1].controls + 1] = control
            end
            page.name = 'Configuration'
            page.controls = {}
            if deps.preferences and deps.preferences.mount then
                deps.preferences.mount(deps.api)
                local owner = deps.api.mods.epic_lut_preferences
                if owner then
                    for _, id in ipairs(preference_ids) do
                        local linked = link_preference(owner, id)
                        if linked then
                            page.controls[#page.controls + 1] = linked
                        end
                    end
                end
            end
            page.controls[#page.controls + 1] = {
                id = 'resource_format',
                type = 'choice',
                label = 'LUT resource IDs',
                choices = { 'Hexadecimal', 'Decimal' },
                default = 1,
                description = 'Display exact resource IDs when matched to game snapshots.',
                on_change = deps.resource_changed,
            }
            page.controls[#page.controls + 1] = {
                type = 'section',
                id = 'manual_fallback',
                label = 'Manual file fallback',
                collapsible = true,
                collapsed = true,
                children = manual.controls,
            }
            if deps.updates then
                local updates, preferences = deps.updates, deps.preferences
                page.controls[#page.controls + 1] = { type = 'text', id = 'update_status', label = updates.status }
                page.controls[#page.controls + 1] = {
                    type = 'button',
                    id = 'check_updates',
                    label = 'Check for Updates',
                    on_activate = function()
                        return deps.action(function()
                            return deps.message(updates.check())
                        end)
                    end,
                }
                page.controls[#page.controls + 1] = {
                    type = 'toggle',
                    id = 'auto_updates',
                    label = 'Check for updates at launch',
                    default = preferences.auto_updates(),
                    on_change = preferences.save_auto_updates,
                }
                page.controls[#page.controls + 1] = {
                    type = 'button',
                    id = 'open_updates',
                    label = 'Open Download Page',
                    on_activate = function()
                        return deps.action(function()
                            return deps.message(updates.open())
                        end)
                    end,
                }
            end
        end
        pages[#pages + 1] = page
    end
end
return C
