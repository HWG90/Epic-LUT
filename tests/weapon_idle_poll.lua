local Bridge = dofile('src/editor/weapon_bridge.lua')
local visible, assigned, polls, probes = false, false, 0, 0
local runtime = {
    enforce_assigned = function()
        probes = probes + 1
        return 0, {}, assigned
    end,
    update = function()
        polls = polls + 1
        return {}
    end,
    catalog = function()
        return nil
    end,
}
local bridge = Bridge.new({
    primary_identity = {
        new = function()
            return {}
        end,
    },
    weapon_discovery = {
        new = function()
            return {}
        end,
    },
    weapon_runtime = {
        new = function()
            return runtime
        end,
    },
    weapon_controller = {},
}, {
    memory = function()
        return {}
    end,
    native = function()
        return {}
    end,
    engine = function()
        return {}
    end,
    retain = function()
        return {}
    end,
    cohort = function()
        return {}
    end,
    visible = function()
        return visible
    end,
})
bridge.runtime()
for _ = 1, 120 do
    bridge.update(1 / 60)
end
assert(probes == 0 and polls == 0, 'Idle weapon service polled bindings')
visible, assigned = true, true
for _ = 1, 120 do
    bridge.update(1 / 60)
end
assert(probes == 0 and polls == 0, 'Visible assigned weapon service polled bindings')
bridge.equipment_changed()
for _ = 1, 120 do
    bridge.update(1 / 60)
end
assert(polls == 3 and probes == 0, 'Equip event did not cause exactly one scan per slot')
for _ = 1, 120 do
    bridge.update(1 / 60)
end
assert(polls == 3 and probes == 0, 'Equip event restarted constant polling')
print('PASS weapon event lifecycle: zero idle material probes; one validation per slot after equip')
