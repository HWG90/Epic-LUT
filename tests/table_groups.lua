local ffi = require('ffi')
local T = dofile('src/table_groups.lua')
local a, b, c = ffi.new('float[?]', 23 * 2 * 4), ffi.new('float[?]', 23 * 2 * 4), ffi.new('float[?]', 23 * 2 * 4)
for i = 0, 23 * 2 * 4 - 1 do
    a[i] = i / 17
    b[i] = a[i]
    c[i] = a[i]
end
local entries = {
    { index = 1, name = 'Table 1', width = 23, height = 2, data = a },
    { index = 2, name = 'Table 2', width = 23, height = 2, data = b },
    { index = 3, name = 'Table 3', width = 23, height = 2, data = c },
}
local grouped = T.collapse(entries)
assert(#grouped == 1 and grouped[1].name:find('1-3', 1, true))
b[13 * 4] = 99
entries[2].revision = 1
grouped = T.collapse(entries)
assert(#grouped == 2, 'Emission-only edits did not split the table from its identical group')
b[13 * 4] = a[13 * 4]
entries[2].revision = 2
assert(#T.collapse(entries) == 1)
c[3] = 0.125
entries[3].revision = 1
assert(#T.collapse(entries) == 2, 'Alpha differences were collapsed based only on visible RGB')
print(
    'PASS identical-table grouping: all float fields compared, edits split groups, undo values merge groups and alpha/emission differences remain visible'
)
