local p = dofile('src/imports/import_protocol.lua')
assert(
    p.paths('job').progress == 'job.txt.progress' and p.paths('job').cancel == 'job.txt.cancel',
    'Worker paths disagree'
)
local v = assert(p.progress('42\textracting\t100\t57\tv2 / 8 LUTs extracted', 42, 100))
assert(v.percent == 57 and v.detail == 'v2 / 8 LUTs extracted')
assert(p.progress('42\tpicker\t100', 42, 100).percent == 0, 'Legacy heartbeat rejected')
for _, text in ipairs({ '7\tpicker\t100', '42\tunknown\t100', '42\tpicker\t103', string.rep('x', 513) }) do
    assert(not p.progress(text, 42, 100), 'Invalid heartbeat accepted')
end
local result = p.result('ok\nlut001.dds\nlut015.dds')
assert(result.names[2] == 'lut015.dds' and p.result('cancel').canceled)
assert(p.result('preset\npreset.tsv\nShared Set').label == 'Shared Set', 'Shared preset result rejected')
for _, text in ipairs({
    'ok',
    'ok\n../outside.dds',
    'ok\nlut001.dds\nlut001.dds',
    'preset\n../preset.tsv\nShared',
    'preset\npreset.tsv\n../Shared',
    'preset\npreset.tsv\nShared\nextra',
    string.rep('x', 8193),
}) do
    assert(not pcall(p.result, text), 'Invalid result accepted')
end
print('PASS import protocol: unified paths, heartbeat versions, ownership/time validation and bounded result filenames')
