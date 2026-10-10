local C = dofile('src/preview/player_authored_clip.lua')
local ffi = require('ffi')
local function u16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end
local function u32(n)
    return u16(n % 65536) .. u16(math.floor(n / 65536))
end
local function f32(n)
    local p = ffi.new('float[1]', n)
    return ffi.string(p, 4)
end
local function vec(v)
    return f32(v[1]) .. f32(v[2]) .. f32(v[3])
end
local names = { 'boss', 'hips', 'r_elbow', 'r_hand', 'r_index_finger1' }
local identity = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function bones()
    local s = u32(#names) .. u32(0)
    for i = 1, #names do
        s = s .. u32(i)
    end
    for _, name in ipairs(names) do
        s = s .. name .. '\0'
    end
    return s
end
local function rig()
    local s = string.rep('\0', 52) .. u32(64) .. string.rep('\0', 8) .. u32(#names) .. string.rep('\0', 12)
    for _ = 1, #names do
        for _, v in ipairs(identity) do
            s = s .. f32(v)
        end
        s = s .. vec({ 0, 0, 0 }) .. vec({ 1, 1, 1 }) .. f32(0)
    end
    s = s .. string.rep('\0', #names * 64)
    for i = 1, #names do
        s = s .. u16(1) .. u16(i == 1 and 0 or i - 2)
    end
    for i = 1, #names do
        s = s .. u32(i)
    end
    return s
end
local function compressed_rotation(q)
    local largest = 3
    local bits = largest
    for i = 0, 2 do
        local value = q[(largest + i + 1) % 4 + 1]
        local n = math.floor(value / 0.75 * 512 + 512 + 0.5)
        bits = bits + n * 2 ^ (2 + 10 * i)
    end
    return u32(bits)
end
local function compressed_key(bone, time, kind, payload)
    local ms = math.floor(time * 1000 + 0.5)
    return string.char(
        (bone % 16) * 16 + math.floor(ms / 65536),
        kind * 64 + math.floor(bone / 16),
        ms % 256,
        math.floor(ms / 256) % 256
    ) .. payload
end
local function uncompressed_key(bone, time, subtype, payload)
    return u16(subtype) .. u32(bone) .. f32(time) .. payload
end
local function clip(held, additive, twist)
    local initials = ''
    local points = { { 0, 0, 1 }, { 0, 0, 0 }, { 0.3, 0, 0.5 }, { 0.3, 0, 0 }, { 0.1, 0, 0 } }
    for i, p in ipairs(points) do
        local q = held and i == 3 and { 0, 0, math.sqrt(0.5), math.sqrt(0.5) }
            or held and i == 5 and { math.sqrt(0.5), 0, 0, math.sqrt(0.5) }
            or twist and i == 2 and { 0, 0, math.sin(0.1), math.cos(0.1) }
            or { 0, 0, 0, 1 }
        initials = initials
            .. vec(p)
            .. f32(q[1])
            .. f32(q[2])
            .. f32(q[3])
            .. f32(q[4])
            .. vec(additive and i == 1 and { 0, 0, 0 } or { 1, 1, 1 })
    end
    local tracks = compressed_key(4, 1, 3, compressed_rotation({ math.sqrt(0.5), 0, 0, math.sqrt(0.5) }))
        .. uncompressed_key(2, 1, 4, vec({ 0.3, 0, 0.6 }))
        .. compressed_key(0, 1, 2, u16(32767) .. u16(32767) .. u16(32767 + 3277))
        .. compressed_key(1, 1, 1, u16(36044) .. u16(36044) .. u16(36044))
        .. uncompressed_key(0, 0.2, 2, '') -- authored sound marker: never played
    if twist then
        tracks = tracks
            .. uncompressed_key(1, 0.5, 5, f32(0) .. f32(0) .. f32(math.sin(0.4)) .. f32(math.cos(0.4)))
            .. uncompressed_key(1, 1, 5, f32(0) .. f32(0) .. f32(0) .. f32(1))
    end
    local flag_bytes = math.ceil(#names * 3 / 8)
    flag_bytes = flag_bytes + flag_bytes % 2
    local body = u16(0) .. string.rep('\0', flag_bytes) .. initials .. tracks .. u16(3)
    return u32(0) .. u32(#names) .. f32(1) .. u32(24 + #body) .. u32(0) .. u32(0) .. body
end
local resources = {
    unit = rig(),
    bones = bones(),
    standing = clip(false, nil, true),
    enter = clip(false),
    hold = clip(true),
    exit = clip(true),
}
local set = C.decode(resources)
assert(#set.names == 5 and set.clips.enter.duration == 1)
local initial, phase = C.sample(set, 0)
assert(
    phase == 'saluting' and math.abs(initial.r_hand[13] - 0.3) < 0.001 and math.abs(initial.r_hand[14] - 0.3) < 0.001,
    'Local authored transforms were not composed through parents'
)
assert(math.abs(set.clips.standing.channels[2].q[2].value[3]) > 0.3, 'Fixture has no moving hips')
for _, time in ipairs({ 0.25, 0.5, 0.9, 1.25, 2.75, 3.1, 4.5, 6.5, 7, 9.999, 10.5, 12.75, 120, 3600 }) do
    local held, held_phase, age = C.sample(set, time)
    assert(held_phase == 'saluting' and age == 0, 'Salute pose was released')
    for name, pose in pairs(initial) do
        for i = 1, 16 do
            assert(math.abs(held[name][i] - pose[i]) < 1e-12, 'Held salute pose changed: ' .. name)
        end
    end
end
local held, held_phase = C.sample(set, 4.5)
assert(
    held_phase == 'saluting' and math.abs(held.r_hand[13] - 0.3) < 0.001 and math.abs(held.r_hand[14] - 0.3) < 0.001,
    'Authored forearm quaternion did not rotate the hand'
)
local p, q, scale = C.pose(held.r_index_finger1)
assert(math.abs(q[1]) + math.abs(q[2]) > 0.3, 'Authored curled-finger quaternion was lost')
assert(math.abs(scale[1] - 1) < 1e-6 and p[1] == p[1])
for _, t in ipairs({ -1, 0 / 0, math.huge, 'bad' }) do
    assert(not pcall(C.sample, set, t))
end
-- Initial flags use little-endian bit order and compressed rotation/vector fields.
local compressed = clip(false)
local prefix = compressed:sub(1, 26)
local payload = u16(32767)
    .. u16(32767)
    .. u16(36044)
    .. compressed_rotation({ 0, 0, 0, 1 })
    .. u16(36044)
    .. u16(36044)
    .. u16(36044)
local original_initial_size = 40
local rebuilt = prefix .. string.char(7, 0) .. payload .. compressed:sub(29 + original_initial_size)
rebuilt = rebuilt:sub(1, 12) .. u32(#rebuilt) .. rebuilt:sub(17)
local compressed_resources = {
    unit = resources.unit,
    bones = resources.bones,
    standing = rebuilt,
    enter = rebuilt,
    hold = rebuilt,
    exit = rebuilt,
}
assert(C.decode(compressed_resources), 'Compressed initial transforms failed')
-- Exact game footer shape: duplicate record with a zero second size field.
local body = clip(false)
local end_at = #body
local first = body .. u32(end_at)
first = first:sub(1, 12) .. u32(#first * 2) .. first:sub(17)
local second = first:sub(1, 12) .. u32(0) .. first:sub(17)
local duplicated = {
    unit = resources.unit,
    bones = resources.bones,
    standing = first .. second,
    enter = first .. second,
    hold = first .. second,
    exit = first .. second,
}
assert(C.decode(duplicated).clips.hold.duration == 1, 'Repeated serialized record doubled playback duration')
for _, fault in ipairs({ 'short', 'nan', 'additive', 'count', 'cycle', 'bone', 'footer', 'names' }) do
    local bad = {}
    for k, v in pairs(resources) do
        bad[k] = v
    end
    if fault == 'short' then
        bad.enter = bad.enter:sub(1, -3)
    elseif fault == 'nan' then
        bad.enter = bad.enter:sub(1, 8) .. u32(2139095040) .. bad.enter:sub(13)
    elseif fault == 'additive' then
        bad.enter = clip(false, true)
    elseif fault == 'count' then
        bad.enter = bad.enter:sub(1, 4) .. u32(513) .. bad.enter:sub(9)
    elseif fault == 'cycle' then
        local at = 64 + 16 + #names * 128 + 4
        bad.unit = bad.unit:sub(1, at + 1) .. u16(1) .. bad.unit:sub(at + 4 + 1)
    elseif fault == 'bone' then
        local track_at = 24 + 2 + 2 + #names * 40
        bad.enter = bad.enter:sub(1, track_at) .. compressed_key(9, 1, 3, compressed_rotation({ 0, 0, 0, 1 })) .. u16(3)
        bad.enter = bad.enter:sub(1, 12) .. u32(#bad.enter) .. bad.enter:sub(17)
    elseif fault == 'footer' then
        bad.enter = (first .. second):sub(1, -2) .. string.char(1)
    else
        bad.bones = bad.bones .. 'extra\0'
    end
    assert(not pcall(C.decode, bad), 'Malformed authored data accepted: ' .. fault)
end
print(
    'PASS authored clip CPU parser: held salute across elapsed time, authored salute/finger FK, compressed/uncompressed transforms, sound exclusion, scales and malformed bounds'
)
return { module = C, resources = resources, set = set }
