local A = dofile('src/armory_collection.lua')
local document = { height = 1, width = 23, data = { [0] = 0.5, [1] = 0.25, [2] = 0 } }
local presets = {
    Alpha = { name = 'Alpha', armor = { document }, helmet = {}, entries = {} },
    Bravo = { name = 'Bravo', armor = {}, helmet = { document }, entries = {} },
}
local storage = {
    names = function()
        local names = {}
        for name in pairs(presets) do
            names[#names + 1] = name
        end
        table.sort(names)
        return names
    end,
    load = function(name)
        return assert(presets[name], 'Missing preset')
    end,
    save = function(name)
        presets[name] = { name = name, armor = { document }, helmet = { document }, entries = {} }
    end,
    rename = function(old, new)
        assert(not presets[new])
        presets[new] = presets[old]
        presets[new].name = new
        presets[old] = nil
    end,
    delete = function(name)
        presets[name] = nil
    end,
}
local selector = {}
local collection
local selected
local handle = {
    set = function(id, index)
        assert(id == 'outfit_preset')
        selected = index
        collection.select(index)
        return true
    end,
}
collection = A.new(storage, function()
    return selector
end, function()
    return handle
end)
collection.refresh()
assert(selector.choice_details[2] == 'Armor Only' and selector.choice_details[3] == 'Helmet Only')
collection.select(1)
assert(not collection.selected, 'Empty selection attempted a disk load')
collection.select(2)
assert(collection.selected.name == 'Alpha')
collection.save('Charlie', {})
assert(collection.selected.name == 'Charlie' and selected == 4)
local menu = {}
local mod = { controls = { outfit_name = {} } }
collection.manage('rename', menu, mod, function(value)
    return value
end)
assert(menu.text_edit.text == 'Charlie')
menu.outfit_dialog.on_save('Delta')
assert(not presets.Charlie and collection.selected.name == 'Delta')
collection.manage('delete', menu, mod, function(value)
    return value
end)
assert(presets.Delta, 'Delete occurred before confirmation')
menu.outfit_dialog.on_save()
assert(not presets.Delta and not collection.selected)
print('PASS Armory collection: type previews, empty selection, save/select, rename and confirmed deletion')
