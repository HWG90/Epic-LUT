local M = dofile('src/weapons/lut_catalog_match.lua')
local A, B = 0x100000, 0x200000
local function id(value)
    return string.format('%016x', value)
end
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
local function fixture(text, wanted)
    local lookups, validations, objects, validate_hook, lookup_hook = {}, 0, {}, nil, nil
    local deps = {
        lookup = function(hex)
            lookups[#lookups + 1] = hex
            if lookup_hook then
                return lookup_hook(hex)
            end
            return objects[hex]
        end,
        validate = function()
            validations = validations + 1
            if validate_hook then
                return validate_hook(validations)
            end
            return true
        end,
    }
    return {
        matcher = M.new(deps, text, wanted or { [A] = true }),
        lookups = lookups,
        objects = objects,
        validations = function()
            return validations
        end,
        validate = function(hook)
            validate_hook = hook
        end,
        lookup = function(hook)
            lookup_hook = hook
        end,
    }
end
test('cooperative chunks are bounded to eight by default and sixteen maximum', function()
    local lines = {}
    for index = 1, 25 do
        lines[index] = id(index)
    end
    local f = fixture(table.concat(lines, '\n'))
    local first = f.matcher.step()
    assert(first.state == 'running' and first.processed == 8 and #f.lookups == 8 and f.validations() == 2)
    local second = f.matcher.step(16)
    assert(second.state == 'running' and second.processed == 24 and #f.lookups == 24 and f.validations() == 4)
    local done = f.matcher.step(16)
    assert(done.complete and not done.refused and done.processed == 25 and done.total == 25 and f.validations() == 6)
    f.matcher.step(16)
    assert(#f.lookups == 25 and f.validations() == 6)
end)
test('all exact resource aliases survive and repeated IDs are deduplicated', function()
    local f = fixture(
        '000000000000ABCD\r\n000000000000abcd\r\n' .. id(2) .. '\r\n' .. id(3) .. '\r\n',
        { [A] = true, [B] = true }
    )
    f.objects['000000000000abcd'], f.objects[id(2)], f.objects[id(3)] = A, A, B
    local done = f.matcher.step()
    assert(done.complete and done.total == 3 and done.input_count == 4 and done.duplicates == 1 and #f.lookups == 3)
    assert(#done.matches[A] == 2 and done.matches[A][1] == '000000000000abcd' and done.matches[A][2] == id(2))
    assert(#done.matches[B] == 1 and done.matches[B][1] == id(3))
end)
test('unloaded and unrelated objects are reported without guessed matches', function()
    local f = fixture(id(1) .. '\n' .. id(2), { [A] = true, [B] = true })
    f.objects[id(2)] = 0x300000
    local done = f.matcher.step()
    assert(done.complete and #done.matches[A] == 0 and #done.matches[B] == 0)
end)
test('malformed, empty and oversized catalogs fail before callbacks', function()
    for _, text in ipairs({ '', id(1) .. '\n\n', id(1) .. ' ', '000000000000000g', id(1) .. '\0', id(1) .. '\r' }) do
        local f = fixture(text)
        assert(f.matcher.result().refused and #f.lookups == 0 and f.validations() == 0)
    end
    local f = fixture(string.rep('a', M.MAX_BYTES + 1))
    assert(f.matcher.result().refused)
    f = fixture(string.rep(id(1) .. '\n', M.MAX_ITEMS + 1))
    assert(f.matcher.result().refused and f.matcher.result().reason:find('Catalog item bounds', 1, true))
end)
test('wanted sets and chunk budgets are validated', function()
    for _, wanted in ipairs({ {}, { [A] = false }, { ['100000'] = true }, { [1] = true }, { [math.huge] = true } }) do
        local f = fixture(id(1), wanted)
        assert(f.matcher.result().refused)
    end
    local f = fixture(id(1))
    assert(f.matcher.step(17).refused and #f.lookups == 0)
    f = fixture(id(1))
    assert(f.matcher.step(0).refused and #f.lookups == 0)
    f = fixture(id(1))
    assert(f.matcher.step('8').refused and #f.lookups == 0)
end)
test('lookup errors refuse the operation without publishing a partial chunk', function()
    local f = fixture(id(1) .. '\n' .. id(2))
    f.lookup(function(hex)
        if hex == id(1) then
            return A
        end
        error('lookup failed')
    end)
    local refused = f.matcher.step()
    assert(refused.refused and refused.processed == 0 and next(refused.matches) == nil)
    assert(refused.reason:find('lookup failed', 1, true) and f.validations() == 1)
    f.matcher.step()
    assert(#f.lookups == 2)
    f = fixture(id(1))
    f.lookup(function()
        return {}
    end)
    assert(f.matcher.step().refused)
end)
test('stale identity before or after any chunk clears every tentative alias', function()
    local f = fixture(id(1))
    f.objects[id(1)] = A
    f.validate(function()
        return nil, 'weapon swapped'
    end)
    local failed = f.matcher.step()
    assert(failed.refused and #f.lookups == 0 and next(failed.matches) == nil)
    f = fixture(id(1))
    f.objects[id(1)] = A
    f.validate(function(count)
        return count == 1, 'weapon swapped after lookup'
    end)
    failed = f.matcher.step()
    assert(failed.refused and failed.processed == 0 and next(failed.matches) == nil)
    f = fixture(id(1) .. '\n' .. id(2))
    f.objects[id(1)] = A
    f.objects[id(2)] = A
    assert(#f.matcher.step(1).matches[A] == 1)
    f.validate(function()
        return false, 'avatar respawned'
    end)
    failed = f.matcher.step(1)
    assert(failed.refused and failed.processed == 1 and next(failed.matches) == nil)
    assert(failed.reason:find('avatar respawned', 1, true))
end)
test('result mutation cannot alter retained aliases or wanted targets', function()
    local wanted = { [A] = true }
    local f = fixture(id(1) .. '\n' .. id(2), wanted)
    f.objects[id(1)] = A
    f.objects[id(2)] = A
    wanted[A], wanted[B] = nil, true
    local first = f.matcher.step(1)
    first.matches[A][1] = 'foreign'
    first.matches[B] = { 'foreign' }
    local done = f.matcher.step(1)
    assert(done.complete and done.matches[A][1] == id(1) and done.matches[A][2] == id(2) and done.matches[B] == nil)
end)
print('PASS weapon LUT cooperative catalog match: ' .. cases .. ' focused contracts')
