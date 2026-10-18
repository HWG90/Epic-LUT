local Bridge = dofile('src/editor/weapon_bridge.lua')
local visible, assigned, polls, probes = false, false, 0, 0
local runtime = {
    enforce_assigned = function() probes = probes + 1; return 0, {}, assigned end,
    update = function() polls = polls + 1; return {} end,
    catalog = function() return nil end,
}
local bridge = Bridge.new({
    primary_identity = { new = function() return {} end },
    weapon_discovery = { new = function() return {} end },
    weapon_runtime = { new = function() return runtime end },
    weapon_controller = {},
}, {
    memory = function() return {} end,
    native = function() return {} end,
    engine = function() return {} end,
    retain = function() return {} end,
    cohort = function() return {} end,
    visible = function() return visible end,
})
bridge.runtime()
for _ = 1, 120 do bridge.update(1 / 60) end
assert(probes == 120 and polls == 0, 'Closed unused catalogs performed background native scans')
visible = true
bridge.update(0.1)
assert(polls == 1, 'Opening the menu did not resume catalog validation')
visible, assigned = false, true
bridge.update(0.1)
assert(polls == 2 and probes == 122, 'Closing the menu stopped assigned appearance validation')
print('PASS weapon idle polling: unused closed catalogs sleep; frame probes, visible scans and assigned recovery stay live')
