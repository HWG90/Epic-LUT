local ffi = require('ffi')
local O = dofile('src/gear/original_luts.lua')
local original = { width = 23, height = 2, data = ffi.new('float[?]', 23 * 2 * 4) }
local imported = { width = 23, height = 2, data = ffi.new('float[?]', 23 * 2 * 4) }
for i = 0, 23 * 2 * 4 - 1 do
    original.data[i] = 0
    imported.data[i] = 0.75
end
original.data[(23 + 13) * 4] = 0.0125
original.data[23 * 4 + 3] = 2
local protected = O.preserve(imported, original)
assert(protected.data[13 * 4] == 0, 'Game-original zero emission was replaced with imported glow')
assert(
    protected.data[(23 + 13) * 4] == original.data[(23 + 13) * 4],
    'Game-original nonzero emissive strength was not preserved'
)
assert(protected.data[23 * 4 + 3] == 2 and protected.data[0] == 0.75 and imported.data[13 * 4] == 0.75)
assert(not pcall(O.preserve, imported, nil), 'Missing readback was silently converted into a zero value')
local D = dofile('src/core/dds.lua')
D.write('tests/tmp/files/armor-00000001-0-0123456789abcdef-original.dds', original.data, 23, 2)
local m = {
    dds = D,
    windows = {
        files = function()
            return { 'armor-00000001-0-0123456789abcdef-original.dds' }
        end,
    },
    engine = {
        texture_object = function(_, hash)
            assert(hash == '0123456789abcdef')
            return 123
        end,
    },
}
local aliases = 'tests/tmp/files/armor-00000001-0-0123456789abcdef-original.source-archives'
local alias_file = assert(io.open(aliases, 'wb'))
assert(alias_file:write('aaaaaaaaaaaaaaaa.patch_2\nbbbbbbbbbbbbbbbb.patch_0\n'))
assert(alias_file:close())
local resolver = O.new(m, { files = 'tests/tmp/files' }, {})
local found = resolver.get(123)
assert(
    found and found.data[(23 + 13) * 4] == original.data[(23 + 13) * 4] and not resolver.get(456),
    'Original snapshot was assigned to the wrong live resource'
)
assert(found.source_archives and found.source_archives:find('aaaaaaaaaaaaaaaa.patch_2', 1, true))
assert(not found.patch_source, 'Color agreement fabricated archive provenance')
os.remove(aliases)
print(
    'PASS game-original emissives: resource ID/object match, valid zero and nonzero strengths, original mode retained, imported colors untouched and missing-reference rejection'
)

-- Snapshot worker errors must never escape into the editor update loop.
local closed = 0
local fake = {
    dds = D,
    original_snapshot_script = '23',
    original_snapshot_reader = '23',
    engine = m.engine,
    windows = {
        files = m.windows.files,
        verify_interface = function()
            return {}, {
                epic_native_pid = function()
                    return 1
                end,
            }
        end,
        launch_worker = function()
            return {
                running = function()
                    error('injected worker polling failure')
                end,
                stop = function()
                    error('injected stop failure')
                end,
                close = function()
                    closed = closed + 1
                end,
            }
        end,
    },
}
local safe = O.new(
    fake,
    { files = 'tests/tmp/files', originals = 'tests/tmp/files', cache = 'tests/tmp/cache' },
    {},
    function()
        return { [123] = true }
    end
)
safe.start()
assert(pcall(safe.tick), 'Snapshot error escaped into editor update')
assert(
    closed == 1 and safe.status:find('paused', 1, true),
    'Snapshot failure did not release ownership and report status'
)
assert(pcall(safe.close), 'Snapshot cleanup failure escaped')

local five = { width = 23, height = 5, data = ffi.new('float[?]', 23 * 5 * 4) }
local eight = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
for i = 0, 23 * 8 * 4 - 1 do
    eight.data[i] = i / 100
end
for row = 0, 4 do
    five.data[(row * 23 + 13) * 4] = row / 10
    five.data[row * 23 * 4 + 3] = row % 4
end
local variant = O.preserve(eight, five)
assert(variant.height == 5 and variant.width == 23, 'Preservation did not retain target row count')
for row = 0, 4 do
    assert(variant.data[row * 23 * 4] == eight.data[row * 23 * 4], 'Imported row colors were remapped')
    assert(variant.data[(row * 23 + 13) * 4] == five.data[(row * 23 + 13) * 4], 'Original five-row emissives changed')
end
assert(not pcall(O.preserve, five, eight), 'Missing imported rows were invented')

local custom = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
for i = 0, 23 * 64 * 4 - 1 do
    custom.data[i] = i / 101
