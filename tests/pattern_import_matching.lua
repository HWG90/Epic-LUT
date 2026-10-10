-- Exercise the production matching planner/commit functions with exact slots
-- and resources; discovery, snapshot and ownership boundaries stay explicit.
local ffi = require('ffi')
local f = assert(io.open('src/editor/direct_editor.lua', 'rb'))
local source = f:read('*a')
f:close()
local implementation = assert(source:match('(local function matching_plan.-)\nimport_target ='))
local factory = assert(loadstring([[
local e=...
local m,native,palettes,source_tables,groups,pattern_editor,operations,handle,original_luts =
    e.m,{},e.palettes,e.documents,e.groups,e.pattern_editor,e.operations,e.handle,e.originals
local present,binding,apply_bindings,basic_documents,stop_identification,refresh,message,remember_appearance =
    e.present,e.binding,e.material_apply,e.basic,e.stop,e.refresh,e.message,e.remember
local index_job,resume_done,resume_job
]] .. implementation .. '\nreturn {plan=matching_plan,apply=apply_matching}'))
local function fixture()
    local e = {
        palettes = {},
        documents = {},
        groups = {},
        basic = {},
        writes = {},
        scans = 0,
        flash_stops = 0,
        preserves = 0,
        remembered = 0,
        originals_by_object = {},
        objects = {},
    }
    e.m = {
        import_matches = dofile('src/imports/import_matches.lua'),
        basic_state = dofile('src/core/basic_state.lua'),
        gear_catalog = {
            kind = function(b)
                return b.helmet and 'helmet' or 'armor'
            end,
        },
        engine = {
            LUT_SLOT = 1,
            PATTERN_SLOT = 2,
            texture_object = function(_, hash)
                return e.objects[hash]
            end,
        },
        original_luts = {
            preserve = function(d, original)
                assert(d.width == 23 and original.width == 23, 'Pattern passed through emissive preservation')
                e.preserves = e.preserves + 1
                return d
            end,
        },
    }
    e.originals = {
        get = function(object)
            return e.originals_by_object[object]
        end,
    }
    e.handle = {
        get = function(id)
            assert(id == 'preserve_emissives')
            return true
        end,
    }
    e.stop = function()
        return true
    end
    e.refresh = function() end
    e.message = function(value)
        return value
    end
    e.present = function(b)
        return not b.stale
    end
    e.binding = function(b)
        return b.foreign or b.current
    end
    e.remember = function(targets, pattern)
        assert(pattern == true and targets[1].slot == 2)
        e.remembered = e.remembered + 1
    end
    e.material_apply = function(d, targets)
        assert(d.width == 23 and targets[1].slot == 1, '3x1 Pattern reached material upload')
        e.writes[#e.writes + 1] =
            { pattern = false, bytes = ffi.string(d.data, d.width * d.height * 16), targets = targets }
        return #targets
    end
    e.operations = {
        pattern_session = {
            apply = function(d, targets)
                assert(d.width == 3 and d.height == 1 and targets[1].slot == 2, 'Material reached Pattern upload')
                e.writes[#e.writes + 1] = { pattern = true, bytes = ffi.string(d.data, 48), targets = targets }
                return #targets
            end,
        },
    }
    e.pattern_groups = {}
    e.pattern_editor = {
        selections = { armor = 900 },
        undo = { 'unchanged' },
        scan = function(background)
            assert(background == true)
            e.scans = e.scans + 1
            return e.pattern_groups
        end,
        stop_flash = function()
            e.flash_stops = e.flash_stops + 1
            e.flashing = false
            return true
        end,
        flashing = function()
            return e.flashing
        end,
    }
    local function entry(path, width, object, slot)
        local d = {
            width = width,
            height = 1,
            data = ffi.new('float[?]', width * 4),
            resource = string.format('%016x', object),
        }
        for i = 0, width * 4 - 1 do
            d.data[i] = (i - 7) * 0.125
        end
        ffi.cast('uint32_t *', d.data)[3] = 0x80000000
        local b = { slot = slot, original = object, current = object, armor = true }
        local group = { object = object, bindings = { b } }
        e.palettes[#e.palettes + 1], e.documents[path], e.objects[d.resource] = path, d, object
        e.originals_by_object[object] = { width = width, height = 1, resource = d.resource }
        if slot == 1 then
            e.groups[#e.groups + 1] = group
        else
            e.pattern_groups[#e.pattern_groups + 1] = group
        end
        return d, b
    end
    e.material, e.material_target = entry('material', 23, 100, 1)
    e.pattern, e.pattern_target = entry('pattern', 3, 900, 2)
    e.code = factory(e)
    return e
end
local e = fixture()
local plan = e.code.plan()
assert(plan.total == 2 and plan.matched == 2 and plan.unmatched == 0, 'Paired Pattern remained unmatched')
assert(e.scans == 1 and e.pattern_editor.undo[1] == 'unchanged' and e.pattern_editor.selections.armor == 900)
e.code.plan()
assert(e.scans == 1, 'Unchanged UI matching repeated native Pattern discovery')
assert(e.code.apply():find('2 matching LUTs', 1, true) and #e.writes == 2 and e.preserves == 1 and e.remembered == 1)
assert(
    e.writes[1].bytes == ffi.string(e.material.data, 368) and e.writes[2].bytes == ffi.string(e.pattern.data, 48),
    'Matching changed exact RGBA/HDR/signed-zero bytes'
)
assert(e.scans == 2 and e.flash_stops == 1, 'Apply failed to rediscover or stop Pattern flash')

e = fixture()
e.pattern_target.stale = true
assert(not pcall(e.code.apply) and #e.writes == 0, 'Stale Pattern partially applied the paired material')
e = fixture()
e.pattern_target.foreign = 7777
assert(not pcall(e.code.apply) and #e.writes == 0, 'Foreign Pattern ownership partially applied the import')
e = fixture()
e.originals_by_object[900] = nil
assert(not pcall(e.code.apply) and #e.writes == 0, 'Missing Pattern snapshot applied a partial appearance')
e = fixture()
e.pattern_target.slot = 1
assert(not pcall(e.code.apply) and #e.writes == 0, 'Pattern document fell through to a23-column material slot')

e = fixture()
e.objects[e.pattern.resource] = 9999
plan = e.code.plan()
assert(plan.matched == 1 and plan.unmatched == 1, 'Unmatched Pattern acquired an ordinal/material fallback')
assert(e.code.apply() and #e.writes == 1 and not e.writes[1].pattern)
e = fixture()
e.palettes[#e.palettes + 1] = 'duplicate-pattern'
e.documents['duplicate-pattern'] = e.pattern
plan = e.code.plan()
assert(plan.matched == 1 and plan.ambiguous == 2, 'Ambiguous Pattern resource was applied')
assert(e.code.apply() and #e.writes == 1 and not e.writes[1].pattern)
e = fixture()
e.material.resource = e.pattern.resource
plan = e.code.plan()
assert(plan.matched == 0 and plan.ambiguous == 2, 'Cross-shape duplicate resource escaped ambiguity checks')
assert(not pcall(e.code.apply) and #e.writes == 0)
e = fixture()
e.pattern_target.cape = true
plan = e.code.plan()
assert(plan.matched == 1 and plan.unmatched == 1, 'Matching changed existing Cape exclusion')

e = fixture()
e.flashing = true
e.pattern_editor.all_groups = e.pattern_groups
assert(
    e.code.plan().matched == 2 and e.scans == 0 and e.flash_stops == 0,
    'Passive matching stopped active Pattern highlighting'
)
assert(e.code.apply() and e.scans == 1 and e.flash_stops == 1)
print(
    'PASS Pattern import matching: exact resources/shapes, dedicated owned slot/session, bit-exact material+Pattern uploads, quiet UI discovery and atomic stale/foreign/snapshot/ambiguity guards'
)
