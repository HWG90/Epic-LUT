-- Internal, texture-only Stingray patch writer. No converter or subprocess.
-- Layout reference: HD2SDK Community Edition, TocEntry/StreamToc and StingrayTexture.
local P = {}
-- The original LUT can occur in unrelated tutorial/prop archives. Its source
-- archive is provenance, not a reliable loaded patch destination. Match the
-- SDK's PatchBaseArchiveOnly default so one resource replacement is global.
P.BASE_ARCHIVE = '9ba626afa44a3aa3'
local bit = require('bit')
local function short(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function qword(n)
    return word(n) .. word(0)
end
local function hash(s)
    assert(type(s) == 'string' and #s == 16 and s:match('^[%x]+$'), 'Missing exact resource/archive ID')
    local chunks = {}
    for i = 15, 1, -2 do
        chunks[#chunks + 1] = string.char(tonumber(s:sub(i, i + 1), 16))
    end
    return table.concat(chunks)
end
local function uint(s, at)
    local a, b, c, d = s:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
function P.encode(dds, document, original)
    assert(original and original.patch_source, 'Original patch metadata unavailable; refresh original LUT snapshots')
    local source = original.patch_source
    assert(#source == 357 and source:sub(17, 17) == '\n', 'Invalid original patch metadata')
    local source_archive, template = source:sub(1, 16):lower(), source:sub(18)
    hash(source_archive)
    local archive = P.BASE_ARCHIVE
    local id = hash(original.resource)
    assert(template:sub(193, 196) == 'DDS ' and template:sub(277, 280) == 'DX10', 'Invalid native texture template')
    assert(uint(template, 320) == 2 or uint(template, 320) == 10, 'Original texture is not a supported float LUT')
    assert(
        uint(template, 324) == 3 and uint(template, 328) == 0 and uint(template, 332) == 1,
        'Only single-layer 2D LUT textures can be exported'
    )
    assert(
        document.width == original.width
            and (document.height == original.height or (document.width == 23 and document.height > 8 and document.height >= original.height))
            and uint(template, 208) == original.width
            and uint(template, 204) == original.height,
        'Editor LUT dimensions differ from selected destination'
    )
    assert(document.width == 23 or (document.width == 3 and document.height == 1), 'Unsupported patch LUT layout')
    local encoded = dds.encode(document.data, document.width, document.height)
    -- SDK writer preserves UnkID, disables streaming and clears all 15 mip descriptors.
    -- Export one unfiltered RGBA32F level: LUT rows are discrete material parameters.
    local body = template:sub(1, 4) .. word(0) .. word(4294967295) .. string.rep('\0', 180) .. encoded:sub(1, 148)
    local pixels = encoded:sub(149)
    local kind = hash('cd4238c6a0c69e32')
    local entry = id
        .. kind
        .. qword(184)
        .. qword(0)
        .. qword(0)
        .. qword(0)
        .. qword(0)
        .. word(#body)
        .. word(0)
        .. word(#pixels)
        .. word(16)
        .. word(64)
        .. word(1)
    local descriptor = qword(0) .. kind .. qword(1) .. word(16) .. word(64)
    local main = word(0xf0000011)
        .. word(1)
        .. word(1)
        .. word(0)
        .. string.rep('\0', 56)
        .. descriptor
        .. entry
        .. body
    return {
        archive = archive,
        source_archive = source_archive,
        resource = original.resource:lower(),
        main = main,
        gpu = pixels,
        stream = '',
    }
end
function P.encode_set(dds, documents)
    assert(
        type(documents) == 'table' and #documents > 0 and #documents <= 128,
        'No complete palette to export or too many LUTs'
    )
    local unique, ordered = {}, {}
    for _, item in ipairs(documents) do
        local patch = P.encode(dds, item.document, item.original)
        local previous = unique[patch.resource]
        if previous then
            assert(
                previous.main == patch.main and previous.gpu == patch.gpu,
                'Shared texture has conflicting applied palettes: ' .. patch.resource
            )
        else
            unique[patch.resource] = patch
            ordered[#ordered + 1] = patch
        end
    end
    table.sort(ordered, function(a, b)
        return a.resource < b.resource
    end)
    local count = #ordered
    local kind = hash('cd4238c6a0c69e32')
    local offset, gpu_offset = 104 + count * 80, 0
    local entries, bodies, gpu = {}, {}, {}
    for i, patch in ipairs(ordered) do
        local body = patch.main:sub(185)
        local aligned = math.ceil(gpu_offset / 64) * 64
        gpu[#gpu + 1] = string.rep('\0', aligned - gpu_offset)
        gpu[#gpu + 1] = patch.gpu
        entries[#entries + 1] = hash(patch.resource)
            .. kind
            .. qword(offset)
            .. qword(0)
            .. qword(aligned)
            .. qword(0)
            .. qword(0)
            .. word(#body)
            .. word(0)
            .. word(#patch.gpu)
            .. word(16)
            .. word(64)
            .. word(i)
        bodies[#bodies + 1] = body
        offset, gpu_offset = offset + #body, aligned + #patch.gpu
    end
    return {
        archive = P.BASE_ARCHIVE,
        resource = tostring(count) .. ' LUTs',
        count = count,
        main = word(0xf0000011)
            .. word(1)
            .. word(count)
            .. word(0)
            .. string.rep('\0', 56)
            .. qword(0)
            .. kind
            .. qword(count)
            .. word(16)
            .. word(64)
            .. table.concat(entries)
            .. table.concat(bodies),
        gpu = table.concat(gpu),
        stream = '',
    }
end
function P.new(folder, deps)
    local self = {}
    function self.save(name, document, original)
        assert(
            type(name) == 'string'
                and #name > 0
                and #name <= 48
                and name:match('^[%w _()%-]+$')
                and not name:match('^%s')
                and not name:match('%s$'),
            'Invalid patch export name'
        )
        assert(
            not name:upper():match('^CON$')
                and not name:upper():match('^PRN$')
                and not name:upper():match('^AUX$')
                and not name:upper():match('^NUL$')
                and not name:upper():match('^COM%d$')
                and not name:upper():match('^LPT%d$'),
            'Reserved export name'
        )
        local patch = original and P.encode(deps.dds, document, original) or P.encode_set(deps.dds, document)
        local zip = P.zip(patch)
        name = assert(deps.available_name, 'Export naming service unavailable')(name, function(candidate)
            return deps.directory_exists(folder .. '/' .. candidate)
                or deps.directory_exists(folder .. '/' .. candidate .. '.pending')
        end)
        local destination, staging = folder .. '/' .. name, folder .. '/' .. name .. '.pending'
        assert(not deps.directory_exists(destination), 'Patch export already exists; choose another name')
        deps.mkdir_new(staging)
        local files = {}
        local ok, why = pcall(function()
            local base = staging .. '/' .. patch.archive .. '.patch_0'
            for _, item in ipairs({
                { base, patch.main },
                { base .. '.gpu_resources', patch.gpu },
                { base .. '.stream', patch.stream },
                { staging .. '/' .. name .. '.zip', zip },
            }) do
                files[#files + 1] = item[1]
                local f = assert(io.open(item[1], 'wb'))
                local wrote, error = f:write(item[2])
                local closed, close_error = f:close()
                assert(wrote, error)
                assert(closed, close_error)
            end
            assert(os.rename(staging, destination)) -- Publish the complete triplet together.
        end)
        if not ok then
            for _, path in ipairs(files) do
                os.remove(path)
            end
            deps.rmdir(staging)
            error(why, 0)
        end
        return destination, patch.resource, destination .. '/' .. name .. '.zip'
    end
    return self
end
-- Standard ZIP, stored entries. LUT triplets are tiny; no compression library is needed.
local crc_table = {}
for n = 0, 255 do
    local crc = n
    for _ = 1, 8 do
        crc = bit.bxor(bit.rshift(crc, 1), bit.band(crc, 1) ~= 0 and 0xedb88320 or 0)
    end
    crc_table[n] = crc
end
local function crc32(bytes)
    local crc = -1
    for i = 1, #bytes do
        crc = bit.bxor(bit.rshift(crc, 8), crc_table[bit.band(bit.bxor(crc, bytes:byte(i)), 255)])
    end
    return bit.bnot(crc)
end
function P.zip(patch)
    local base = patch.archive .. '.patch_0'
    local local_records, central, offset = {}, {}, 0
    for _, entry in ipairs({
        { base, patch.main },
        { base .. '.gpu_resources', patch.gpu },
        { base .. '.stream', patch.stream },
    }) do
        local name, bytes = entry[1], entry[2]
        local crc = word(crc32(bytes))
        local common = short(20)
            .. short(0)
            .. short(0)
            .. short(0)
            .. short(33)
            .. crc
            .. word(#bytes)
            .. word(#bytes)
            .. short(#name)
            .. short(0)
        local record = word(0x04034b50) .. common .. name .. bytes
        local_records[#local_records + 1] = record
        central[#central + 1] = word(0x02014b50)
            .. short(20)
            .. common
            .. short(0)
            .. short(0)
            .. short(0)
            .. word(0)
            .. word(offset)
            .. name
        offset = offset + #record
    end
    local directory = table.concat(central)
    return table.concat(local_records)
        .. directory
        .. word(0x06054b50)
        .. short(0)
        .. short(0)
        .. short(3)
        .. short(3)
        .. word(#directory)
        .. word(offset)
        .. short(0)
end
return P
