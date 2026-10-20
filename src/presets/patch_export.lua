-- Internal, texture-only Stingray patch writer. No converter or subprocess.
-- Layout reference: HD2SDK Community Edition, TocEntry/StreamToc and StingrayTexture.
-- A preset can contain DDS, texture metadata and assignment references per
-- binding, plus its manifest. The optional v3 references contain no game bytes.
local P = { MAX_BINDINGS = 4096, ZIP_MAX_MEMBERS = 12289 }
-- The original LUT can occur in unrelated tutorial/prop archives. Its source
-- archive is provenance, not a reliable loaded patch destination. Match the
-- SDK's PatchBaseArchiveOnly default so one resource replacement is global.
P.BASE_ARCHIVE = '9ba626afa44a3aa3'
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
    assert(
        original and original.patch_source,
        original
                and original.source_archives
                and 'LUT colors agree across mod archives; a single patch source is not proven'
            or 'Original patch metadata unavailable; refresh original LUT snapshots'
    )
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
    -- The snapshot certifies the resource and native texture kind. Its DDS
    -- dimensions must agree with its metadata, even when the applied material
    -- uses a different row count. The replacement header/GPU payload comes
    -- entirely from the saved DDS, matching the live texture replacement.
    assert(
        (original.width == 23 or original.width == 3)
            and type(original.height) == 'number'
            and original.height >= 1
            and original.height <= 64
            and original.height % 1 == 0
            and (original.width ~= 3 or original.height == 1)
            and uint(template, 208) == original.width
            and uint(template, 204) == original.height,
        'Original patch metadata dimensions differ from its native texture header'
    )
    assert(
        document.width == original.width and (document.width == 23 or (document.width == 3 and document.height == 1)),
        'Editor LUT columns or texture kind differ from selected destination'
    )
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
function P.encode_set(dds, documents, options)
    assert(
        type(documents) == 'table' and #documents > 0 and #documents <= P.MAX_BINDINGS,
        'No complete palette to export or too many LUTs'
    )
    local unique, ordered, patches, conflict = {}, {}, {}, nil
    for _, item in ipairs(documents) do
        local patch = P.encode(dds, item.document, item.original)
        patches[#patches + 1] = patch
        local previous = unique[patch.resource]
        if previous then
            if previous.main ~= patch.main or previous.gpu ~= patch.gpu then
                conflict = conflict or patch.resource
            end
        else
            unique[patch.resource] = patch
            ordered[#ordered + 1] = patch
        end
    end
    if conflict then
        if options and options.binding_writer then
            return options.binding_writer.encode(P.BASE_ARCHIVE, documents, patches, options)
        end
        error(
            'Shared texture has conflicting applied palettes: '
                .. conflict
                .. '. Verified material/unit assignment provenance is required to preserve every binding.',
            0
        )
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
        local patch = original and P.encode(deps.dds, document, original) or P.encode_set(deps.dds, document, deps)
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
-- CRC work is export-only and initialized on first ZIP, never on idle updates.
-- LuaJIT keeps its native bit fast path; stock Lua 5.1 needs no extension.
local crc32
local function initialize_crc()
    local native = rawget(_G, 'bit')
    local bxor, rshift
    if native then
        bxor, rshift = native.bxor, native.rshift
    else
        local nibble = {}
        for a = 0, 15 do
            for b = 0, 15 do
                local x, y, value, place = a, b, 0, 1
                for _ = 1, 4 do
                    if x % 2 ~= y % 2 then value = value + place end
                    x, y, place = math.floor(x / 2), math.floor(y / 2), place * 2
                end
                nibble[a * 16 + b] = value
            end
        end
        bxor = function(a, b)
            local value, place = 0, 1
            for _ = 1, 8 do
                value = value + nibble[(a % 16) * 16 + b % 16] * place
                a, b, place = math.floor(a / 16), math.floor(b / 16), place * 16
            end
            return value
        end
        rshift = function(a, n) return math.floor(a / 2 ^ n) end
    end
    local crc_table = {}
    for n = 0, 255 do
        local crc = n
        for _ = 1, 8 do
            crc = bxor(rshift(crc, 1), crc % 2 ~= 0 and 0xedb88320 or 0)
        end
        crc_table[n] = crc
    end
    crc32 = function(bytes)
        local crc = 4294967295
        for i = 1, #bytes do
            crc = bxor(rshift(crc, 8), crc_table[bxor(crc % 256, bytes:byte(i))])
        end
        return 4294967295 - (crc % 4294967296)
    end
end
local function checksum(bytes)
    if not crc32 then initialize_crc() end
    return crc32(bytes)
end
function P.zip(patch)
    local base = patch.archive .. '.patch_0'
    return P.zip_entries({
        { base, patch.main },
        { base .. '.gpu_resources', patch.gpu },
        {
            base .. '.stream',
            patch.stream,
        },
    })
end
function P.zip_entries(entries)
    assert(type(entries) == 'table' and #entries > 0 and #entries <= P.ZIP_MAX_MEMBERS, 'Invalid export ZIP entries')
    local local_records, central, offset = {}, {}, 0
    local seen = {}
    for _, entry in ipairs(entries) do
        local name, bytes = entry[1], entry[2]
        assert(
            type(name) == 'string'
                and #name > 0
                and #name <= 200
                and not name:find('[\\/:]')
                and not name:find('..', 1, true)
                and not seen[name],
            'Unsafe export ZIP name'
        )
        assert(type(bytes) == 'string' and #bytes <= 8 * 1024 * 1024, 'Export ZIP entry too large')
        seen[name] = true
        local crc = word(checksum(bytes))
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
        .. short(#entries)
        .. short(#entries)
        .. word(#directory)
        .. word(offset)
        .. short(0)
end
return P
