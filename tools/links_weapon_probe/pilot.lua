-- Explicit apply/restore diagnostic. Uses production runtime/session ownership.
-- Root controls execution; preparation alone never runs this script.
local rows, baselines, runtime, discovery, memory, Engine, native, selected
local read_into
local done, restored, began, applied_at = false, false, nil, nil
local records = {}
local function failure_status()
    if (records.native_allocations or 0) == 0 and (records.native_writes or 0) == 0 then
        return 'refused_before_apply'
    end
    return records.applied and 'refused_after_apply' or 'refused_during_apply'
end
local function add(...)
    local fields = {}
    for index = 1, select('#', ...) do
        fields[index] = tostring(select(index, ...)):gsub('[\t\r\n]', ' ')
    end
    rows[#rows + 1] = table.concat(fields, '\t')
end
local function flush(state, reason)
    add('result', state, reason or '')
    save_file('r6_weapon_pilot.tsv', table.concat(rows, '\n') .. '\n')
    out('R6 weapon pilot', state, reason or '', 'r6_weapon_pilot.tsv')
end
local function read_bytes(address, size)
    return memory.read(ffi.cast('const uint8_t *', address), size)
end
read_into = function(address, size, buffer)
    return memory.read_into(ffi.cast('const uint8_t *', address), size, buffer)
end
local function module_address(name)
    local found = memory.module(name)
    return found and memory.address(found)
end
local function proof(phase, candidate)
    local validated = {}
    local small, large = ffi.new('uint8_t[16]'), ffi.new('uint8_t[1024]')
    for _, baseline in ipairs(baselines) do
        local binding = baseline.binding
        if not validated[binding.receipt] then
            local valid, why = discovery.validate(binding.receipt)
            assert(valid, why)
            validated[binding.receipt] = true
        end
        local mesh = tonumber(native.mesh(binding.unit, binding.mesh_index))
        local lua_mesh = stingray.Unit.mesh(binding.receipt.lua_unit, binding.mesh_index + 1)
        assert(mesh == binding.mesh and tonumber(ffi.cast('uintptr_t', lua_mesh)) == mesh,
            'Pilot captured mesh changed')
        assert(binding.material_index < tonumber(native.materials(mesh))
            and tonumber(native.material(mesh, binding.material_index)) == binding.material,
            'Pilot captured material changed')
        local object = Engine.binding(read_into, binding.material, binding.slot, small, large)
        local expected = baseline.selected and candidate or baseline.object
        add('binding', phase, binding.weapon_slot, baseline.family, binding.save_key,
            binding.mesh_index, binding.material_index, baseline.object, object, expected)
        assert(object == expected, 'Pilot changed an unselected destination or failed binding readback')
    end
end
local function cleanup()
    if restored or not runtime then
        return
    end
    local ok, complete = pcall(runtime.restore, 1)
    if ok and complete then
        restored = true
        records.state = 'restored'
        local checked, reason = pcall(proof, 'cleanup_restored', selected and selected.object)
        if not checked then
            records.state = 'quarantined'
            add('cleanup', 'binding proof unavailable', tostring(reason))
        end
    else
        records.state = 'quarantined'
        add('cleanup', 'retained until game exit', tostring(complete))
    end
    -- Never destroy a pilot texture or release its float array, even after a
    -- successful restore. No new renderer retirement API is introduced here.
    add('retention', records.state, #records.retain.records, records.retain.bytes)
    add('cleanup_result', records.state, records.native_allocations or 0, records.native_writes or 0)
    if not done then
        flush(failure_status(), 'Pilot stopped; cleanup outcome recorded separately and GPU backing retained')
    end
end
local function collect()
    rows, baselines = {}, {}
    local Primary = use('r6_weapon_probe_primary_identity')
    local Discovery = use('r6_weapon_probe_weapon_discovery')
    local Runtime = use('r6_weapon_probe_weapon_runtime')
    local Session = use('r6_weapon_probe_binding_session')
    local DDS = use('r6_weapon_probe_dds')
    Engine = use('r6_weapon_probe_engine')
    memory = use('r6_weapon_probe_bingus_memory').new(use('r6_weapon_probe_bingus_runtime'))
    local config = assert(load_file('r6_weapon_pilot.cfg'), 'Prepared pilot configuration missing')
    assert(#config <= 512, 'Pilot configuration bounds')
    local wanted_resource = assert(config:match('resource=(%x+)\n'), 'Pilot LUT ID missing')
    local wanted_weapon = assert(config:match('weapon=(%x+)\n'), 'Pilot weapon configuration missing')
    assert(#wanted_resource == 16 and #wanted_weapon == 16, 'Pilot identity lengths')
    local source = assert(load_file('r6_weapon_pilot_dds.hex'), 'Prepared original DDS missing')
    assert(#source <= 2 * DDS.MAX_BYTES and #source % 2 == 0 and source:match('^%x+$'), 'Pilot DDS hex bounds')
    local data, width, height = DDS.decode(unhex(source))
    assert(width == 23 and height == 8, 'Pilot requires proven 23 x 8 primary material LUT')
    local document = { data = data, width = width, height = height, resource = wanted_resource }
    local identity = Primary.new({ module = module_address, read = read_bytes, verify_build = memory.verify_build })
    assert(identity.validate())
    local snapshot, why = identity.snapshot(1)
    assert(snapshot and snapshot.weapon_resource64 == wanted_weapon, why or 'Pilot primary configuration changed')
    local opened, reason = Engine.open(memory, module_address('game.dll'), module_address())
    assert(opened, reason)
    native = opened
    discovery = Discovery.new(assert(rawget(_G, 'stingray')), {
        identity = identity, native = native, read = read_bytes,
    })
    local retained = package.loaded['epic.links.weapon.pilot.retained.v1'] or { runs = {} }
    package.loaded['epic.links.weapon.pilot.retained.v1'] = retained
    records = { state = 'prepared', retain = { records = {}, cache = {}, bytes = 0 }, cohort = { sessions = {} } }
    retained.runs[#retained.runs + 1] = records
    local small = ffi.new('uint8_t[96]')
    local target_object = assert(Engine.texture_object(native, wanted_resource), 'Pilot stock resource is not loaded')
    runtime = Runtime.new({
        discovery = discovery, binding_session = Session, retain = records.retain, cohort = records.cohort,
        document = function(object, binding, family)
            assert(object == target_object and binding.weapon_slot == 1 and family == 'material',
                'Pilot requested an unapproved source document')
            return document
        end,
        bind = function(binding, object)
            local allowed, why = discovery.write_guard(binding)
            assert(allowed, why)
            records.native_writes = (records.native_writes or 0) + 1
            add('native_bind', binding.save_key, binding.original, object)
            Engine.bind(native, binding.material, binding.slot, object)
            native.commit(binding.mesh)
        end,
        create_texture = function(w, h, pixels)
            assert(w == width and h == height, 'Pilot allocation dimensions changed')
            records.native_allocations = (records.native_allocations or 0) + 1
            add('native_allocation', w, h, w * h * 16)
            return Engine.create_texture(native, w, h, pixels, read_into, small)
        end,
        validate_document = DDS.validate,
    })
    records.runtime = runtime -- Keep cleanup receipts and backing alive on failure.
    began = memory.time()
    add('source', 'r6_weapon_pilot_manifest.json', config:match('dds_sha256=(%x+)'))
    add('pilot', wanted_weapon, wanted_resource, 'Base RGB row 1', '1,0,1', 'Alpha and all other channels preserved')
    for slot = 1, 3 do
        local catalog, unavailable = runtime.refresh(slot)
        if catalog then
            if slot == 1 then
                assert(catalog.weapon_resource64 == wanted_weapon, 'Pilot primary identity changed during refresh')
            end
            for _, family in ipairs({ 'material', 'pattern' }) do
                for index, group in ipairs(catalog[family]) do
                    local chosen = slot == 1 and family == 'material' and group.object == target_object
                    if chosen then
                        assert(not selected, 'Pilot resource group is ambiguous')
                        selected = { index = index, object = group.object, bindings = group.bindings }
                    end
                    for _, binding in ipairs(group.bindings) do
                        baselines[#baselines + 1] = { binding = binding, family = family,
                            object = discovery.binding(binding), selected = chosen }
                    end
                end
            end
        else
            add('slot', slot, 'unavailable', unavailable)
        end
        coroutine.yield()
    end
    assert(selected and #selected.bindings == 5, 'Pilot requires the five proven primary body LOD bindings')
    local changed = runtime.load(1, selected.index, 'material')
    local before = ffi.string(changed.data, width * height * 16)
    changed.data[0], changed.data[1], changed.data[2] = 1, 0, 1
    assert(ffi.string(changed.data, width * height * 16):sub(13) == before:sub(13), 'Pilot changed non-RGB channels')
    proof('before', selected.object)
    records.state = 'applying'
    local count, texture = runtime.apply(changed, 1, selected.index, 'material')
    assert(count == 5 and texture and texture.object ~= selected.object, 'Pilot did not bind all body LODs')
    records.applied = true
    records.state = 'applied'
    proof('applied', texture.object)
    applied_at = memory.time()
    out('Primary body RGB pilot applied to', count, 'LOD bindings; restoring in two seconds')
    repeat coroutine.yield() until memory.time() - applied_at >= 2
    assert(runtime.restore(1), 'Pilot original restoration could not be certified')
    restored, records.state = true, 'restored'
    proof('restored', selected.object)
    add('retention', 'kept until game exit', #records.retain.records, records.retain.bytes)
    flush('restored', 'All selected originals restored; other weapon and Pattern bindings unchanged')
    done = true
end
local job = coroutine.create(collect)
return function()
    if began and memory.time() - began > 30 then
        cleanup()
        flush(failure_status(), 'Pilot exceeded elapsed budget')
        done = true
        return true
    end
    local ok, why = coroutine.resume(job)
    if not ok then
        rows = rows or {}
        add('failure', tostring(why))
        cleanup()
        if not done then
            flush(failure_status(), tostring(why))
            done = true
        end
        return true
    end
    return coroutine.status(job) == 'dead'
end, cleanup
