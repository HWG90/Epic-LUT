local ffi = require('ffi')
local Apply = dofile('src/presets/armory_apply.lua')
local Gear = dofile('src/gear/gear_catalog.lua')
local LUT, PATTERN = 0x7e662968, 0x81d4c49d
local function doc(width, height, value)
    local d = {
        width = width,
        height = height,
        data = ffi.new('float[?]', width * height * 4),
        resource = '1111111111111111',
    }
    d.data[0] = value
    return d
end
local function fixture()
    local original, armor, weapon, pattern = doc(23, 8, 0.1), doc(23, 8, 0.5), doc(23, 8, 0.8), doc(3, 1, 0.3)
    local resource = '5fecab819f96a3e8'
    local entries = {
        { kind = 'armor', key = '0:1:0:0', document = armor, original = original },
        { kind = 'weapon', key = '3:1:0:0', weapon_slot = 1, weapon_resource = resource, document = weapon },
        { kind = 'weapon', key = '3:1:1:0', weapon_slot = 1, weapon_resource = resource, document = weapon },
        { kind = 'weapon', key = 'p:3:1:0:0', weapon_slot = 1, weapon_resource = resource, document = pattern },
    }
    local preset = {
        name = 'Mixed Weapons',
        entries = entries,
        armor = { armor },
        helmet = {},
        cape = {},
        weapon = { weapon, weapon, pattern },
    }
    local b = {
        armor = true,
        save_key = '0:1:0:0',
        unit = 1,
        mesh = 2,
        material = 3,
        original = 100,
        current = 200,
        slot = LUT,
    }
    local groups = { { object = 200, bindings = { b } } }
    local proof, menu = { armor = 'armor:1', helmet = 'helmet:1', cape = 'cape:1' }, {}
    local values = {
        gear = 0.1,
        weapon = 0.1,
        writes = 0,
        weapon_writes = 0,
        restored = 0,
        begins = 0,
        finishes = 0,
        clears = {},
        plans = {},
    }
    local fail_weapon, stale, mismatch, stale_after_gear = false, false, false, false
    local host = {
        selected = function()
            return preset
        end,
        cape_available = function()
            return false
        end,
        stop_identification = function()
            return true
        end,
        has_patterns = function()
            return false
        end,
        refresh = function() end,
        scan_patterns = function() end,
        groups = function()
            return groups
        end,
        pattern_groups = function()
            return {}
        end,
        material_session = function()
            return { owned = { b } }
        end,
        pattern_session = function() end,
        present = function()
            return true
        end,
        binding = function(item)
            return item.current
        end,
        original = function()
            return original
        end,
        proof = function()
            return proof
        end,
        documents = function()
            return {}
        end,
        document = function(_, _, is_pattern)
            return not is_pattern and armor or nil
        end,
        key = function(item)
            return item.save_key
        end,
        resource = function()
            return true
        end,
        resource_id = function()
            return original.resource
        end,
        capture = function()
            return values.gear
        end,
        restore = function(before)
            values.gear, values.restored = before, values.restored + 1
            return true
        end,
        clear_default = function(kind)
            assert(kind ~= 'weapon')
            values.clears[#values.clears + 1] = kind
        end,
        begin_application = function()
            values.begins = values.begins + 1
        end,
        finish_application = function()
            values.finishes = values.finishes + 1
            if stale_after_gear then
                stale = true
            end
        end,
        apply_batch = function(d, targets)
            values.writes, values.gear = values.writes + 1, tonumber(d.data[0])
            return #targets
        end,
        remember_basic = function() end,
        capture_history = function()
            return {}
        end,
        record_history = function() end,
        menu = function()
            return menu
        end,
        choices = function(container)
            return container == 'armor' and { { kind = 'armor', group = 1, key = 'gear:armor:1', ordinal = 1 } } or {}
        end,
        target = function()
            return { kind = 'armor', object = 200, binding_keys = { ['0:1:0:0:' .. LUT] = b.save_key } }
        end,
        message = function(message)
            values.message = message
            return message
        end,
        weapon_plan = function(received, options)
            assert(received == preset and options.associated_patterns == true)
            local plan = {
                choices = {
                    {
                        id = 'weapon:1:body',
                        label = 'Primary Body LUT 1',
                        enabled = true,
                        weapon_slot = 1,
                        weapon_resource = mismatch and 'ffffffffffffffff' or resource,
                        has_pattern = true,
                    },
                },
                validate = function()
                    return not stale, stale and 'Weapon generation changed' or nil
                end,
                count = 3,
                options = options,
            }
            values.plans[#values.plans + 1] = plan
            return plan
        end,
        apply_weapon_plan = function(plan)
            assert(plan.validate() and plan.options.associated_patterns)
            if plan.options.selected then
                assert(plan.options.selected['weapon:1:body'], 'Selected weapon LUT was lost')
            end
            local before = values.weapon
            values.weapon, values.weapon_writes = tonumber(weapon.data[0]), values.weapon_writes + 1
            if fail_weapon then
                values.weapon = before
                error('Atomic weapon transaction failed')
            end
            return 3
        end,
    }
    local service = Apply.new({ gear_catalog = Gear, material_slot = LUT, pattern_slot = PATTERN }, host)
    return {
        service = service,
        host = host,
        values = values,
        preset = preset,
        menu = menu,
        proof = proof,
        stale = function(value)
            stale = value
        end,
        fail = function(value)
            fail_weapon = value
        end,
        mismatch = function(value)
            mismatch = value
        end,
        stale_after_gear = function(value)
            stale_after_gear = value
        end,
    }
end
local f = fixture()
f.service.apply({ armor = true, weapon = true })
assert(f.values.writes == 1 and f.values.weapon_writes == 1 and f.values.finishes == 1 and f.values.begins == 1)
assert(math.abs(f.values.gear - 0.5) < 0.001 and math.abs(f.values.weapon - 0.8) < 0.001)
assert(f.values.plans[1].count == 3 and f.values.message:find('Weapons', 1, true))
local only = fixture()
only.service.apply({ weapon = true })
assert(
    only.values.writes == 0
        and only.values.begins == 0
        and only.values.finishes == 0
        and #only.values.clears == 0
        and only.values.weapon_writes == 1
)
local rollback = fixture()
rollback.fail(true)
assert(not pcall(rollback.service.apply, { armor = true, weapon = true }))
assert(
    rollback.values.restored == 1 and rollback.values.gear == 0.1 and rollback.values.weapon == 0.1,
    'Mixed transaction did not restore garments after atomic weapon failure'
)
local stale = fixture()
stale.stale(true)
assert(
    not pcall(stale.service.apply, { armor = true, weapon = true })
        and stale.values.writes == 0
        and stale.values.weapon_writes == 0
)
local after = fixture()
after.stale_after_gear(true)
assert(
    not pcall(after.service.apply, { armor = true, weapon = true })
        and after.values.restored == 1
        and after.values.weapon_writes == 0
)
local mismatch = fixture()
mismatch.mismatch(true)
assert(
    not pcall(mismatch.service.apply, { armor = true, weapon = true })
        and mismatch.values.writes == 0
        and mismatch.values.weapon_writes == 0
)
local chooser = fixture()
chooser.service.choose_luts()
local dialog = chooser.menu.lut_apply_dialog
assert(dialog.select_all and #dialog.columns == 3 and dialog.columns[3].title == 'Primary Weapons')
assert(dialog.columns[3].items[1].detail == 'Pattern included' and dialog.columns[3].items[1].checked)
assert(dialog.on_apply({ ['gear:armor:1'] = true, ['weapon:1:body'] = true }))
assert(chooser.values.writes == 1 and chooser.values.weapon_writes == 1 and chooser.menu.lut_apply_dialog == nil)
local saved_identity = fixture()
saved_identity.service.choose_luts()
saved_identity.preset.entries[2].weapon_resource = 'ffffffffffffffff'
assert(not pcall(saved_identity.menu.lut_apply_dialog.on_apply, { ['weapon:1:body'] = true }))
assert(saved_identity.values.writes == 0 and saved_identity.values.weapon_writes == 0)
local changed = fixture()
changed.service.choose_luts()
changed.stale(true)
assert(
    not pcall(changed.menu.lut_apply_dialog.on_apply, { ['weapon:1:body'] = true })
        and changed.values.weapon_writes == 0
)
local plain = fixture()
plain.host.weapon_plan, plain.host.apply_weapon_plan = nil, nil
plain.service.apply('armor')
assert(plain.values.writes == 1 and plain.values.weapon_writes == 0, 'Garment-only preset acquired a weapon dependency')
print(
    'PASS: mixed weapon Armory planning, all-LOD/Pattern application hooks, atomic garment rollback, chooser and configuration/metadata preflight'
)
