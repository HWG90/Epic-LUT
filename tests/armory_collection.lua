local A = dofile('src/presets/armory_collection.lua')
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
presets.Cape = { name = 'Cape', armor = {}, helmet = {}, cape = { document }, entries = {} }
collection.refresh()
assert(
    selector.choice_details[4] == 'Armor Only' and #selector.choice_previews[4].armor == 1,
    'Cape-only Armory preset lost Armor grouping or preview'
)
presets.Cape = nil
collection.refresh()
print('PASS Armory collection: type previews, empty selection, save/select, rename and confirmed deletion')

collection.filter('br', 1)
assert(#collection.names == 1 and collection.names[1] == 'Bravo')
collection.filter('', 2)
assert(collection.names[1] == 'Bravo' and collection.names[2] == 'Alpha')

-- Empty search values must survive the real settings writer used in game.
local disk = dofile('vendor/menu/store.lua').new('tests/tmp/presets')
assert(disk.save('armory_search_test', { search = '', other = 'valid name' }))
local settings = disk.load('armory_search_test')
assert(settings.search == '' and settings.other == 'valid name', 'Empty search did not round trip')
local core = dofile('vendor/menu/core.lua').new(disk)
local test = core.register({
    id = 'armory_search_test',
    name = 'Search test',
    pages = {
        {
            id = 'search',
            name = 'Search',
            controls = {
                { id = 'search', type = 'input', label = 'Search', allow_empty = true, default = '' },
                { id = 'other', type = 'input', label = 'Name', default = 'valid name' },
            },
        },
    },
})
assert(test.set('other', 'new name'))
assert(test.set('search', 'filter'))
assert(test.set('search', ''))
assert(disk.load('armory_search_test').search == '')
os.remove('tests/tmp/presets/armory_search_test.ini')
os.remove('tests/tmp/presets/armory_search_test.ini.bak')

do
    local library, deleted, selection_calls = {}, {}, {}
    local payloads =
        { Alpha = 'alpha.dds', Beta = 'beta.dds', Bravo = 'bravo.dds', Brown = 'brown.dds', Zulu = 'zulu.dds' }
    local active_appearance = { armor = 'active-armor', helmet = 'active-helmet' }
    for name in pairs(payloads) do
        library[name] = { name = name, armor = { document }, helmet = {}, entries = {} }
    end
    local fail_delete = false
    local storage = {
        names = function()
            local names = {}
            for name in pairs(library) do
                names[#names + 1] = name
            end
            return names
        end,
        load = function(name)
            return assert(library[name], 'Missing preset')
        end,
        delete = function(name)
            if fail_delete then
                return false, 'Manifest is locked'
            end
            assert(library[name])
            deleted[#deleted + 1] = name
            library[name] = nil
            return true
        end,
    }
    local selector, collection, current = {}, nil, 1
    local handle = {
        set = function(id, index)
            assert(id == 'outfit_preset')
            current = index
            collection.select(index)
            selection_calls[#selection_calls + 1] = collection.selected and collection.selected.name or 'empty'
            return true
        end,
    }
    collection = A.new(storage, function()
        return selector
    end, function()
        return handle
    end)
    collection.refresh()
    collection.select_name('Zulu')
    assert(current == 6)
    assert(not pcall(collection.remove_choice, 1, 'Choose saved outfit...'), 'Placeholder preset was removed')
    assert(not pcall(collection.remove_choice, 2, 'Beta'), 'Stale row label deleted a different preset')
    assert(not pcall(collection.remove_choice, 2.5, 'Alpha'), 'Fractional removal index accepted')
    selector.choices[2] = 'Another row'
    assert(not pcall(collection.remove_choice, 2, 'Alpha'), 'Changed UI row accepted stale removal')
    assert(#deleted == 0 and collection.selected.name == 'Zulu', 'Rejected row mutated the library or selection')
    collection.refresh()
    local before = #selection_calls
    local removed, status = collection.remove_choice(2, 'Alpha')
    assert(removed and status == 'Removed Alpha from The Armory.' and not library.Alpha)
    assert(
        collection.selected.name == 'Zulu' and current == 5,
        'Removing earlier unselected row changed selected preset'
    )
    assert(
        #selection_calls == before + 1 and selection_calls[#selection_calls] == 'Zulu',
        'Removal selected/applied the clicked preset'
    )
    assert(
        payloads.Alpha == 'alpha.dds'
            and active_appearance.armor == 'active-armor'
            and active_appearance.helmet == 'active-helmet',
        'Removal affected DDS payloads or active appearance'
    )
    collection.filter('br', 2)
    assert(collection.names[1] == 'Brown' and collection.names[2] == 'Bravo')
    collection.select_name('Bravo')
    assert(collection.remove_choice(2, 'Brown'))
    assert(
        collection.query == 'br' and collection.order == 2 and collection.selected.name == 'Bravo' and current == 2,
        'Sorted/filtered removal used global indices or changed the current preset'
    )
    assert(
        not pcall(collection.remove_choice, 2, 'Brown') and library.Bravo,
        'Old row snapshot removed the shifted preset'
    )
    assert(collection.remove_choice(2, 'Bravo'))
    assert(
        not collection.selected and current == 1 and #selector.choices == 1,
        'Removing selected preset retained stale preview/choice'
    )
    collection.filter('', 1)
    collection.select_name('Beta')
    local prior_choices, prior_selected, prior_calls = selector.choices, collection.selected, #selection_calls
    fail_delete = true
    local ok, why = pcall(collection.remove_choice, 2, 'Beta')
    assert(not ok and tostring(why):find('Manifest is locked', 1, true), 'Delete failure was not reported')
    assert(
        selector.choices == prior_choices
            and collection.selected == prior_selected
            and #selection_calls == prior_calls
            and library.Beta,
        'Failed storage removal committed UI/selection changes'
    )
    assert(
        #deleted == 3 and payloads.Bravo == 'bravo.dds' and payloads.Brown == 'brown.dds',
        'Only active library manifests should be removed'
    )
    print(
        'PASS arbitrary Armory row removal:filtered/sorted labels, stale/placeholder rejection, selected-name preservation, failure isolation and untouched payloads/appearance'
    )
end
