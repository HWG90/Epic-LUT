local P, C = dofile('src/presets/binding_provenance.lua'), dofile('src/presets/binding_source_cache.lua')
local files, dirs, time, starts, stops, closes = {}, {}, 0, 0, 0, 0
local running, stop_ready = false, true
local patch_names = {}
local io_fake = {
    open = function(path, mode)
        if mode == 'rb' and files[path] == nil then
            return nil
        end
        if mode == 'wb' then
            files[path] = ''
        end
        local at = 0
        return {
            read = function(_, n)
                local v = files[path]:sub(at + 1, at + n)
                at = at + #v
                return v
            end,
            write = function(_, v)
                files[path] = files[path] .. v
                return true
            end,
            close = function()
                return true
            end,
            seek = function(_, which, n)
                at = which == 'end' and #files[path] + (n or 0) or which == 'set' and (n or 0) or at + (n or 0)
                return at
            end,
        }
    end,
}
local paths = {
    cache = 'C:/fixture',
    directory_exists = function(path)
        return dirs[path]
    end,
    mkdir_new = function(path)
        dirs[path] = true
    end,
}
local m = {
    binding_provenance = P,
    binding_provenance_script = '61',
    binding_provenance_reader = '62',
    original_snapshot_reader = '63',
    windows = {
        files = function()
            return patch_names
        end,
        verify_interface = function()
            return {}, {
                epic_native_pid = function()
                    return 123
                end,
            }
        end,
        game_data = function()
            return 'C:/game/data'
        end,
        launch_worker = function(command, folder)
            assert(
                command:find('-Request "C:/fixture/binding%-sources/request.tsv"')
                    and command:find('-OwnerPID 123', 1, true)
                    and folder == 'C:/fixture/binding-worker'
            )
            starts = starts + 1
            return {
                running = function()
                    return running
                end,
                stop = function()
                    stops = stops + 1
                    if stop_ready then
                        running = false
                    end
                    return stop_ready
                end,
                close = function()
                    closes = closes + 1
                end,
            }
        end,
    },
}
local function new(mode)
    return C.new(m, {
        paths = paths,
        io = io_fake,
        time = function()
            return time
        end,
        mode = mode,
    })
end
local stamp, request = ('A'):rep(64), ('B'):rep(64)
local folder = 'C:/fixture/binding-sources/' .. stamp .. '/' .. request
local unit_id, mat_id = '0000000000000111', '0000000000000222'
local function dataset()
    files['C:/fixture/binding-sources/error.txt'] = ''
    files['C:/fixture/binding-sources/complete.txt'] = folder .. '\n1\n' .. stamp .. '\n'
    local lines = {}
    for _, item in ipairs({ { unit_id, P.UNIT, 'unit bytes' }, { mat_id, P.MATERIAL, 'material bytes' } }) do
        local stem = item[1] .. '.' .. item[2]
        files[folder .. '/' .. stem .. '.main'] = item[3]
        files[folder .. '/' .. stem .. '.toc'] = ('t'):rep(80)
        lines[#lines + 1] = table.concat({
            item[2],
            item[1],
            '1234567890abcdef',
            stem .. '.main',
            '-',
            '-',
            stem .. '.toc',
            P.digest(item[3]),
            '-',
            '-',
        }, '\t')
    end
    files[folder .. '/resources.tsv'] = table.concat(lines, '\n') .. '\n'
    local collision = {
        P.UNIT .. '\t' .. unit_id .. '\n',
        P.MATERIAL .. '\t' .. mat_id .. '\n',
        'cd4238c6a0c69e32\t0000000000000999\n',
    }
    table.sort(collision)
    files[folder .. '/collisions.tsv'] = table.concat(collision)
    files[folder .. '/collisions.meta'] = '3\n' .. P.digest(files[folder .. '/collisions.tsv']) .. '\n'
    files[folder .. '/scope.meta'] = 'top-level-game-data-patches-v1\n0\n' .. P.digest('') .. '\n'
