local R = dofile('src/core/resource_ids.lua')
local Store = dofile('vendor/menu/store.lua')
local function copy(values)
    local result = {}
    for key, value in pairs(values) do
        result[key] = value
    end
    return result
end
local function rejected(labels, hash, name)
    local ok, result = pcall(labels.set, hash, name)
    assert(not ok or result == false, 'Invalid label edit was accepted')
end
local stored, writes, fail = {}, 0, false
local storage = {
    load = function(id)
        assert(id == 'epic_lut_labels')
        return copy(stored)
    end,
    save = function(id, values)
        assert(id == 'epic_lut_labels')
        writes = writes + 1
        if fail then
            return false, 'Label save unavailable'
        end
        stored = copy(values)
        return true
    end,
}
local labels = R.labels(storage)
local hash, neighbor = 'FFFFFFFFFFFFFFFF', 'fffffffffffffffe'
assert(labels.get(hash) == nil)
assert(labels.set(hash, '  Helmet Primary  '))
assert(labels.get(hash) == 'Helmet Primary' and labels.get(hash:lower()) == 'Helmet Primary')
assert(stored[hash:lower()] == 'Helmet Primary' and stored[hash] == nil, 'Hash casing created duplicate labels')
assert(labels.set(neighbor, 'Cape-Accent_1'))
assert(
    labels.get(hash) == 'Helmet Primary' and labels.get(neighbor) == 'Cape-Accent_1',
    'Adjacent high 64-bit hashes aliased'
)
local reopened = R.labels(storage)
assert(reopened.get(hash) == 'Helmet Primary' and reopened.get(neighbor) == 'Cape-Accent_1')
assert(reopened.set(hash, 'Renamed'))
assert(R.labels(storage).get(hash) == 'Renamed', 'Rename did not survive reopening')
local before = writes
for _, bad in ipairs({ '', 'fffffffffffffff', 'fffffffffffffffff', 'zzzzzzzzzzzzzzzz', '../outside' }) do
    rejected(reopened, bad, 'Invalid')
end
rejected(reopened, nil, 'Invalid')
for _, bad in ipairs({ 'line\nbreak', 'tabs\tname', '../outside', 'Color:Name', string.rep('x', 49), '#123456' }) do
    rejected(reopened, hash, bad)
end
rejected(reopened, hash, 42)
assert(writes == before and reopened.get(hash) == 'Renamed', 'Validation wrote or changed the saved label')
assert(reopened.set(hash, string.rep('x', 48)) and #reopened.get(hash) == 48)
fail = true
rejected(reopened, hash, 'Unsaved')
assert(
    reopened.get(hash) == string.rep('x', 48) and stored[hash:lower()] == string.rep('x', 48),
    'Failed save committed a label'
)
rejected(reopened, hash, '')
assert(reopened.get(hash) ~= nil, 'Failed deletion lost a label')
fail = false
assert(reopened.set(hash, '   ') and reopened.get(hash) == nil and stored[hash:lower()] == nil)
assert(
    R.labels(storage).get(hash) == nil and R.labels(storage).get(neighbor) == 'Cape-Accent_1',
    'Deletion removed another resource label'
)

-- Corrupt saved entries are ignored, and resource-name strings never execute.
local malformed = R.labels({
    load = function()
        return {
            ['0000000000000001'] = 'Valid Label',
            ['0000000000000002'] = 'error("do not execute")',
            ['0000000000000003'] = true,
            ['0000000000000004'] = string.rep('x', 49),
            ['0000000000000005'] = '',
            ['not-a-hash'] = 'Invalid key',
        }
    end,
    save = function()
        return true
    end,
})
assert(malformed.get('0000000000000001') == 'Valid Label')
for i = 2, 5 do
    assert(malformed.get(string.format('%016x', i)) == nil, 'Malformed stored alias was loaded')
end

-- Bounded aliases can be replaced/deleted at capacity, without blocking startup.
local full = {}
for i = 1, 513 do
    full[string.format('%016x', i)] = 'LUT ' .. i
end
local bounded = R.labels({
    load = function()
        return full
    end,
    save = function()
        return true
    end,
})
local count, present
count = 0
for i = 1, 513 do
    local key = string.format('%016x', i)
    if bounded.get(key) then
        count, present = count + 1, key
    end
end
assert(count == 512, 'Stored resource labels exceeded or lost the bounded alias budget')
rejected(bounded, 'abcdef0123456789', 'Too many')
assert(bounded.set(present, 'At capacity'))
assert(bounded.set(present, '') and bounded.set('abcdef0123456789', 'New slot'))

-- Exercise the native INI store's publish/restore path in the workspace fixture.
local target = 'tests/tmp/presets/epic_lut_labels.ini'
for _, suffix in ipairs({ '', '.tmp', '.bak' }) do
    os.remove(target .. suffix)
end
local disk = Store.new('tests/tmp/presets')
local native = R.labels(disk)
assert(native.set(hash, 'Before save failure'))
local function bytes(path)
    local f = assert(io.open(path, 'rb'))
    local result = f:read('*a')
    assert(f:close())
    return result
end
local previous_bytes, rename = bytes(target), os.rename
os.rename = function(source, destination)
    if source == target .. '.tmp' and destination == target then
        return nil, 'Injected publish failure'
    end
    return rename(source, destination)
end
local ok, result = pcall(native.set, hash, 'Not published')
os.rename = rename
assert(not ok or result == false, 'Native label publish failure was accepted')
assert(
    native.get(hash) == 'Before save failure' and bytes(target) == previous_bytes,
    'Failed publish lost memory or the previous INI file'
)
assert(R.labels(disk).get(hash) == 'Before save failure', 'Backup restoration did not survive reopening')
assert(native.set(hash, 'After recovery') and R.labels(disk).get(hash) == 'After recovery')
local oversized = assert(io.open(target, 'wb'))
assert(oversized:write(string.rep('x', 65537)) and oversized:close())
assert(R.labels(disk).get(hash) == nil, 'Oversized backing file bypassed native store limit')
for _, suffix in ipairs({ '', '.tmp', '.bak' }) do
    os.remove(target .. suffix)
end
print(
    'PASS resource labels: exact 64-bit identity, trim/rename/delete persistence, bounded malformed input, failed-save retention and native backup recovery'
)
