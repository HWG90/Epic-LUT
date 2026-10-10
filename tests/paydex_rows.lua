local ffi = require('ffi')
local dds = dofile('src/core/dds.lua')
local P = dofile('src/presets/paydex_rows.lua')
local function row(value)
    local pixels = ffi.new('float[92]')
    for i = 0, 91 do
        pixels[i] = value + i * 0.03125
    end
    ffi.cast('uint32_t*', pixels)[0] = 0x80000000
    pixels[3], pixels[8], pixels[91] = -0.125, 13.25, 5
    return dds.encode(pixels, 23, 1)
end
local a, b = row(0.25), row(0.75)
local function fixture()
    local files = { ['job/rows.tsv'] = 'row-A.dds\nrow-B.dds\n', ['job/row-A.dds'] = a, ['job/row-B.dds'] = b }
    local writes, moved = {}, {}
    local deps = {
        folder = 'presets',
        dds = dds,
        read = function(path, limit, optional)
            local value = files[path]
            assert(value or optional, 'File missing: ' .. path)
            assert(not value or #value <= limit, 'Read budget exceeded')
            return value
        end,
        write = function(path, value)
            files[path] = value
            writes[#writes + 1] = path
            return true
        end,
        move = function(source, target)
            assert(files[source] and not files[target], 'Rename would replace a file')
            files[target], files[source] = files[source], nil
            moved[#moved + 1] = target
            return true
        end,
        remove = function(path)
            files[path] = nil
            return true
        end,
    }
    return deps, files, writes, moved
end
local deps, files = fixture()
files['presets/row-A.dds'], files['presets/row-B.dds'] = b, b
local names, count = P.new(deps).import('job', 'rows.tsv')
assert(names[1] == 'A-2' and names[2] == 'B' and count == 1, 'Preset conflicts were not preserved/deduplicated')
assert(files['presets/row-A.dds'] == b and files['presets/row-A-2.dds'] == a and files['presets/row-B.dds'] == b)
names, count = P.new(deps).import('job', 'rows.tsv')
assert(names[1] == 'A-2' and count == 0, 'Repeat import multiplied identical presets')
for _, text in ipairs({
    '',
    'row-../outside.dds',
    'row-A.dds\nrow-a.dds',
    'row-' .. string.rep('A', 49) .. '.dds',
    string.rep('x', P.MAX_MANIFEST + 1),
}) do
    assert(not pcall(P.manifest, text), 'Invalid row manifest accepted')
end
local invalid_deps, invalid_files, invalid_writes = fixture()
invalid_files['job/row-B.dds'] = dds.encode(ffi.new('float[23 * 8 * 4]'), 23, 8)
assert(not pcall(P.new(invalid_deps).import, 'job', 'rows.tsv'))
assert(#invalid_writes == 0 and not invalid_files['presets/row-A.dds'], 'Late invalid row published an earlier preset')
local stage_deps, stage_files = fixture()
stage_files['job/publish-1.pending'] = a
assert(not pcall(P.new(stage_deps).import, 'job', 'rows.tsv'))
assert(stage_files['job/publish-1.pending'] == a, 'Rejected foreign stage was deleted')
local fail_deps, fail_files = fixture()
local move = fail_deps.move
fail_deps.move = function(source, target)
    if target == 'presets/row-B.dds' then
        error('Publication failure')
    end
    return move(source, target)
end
assert(not pcall(P.new(fail_deps).import, 'job', 'rows.tsv'))
assert(
    not fail_files['presets/row-A.dds'] and not fail_files['presets/row-B.dds'],
    'Partial row publication survived rollback'
)
assert(not fail_files['job/publish-1.pending'] and not fail_files['job/publish-2.pending'])
assert(fail_files['job/row-A.dds'] == a and fail_files['job/row-B.dds'] == b, 'Rollback removed input rows')
local foreign_deps, foreign_files = fixture()
local foreign_move = foreign_deps.move
foreign_deps.move = function(source, target)
    if target == 'presets/row-B.dds' then
        foreign_files['presets/row-A.dds'] = 'replacement by another writer'
        error('Publication failure')
    end
    return foreign_move(source, target)
end
assert(not pcall(P.new(foreign_deps).import, 'job', 'rows.tsv'))
assert(foreign_files['presets/row-A.dds'] == 'replacement by another writer', 'Rollback removed a foreign replacement')
print(
    'PASS Paydex rows: exact HDR/alpha/signed-zero DDS, complete preflight, bounded names, collision preservation, repeat-import reuse, rollback and foreign-stage/replacement protection'
)