end
local retained = O.preserve(custom, eight, true)
assert(
    retained.height == 64
        and ffi.string(retained.data + 23 * 8 * 4, 23 * 56 * 16)
            == ffi.string(custom.data + 23 * 8 * 4, 23 * 56 * 16),
    'Preserving original emissives truncated custom rows'
)
assert(retained.data[13 * 4] == eight.data[13 * 4], 'Known original emissives changed for custom rows')

-- Existing base-game cache markers cannot authorize current colors until the
-- worker has validated the installed patch scope. Explicit reload repeats it.
do
    local open = io.open
    local ok, why = pcall(function()
        local prefix, hash = 'snapshot-fixture/', '0123456789abcdef'
        local old_stamp, custom_stamp, updated_stamp = string.rep('a', 64), string.rep('b', 64), string.rep('c', 64)
        local files = {
            [prefix .. 'originals/index-complete.txt'] = old_stamp .. '\n1',
            [prefix .. 'originals/complete.txt'] = old_stamp .. '\n1',
            [prefix .. 'originals/' .. old_stamp .. '/game-' .. hash .. '-original.dds'] = 'stock',
        }
        local source, running, indexed, captures, listed = {}, true, 0, 0, 0
        source.stock, source.custom, source.updated = original, eight, custom
        io.open = function(path, mode)
            if path:sub(1, #prefix) ~= prefix then
                return open(path, mode)
            end
            if mode == 'rb' then
                if not files[path] then
                    return nil
                end
                return {
                    read = function()
                        return files[path]
                    end,
                    close = function()
                        return true
                    end,
                }
            end
            return {
                write = function(_, text)
                    files[path] = text
                    return true
                end,
                close = function()
                    return true
                end,
            }
        end
        local modules = {
            original_snapshot_script = '23',
            original_snapshot_reader = '23',
            dds = {
                MAX_BYTES = 65536,
                decode = function(bytes)
                    local d = assert(source[bytes])
                    return d.data, d.width, d.height
                end,
            },
            engine = m.engine,
            windows = {
                files = function(path)
                    listed = listed + 1
                    assert(path ~= prefix .. 'originals/' .. old_stamp, 'Unvalidated stock cache was read')
                    return { 'game-' .. hash .. '-original.dds' }
                end,
                verify_interface = fake.windows.verify_interface,
                launch_worker = function(arguments)
                    if arguments:find('-IndexOnly', 1, true) then
                        indexed = indexed + 1
                    else
                        captures = captures + 1
                    end
                    running = true
                    return {
                        running = function()
                            return running
                        end,
                        close = function() end,
                        stop = function() end,
                    }
                end,
            },
        }
        local reader
        local resolve_cape, in_refresh, recursive_refreshes = false, false, 0
        reader = O.new(modules, { originals = prefix .. 'originals', cache = prefix .. 'cache' }, {}, function()
            -- Production chain: targets -> refresh -> sync_armory_cape ->
            -- armory_cape_available -> appearance_resource -> original.get.
            -- Bound the old recursion here so a failing test cannot freeze.
            if in_refresh then
                recursive_refreshes = recursive_refreshes + 1
                return { [123] = true }
            end
            in_refresh = true
            if resolve_cape then reader.get(123) end
            in_refresh = false
            return { [123] = true }
        end)
        assert(
            reader.get(123) == nil and not reader.loaded and indexed == 1 and listed == 0,
            'Startup exposed a stock snapshot before installed custom sources were checked'
        )
        local function complete(stamp, pixels)
            files[prefix .. 'originals/index-complete.txt'] = stamp .. '\n1'
            files[prefix .. 'originals/' .. stamp .. '/catalog.txt'] = hash .. '\n'
            running = false
            reader.tick()
            assert(not reader.loaded and reader.worker, 'Index validation skipped current LUT capture')
            files[prefix .. 'originals/complete.txt'] = stamp .. '\n1'
            files[prefix .. 'originals/' .. stamp .. '/game-' .. hash .. '-original.dds'] = pixels
            running = false
            reader.tick()
        end
        complete(custom_stamp, 'custom')
        assert(reader.get(123).data == eight.data and captures == 1)
        reader.retry()
        assert(
            indexed == 2 and reader.get(123) == nil and not reader.loaded,
            'Load Current Gear reused pixels from an earlier custom patch scope'
        )
        resolve_cape = true -- A Cape-bearing preset is now selected after Restore.
        complete(updated_stamp, 'updated')
        assert(recursive_refreshes == 0, 'Snapshot metadata read recursively advanced the active matching job')
        assert(
            reader.get(123).data == custom.data and captures == 2,
            'Current custom source did not replace the previous snapshot at the same texture object'
        )
        reader.close()
    end)
    io.open = open
    assert(ok, why)
end
print(
    'PASS installed snapshot scope: no unvalidated stock cache, explicit source recheck and changed custom pixels at one live object'
)
