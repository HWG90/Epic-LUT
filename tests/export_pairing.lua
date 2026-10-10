local P = dofile('src/presets/export_pairing.lua')
local material = { width = 23, height = 8, data = {} }
local pattern = { width = 3, height = 1, data = {} }
assert(P.is_pattern(pattern) and not P.is_pattern(material))
assert(not P.is_pattern(nil) and not P.is_pattern({ width = 3, height = 2 }))

local deps = {
    key = function(b)
        return b.unit .. ':' .. b.mesh .. ':' .. b.material
    end,
    kind = function(b)
        return b.kind
    end,
}
local function binding(unit, kind, original, slot)
    return {
        unit = unit,
        mesh = 2,
        material = 3,
        kind = kind or 'armor',
        original = original,
        current = original,
        slot = slot,
    }
end
local a, b = binding(10, 'armor', 100, 1), binding(20, 'armor', 100, 1)
local pa, pb = binding(10, 'armor', 200, 2), binding(20, 'armor', 300, 2)
local unrelated = binding(30, 'armor', 200, 2)
local wrong_kind = binding(10, 'helmet', 200, 2)
pa.document, pb.document = pattern, pattern
local paired = P.live({ a, b }, { { bindings = { unrelated, wrong_kind, pb } }, { bindings = { pa } } }, deps)
assert(
    #paired == 2 and paired[1] == pb and paired[2] == pa,
    'Shared primary texture lost distinct Pattern destinations'
)
assert(#P.live({ a }, { { bindings = { unrelated, wrong_kind } } }, deps) == 0, 'Unrelated material or gear was paired')
assert(#P.live({ a }, {}, deps) == 0)
local alias = binding(10, 'armor', 200, 2)
assert(
    #P.live({ a, binding(10, 'armor', 100, 1) }, { { bindings = { pa, alias, pa } } }, deps) == 1,
    'Binding aliases were not deduplicated'
)
local conflict = binding(10, 'armor', 201, 2)
assert(not pcall(P.live, { a }, { { bindings = { pa, conflict } } }, deps), 'Conflicting Pattern slot was accepted')
conflict = binding(10, 'armor', 200, 3)
assert(not pcall(P.live, { a }, { { bindings = { pa, conflict } } }, deps), 'Different slots were collapsed')
assert(not pcall(P.live, { a, binding(10, 'armor', 101, 1) }, {}, deps), 'Conflicting primary slot was accepted')
assert(
    not pcall(P.live, { binding(10), binding(10) }, {}, deps),
    'Missing texture identities allowed unrelated records to collapse'
)
local invalid = binding(10, 'armor', 200, 2)
invalid.document = material
assert(not pcall(P.live, { a }, { { bindings = { invalid } } }, deps), 'Wrong Pattern dimensions accepted')
local texture = binding(10, 'armor', 200, 2)
texture.current, texture.document = 300, material
texture.texture = { object = 300, width = 3, height = 1, data = {} }
assert(P.live({ a }, { { bindings = { texture } } }, deps)[1] == texture, 'Applied Pattern document was ignored')

local function entry(kind, key, doc, original)
    return { kind = kind, key = key, document = doc, original = original }
end
local saved_a = entry('armor', '0:1:2:3', material)
local saved_b = entry('armor', '0:1:2:4', material)
local saved_pa = entry('armor', 'p:0:1:2:3', pattern)
local saved_pb = entry('armor', 'p:0:1:2:4', pattern)
local saved_helmet = entry('helmet', 'p:0:1:2:3', pattern)
local entries = { saved_pb, saved_b, saved_helmet, saved_a, saved_pa }
paired = P.saved(entries, 4)
assert(#paired == 2 and paired[1] == saved_a and paired[2] == saved_pa, 'Stored exact key/kind pairing failed')
paired = P.saved(entries, 2)
assert(#paired == 2 and paired[1] == saved_b and paired[2] == saved_pb, 'Shared documents merged distinct keys')
paired = P.saved(entries, 1)
assert(#paired == 1 and paired[1] == saved_pb, 'Selected Pattern was not standalone')
assert(#P.saved({ saved_a, saved_pb, saved_helmet }, 1) == 1, 'Pairing guessed by position or gear')
assert(#P.saved({ saved_a, saved_pa, entry('armor', saved_pa.key, pattern) }, 1) == 2, 'Stored aliases were duplicated')
assert(
    not pcall(P.saved, { saved_a, saved_pa, entry('armor', saved_pa.key, { width = 3, height = 1, data = {} }) }, 1),
    'Conflicting stored data accepted'
)
assert(
    not pcall(P.saved, { entry('armor', 'p:0:1:2:3', material) }, 1),
    'Pattern prefix with material dimensions accepted'
)
assert(not pcall(P.saved, { entry('armor', '0:1:2:3', pattern) }, 1), 'Pattern dimensions without prefix accepted')
assert(not pcall(P.saved, { entry('weapon', '0:1:2:3', material) }, 1), 'Unknown gear kind accepted')
assert(not pcall(P.saved, { entry('armor', 'bad-key', material) }, 1), 'Invalid slot key accepted')
assert(not pcall(P.saved, { entry('armor', '0:1:2:3', { width = 23, height = 65 }) }, 1), 'Unsupported height accepted')
assert(not pcall(P.saved, entries, 0) and not pcall(P.saved, entries, 1.5))
local legacy = entry('cape', '0:2', material)
local legacy_pattern = entry('cape', 'p:0:2', pattern)
assert(P.saved({ legacy, legacy_pattern }, 1)[2] == legacy_pattern, 'Legitimate legacy slot key rejected')
local many = {}
for i = 1, 4097 do
    many[i] = entry('armor', tostring(i), material)
end
assert(not pcall(P.saved, many, 1) and not pcall(P.live, many, {}, deps), 'Binding limit accepted')
local unrelated_patterns, unrelated_groups = {}, {}
for i = 1, 4097 do
    unrelated_patterns[i] = binding(1000 + i, 'armor', 200, 2)
    unrelated_groups[i] = { bindings = { unrelated_patterns[i] } }
end
unrelated_patterns[#unrelated_patterns + 1] = pa
unrelated_groups[#unrelated_groups + 1] = { bindings = { pa } }
assert(
    P.live({ a }, { { bindings = unrelated_patterns } }, deps)[1] == pa,
    'Unrelated bindings counted toward selected export limit'
)
assert(P.live({ a }, unrelated_groups, deps)[1] == pa, 'Unrelated groups counted toward selected export limit')
assert(not pcall(P.live, { a }, { { bindings = false } }, deps), 'Invalid Pattern group bindings accepted')
print('export pairing tests passed')
