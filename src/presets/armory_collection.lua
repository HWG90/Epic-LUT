-- Named preset collection and UI selection. No native writes or gear discovery.
local A = {}
local function type_label(preset)
    if #preset.armor > 0 then
        return #preset.helmet > 0 and 'Armor + Helmet' or 'Armor Only'
    end
    return 'Helmet Only'
end
local function first_strip(documents)
    local document = documents[1]
    local strip = {}
    if not document then
        return strip
    end
    for row = 1, document.height do
        local color = {}
        local index = (row - 1) * document.width * 4
        for channel = 0, 2 do
            color[#color + 1] = math.floor(math.max(0, math.min(1, document.data[index + channel])) * 255 + 0.5)
        end
        strip[#strip + 1] = color
    end
    return strip
end
function A.new(storage, control, handle)
    local self = { names = {}, selected = nil }
    function self.refresh()
        self.names = storage.names()
        local choices, previews, details = { 'Choose saved outfit...' }, {}, {}
        for _, name in ipairs(self.names) do
            choices[#choices + 1] = name
            local ok, preset = pcall(storage.load, name)
            if ok then
                previews[#choices] = { armor = first_strip(preset.armor), helmet = first_strip(preset.helmet) }
                details[#choices] = type_label(preset)
            end
        end
        local selector = control()
        selector.choices, selector.choice_previews, selector.choice_details = choices, previews, details
    end
    function self.select(index)
        if index == 1 then
            self.selected = nil
        else
            self.selected = storage.load(assert(self.names[index - 1]))
        end
    end
    function self.select_name(name)
        for index, label in ipairs(self.names) do
            if label == name then
                assert(handle().set('outfit_preset', index + 1))
                return
            end
        end
        error('Saved preset is not in the Armory collection')
    end
    function self.save(name, entries)
        storage.save(name, entries)
        self.selected = storage.load(name)
        self.refresh()
        self.select_name(name)
    end
    function self.manage(mode, menu, mod, message)
        assert(mode == 'rename' or mode == 'delete', 'Invalid preset action')
        local name = assert(self.selected, 'Choose an Armory preset first').name
        local function finish(new_name)
            if mode == 'rename' then
                storage.rename(name, new_name)
            else
                storage.delete(name)
            end
            self.selected = nil
            self.refresh()
            assert(handle().set('outfit_preset', 1))
            if mode == 'rename' then
                self.select_name(new_name)
            end
            menu.redraw_revision = (menu.redraw_revision or 0) + 1
            return message(
                mode == 'rename' and ('Renamed preset to ' .. new_name) or ('Removed ' .. name .. ' from The Armory.')
            )
        end
        menu.outfit_dialog = {
            phase = mode == 'rename' and 'name' or 'delete',
            title = mode == 'rename' and 'Rename Preset' or 'Delete Preset?',
            preset_name = name,
            mod = mod,
            control = mod.controls.outfit_name,
            on_save = finish,
        }
        if mode == 'rename' then
            menu.text_edit = { mod = mod, control = mod.controls.outfit_name, text = name, replace = true }
        end
        return true
    end
    return self
end
return A