end
local units = { { resource = unit_id, archive = '1234567890abcdef' } }
local cache = new()
assert(cache.start(units) and cache.state == 'loading' and starts == 1)
assert(files['C:/fixture/binding-sources/request.tsv'] == unit_id .. '\t1234567890abcdef\n')
assert(cache.start(units) and starts == 1, 'Identical request started a second worker')
running = true
time = 1
cache.tick()
assert(cache.state == 'loading' and not cache.get())
dataset()
running = false
time = 2
cache.tick()
assert(cache.state == 'ready' and cache.get() == cache and cache.index_stamp == stamp:lower() and closes == 1)
assert(cache.validate_scope(), 'Unchanged empty patch scope was refused')
local unit = assert(cache.unit(unit_id))
assert(unit.main == 'unit bytes' and unit.gpu == '' and #unit.toc == 80 and unit.archive == '1234567890abcdef')
files[folder .. '/' .. unit_id .. '.' .. P.UNIT .. '.main'] = 'mutated after load'
assert(cache.unit(unit_id) == unit and unit.main == 'unit bytes', 'Loaded pristine bytes were reread/mutated')
assert(not cache.id_available(P.UNIT, unit_id) and not cache.id_available(P.MATERIAL, mat_id))
assert(not cache.id_available('cd4238c6a0c69e32', '0000000000000999'), 'Collision query ignored an unloaded resource')
assert(cache.id_available(P.MATERIAL, '0000000000000001') and cache.id_available(P.UNIT, 'ffffffffffffffff'))
files[folder .. '/collisions.tsv'] = files[folder .. '/collisions.tsv']:sub(1, -35)
assert(not pcall(cache.id_available, P.MATERIAL, mat_id), 'Incomplete collision catalog was accepted')
assert(cache.close() and not cache.get())
dataset()
local function invalid(mutator, text)
    local cache = new()
    assert(cache.start(units))
    dataset()
    mutator()
    time = time + 1
    cache.tick()
    assert(cache.state == 'failed' and cache.error:find(text, 1, true), cache.error)
    cache.close()
end
invalid(function()
    files['C:/fixture/binding-sources/complete.txt'] = 'C:/elsewhere/' .. stamp .. '\n1\n' .. stamp
end, 'escapes')
invalid(function()
    files['C:/fixture/binding-sources/complete.txt'] = folder .. '\n2\n' .. stamp
end, 'schema')
invalid(function()
    files[folder .. '/scope.meta'] = nil
end, 'scope proof')
invalid(function()
    files[folder .. '/resources.tsv'] =
        files[folder .. '/resources.tsv']:gsub(unit_id .. '%.' .. P.UNIT .. '%.main', 'evil.main')
end, 'filename')
invalid(function()
    files[folder .. '/resources.tsv'] = files[folder .. '/resources.tsv']
        .. files[folder .. '/resources.tsv']:match('[^\n]+')
        .. '\n'
end, 'Duplicate')
invalid(function()
    files[folder .. '/collisions.meta'] = '4\n' .. ('c'):rep(64) .. '\n'
end, 'incomplete')
invalid(function()
    files[folder .. '/collisions.tsv'] = files[folder .. '/collisions.tsv']:gsub('0999', '0888')
end, 'digest differs')
cache = new()
assert(cache.start(units))
dataset()
time = time + 1
cache.tick()
files[folder .. '/' .. unit_id .. '.' .. P.UNIT .. '.main'] = 'bad bytes'
assert(not pcall(cache.unit, unit_id), 'Tampered pristine source bytes passed recorded SHA256')
cache.close()
invalid(function()
    files['C:/fixture/binding-sources/error.txt'] = 'Worker rejected ambiguous resources'
end, 'ambiguous')
local patch = '0123456789abcdef.patch_1'
patch_names = { patch, patch .. '.gpu_resources', patch .. '.stream' }
files['C:/game/data/' .. patch] = 'MAIN'
files['C:/game/data/' .. patch .. '.gpu_resources'] = 'GPU'
files['C:/game/data/' .. patch .. '.stream'] = 'STREAM'
local receipt = patch
    .. '\t4\t'
    .. P.digest('MAIN')
    .. '\t3\t'
    .. P.digest('GPU')
    .. '\t6\t'
    .. P.digest('STREAM')
    .. '\t\n'
cache = new()
assert(cache.start(units))
dataset()
files[folder .. '/scope.meta'] = 'top-level-game-data-patches-v1\n1\n' .. P.digest(receipt) .. '\n'
time = time + 1
cache.tick()
local scope_lengths = {}
m.binding_provenance = setmetatable({
    digest = function(bytes, expected)
        if type(bytes) == 'function' then
            assert(expected ~= nil, 'Patch scope hashing omitted its measured file size')
            scope_lengths[#scope_lengths + 1] = expected
        end
        return P.digest(bytes, expected)
    end,
}, { __index = P })
assert(cache.validate_scope())
assert(
    #scope_lengths == 3 and scope_lengths[1] == 4 and scope_lengths[2] == 3 and scope_lengths[3] == 6,
    'Patch scope hashing did not pass each exact measured file size'
)
files['C:/game/data/' .. patch .. '.gpu_resources'] = 'BAD'
assert(
    not cache.validate_scope() and cache.state == 'stale',
    'Changed same-size GPU patch body reused stale provenance'
)
m.binding_provenance = P
patch_names = {}
cache.close()
cache = new()
running = true
assert(cache.start(units))
stop_ready = false
assert(not cache.close() and cache.worker and cache.state == 'loading', 'Pending worker cleanup was forgotten')
stop_ready = true
assert(cache.close() and stops >= 2)
running = false
local stock_launch = m.windows.launch_worker
m.windows.launch_worker = function(command, scripts)
    assert(command:find(' -Mode weapon_effective', 1, true))
    assert(command:find('binding-sources-weapon-effective/request.tsv', 1, true))
    assert(scripts == 'C:/fixture/binding-worker-weapon-effective')
    return stock_launch(command:gsub('%-weapon%-effective', ''), scripts:gsub('%-weapon%-effective', ''))
end
local effective_folder = folder:gsub('binding%-sources/', 'binding-sources-weapon-effective/')
local effective_root = 'C:/fixture/binding-sources-weapon-effective'
local function effective_dataset()
    dataset()
    local copy = {}
    for path, bytes in pairs(files) do
        if path:find('C:/fixture/binding-sources/', 1, true) == 1 then
            copy[path:gsub('binding%-sources/', 'binding-sources-weapon-effective/')] = bytes
        end
    end
    for path, bytes in pairs(copy) do
        files[path] = bytes
    end
    files[effective_root .. '/complete.txt'] = effective_folder .. '\n2\n' .. stamp .. '\n'
    files[effective_folder .. '/sources.tsv'] = P.UNIT
        .. '\t'
        .. unit_id
        .. '\tloose\t1234567890abcdef.patch_34\t'
        .. P.digest('')
        .. '\n'
        .. P.MATERIAL
        .. '\t'
        .. mat_id
        .. '\tpacked\t1234567890abcdef\t'
        .. P.digest('')
        .. '\n'
end
cache = new('weapon_effective')
assert(cache.mode == 'weapon_effective' and cache.start(units))
effective_dataset()
time = time + 1
cache.tick()
assert(cache.state == 'ready' and cache.validate_scope())
unit = assert(cache.unit(unit_id))
assert(
    unit.source_mode == 'weapon_effective'
        and unit.source_kind == 'loose'
        and unit.source_file == '1234567890abcdef.patch_34'
        and unit.source_scope == P.digest('')
)
assert(cache.material(mat_id).source_kind == 'packed')
assert(cache.close())
local function invalid_effective(mutator, expected)
    local current = new('weapon_effective')
    assert(current.start(units))
    effective_dataset()
    mutator()
    time = time + 1
    current.tick()
    assert(current.state == 'failed' and current.error:find(expected, 1, true), current.error)
    current.close()
end
invalid_effective(function()
    files[effective_root .. '/complete.txt'] = effective_folder .. '\n1\n' .. stamp .. '\n'
end, 'schema')
invalid_effective(function()
    files[effective_folder .. '/sources.tsv'] = nil
end, 'receipt unavailable')
invalid_effective(function()
    files[effective_folder .. '/sources.tsv'] =
        files[effective_folder .. '/sources.tsv']:gsub('patch_34', 'patch_34/evil')
end, 'origin differs')
invalid_effective(function()
    files[effective_folder .. '/sources.tsv'] = files[effective_folder .. '/sources.tsv']:gsub('loose', 'guessed')
end, 'origin differs')
invalid_effective(function()
    files[effective_folder .. '/sources.tsv'] =
        files[effective_folder .. '/sources.tsv']:gsub(P.digest(''), ('a'):rep(64))
end, 'scope receipt differs')
invalid_effective(function()
    files[effective_folder .. '/sources.tsv'] = files[effective_folder .. '/sources.tsv']:match('[^\n]+') .. '\n'
end, 'incomplete')
invalid_effective(function()
    files[effective_folder .. '/sources.tsv'] = files[effective_folder .. '/sources.tsv']
        .. files[effective_folder .. '/sources.tsv']:match('[^\n]+')
        .. '\n'
end, 'Duplicate effective')
m.windows.launch_worker = stock_launch
assert(not pcall(new, 'guessed_priority'), 'Unsupported cache mode accepted')
print(
    'PASS binding source cache: owned worker lifecycle, exact bounded parts, immutable data, collision/scope checks, isolated weapon-effective mode and validated source receipts'
)
