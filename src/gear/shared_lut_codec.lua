-- Full RGBA32F tables and stable garment/material destinations. No lossy color conversion.
local C = { MAX_RAW = 65536, MAX_TEXT = 3600, MAX_DOCS = 32, MAX_BINDINGS = 4096, LEGACY_BINDINGS = 128 }
local ffi = require('ffi')
local bit = require('bit')
local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local digits = {}
for i = 1, #alphabet do digits[alphabet:sub(i, i)] = i - 1 end
local function base64(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local function char(v) return alphabet:sub(v + 1, v + 1) end
        out[#out + 1] = char(math.floor(n / 262144)) .. char(math.floor(n / 4096) % 64)
            .. (b and char(math.floor(n / 64) % 64) or '=') .. (c and char(n % 64) or '=')
    end
    return table.concat(out)
end
local function unbase64(text)
    assert(#text % 4 == 0 and not text:find('[^%w+/=]'), 'Invalid shared LUT encoding')
    local out = {}
    for i = 1, #text, 4 do
        local a, b, c, d = text:sub(i,i), text:sub(i+1,i+1), text:sub(i+2,i+2), text:sub(i+3,i+3)
        assert(digits[a] and digits[b] and (digits[c] or c == '=') and (digits[d] or d == '='), 'Invalid shared LUT encoding')
        assert((c ~= '=' or d == '=') and (c ~= '=' and d ~= '=' or i + 3 == #text), 'Invalid shared LUT padding')
        local n = digits[a] * 262144 + digits[b] * 4096 + (digits[c] or 0) * 64 + (digits[d] or 0)
        out[#out + 1] = string.char(math.floor(n / 65536), math.floor(n / 256) % 256, n % 256):sub(1, c == '=' and 1 or d == '=' and 2 or 3)
    end
    return table.concat(out)
end
function C.compression(native)
    pcall(ffi.cdef, [[
        int32_t EpicLutWorkspace(uint16_t, uint32_t *, uint32_t *) __asm__("RtlGetCompressionWorkSpaceSize");
        int32_t EpicLutCompress(uint16_t, const uint8_t *, uint32_t, uint8_t *, uint32_t, uint32_t, uint32_t *, void *) __asm__("RtlCompressBuffer");
        int32_t EpicLutDecompress(uint16_t, uint8_t *, uint32_t, const uint8_t *, uint32_t, uint32_t *) __asm__("RtlDecompressBuffer");
    ]])
    local dll = native or ffi.load('ntdll')
    local workspace_size, fragment = ffi.new('uint32_t[1]'), ffi.new('uint32_t[1]')
    assert(dll.EpicLutWorkspace(2, workspace_size, fragment) == 0 and workspace_size[0] > 0 and workspace_size[0] <= 1024 * 1024, 'LUT compression unavailable')
    local workspace = ffi.new('uint8_t[?]', workspace_size[0])
    local xpress_workspace, xpress_format
    -- Optional native improvement: MAXIMUM first, STANDARD second. Keep the
    -- legacy backend available and every workspace bounded to one MiB.
    for _, format in ipairs({259, 3}) do
        local ok, status = pcall(dll.EpicLutWorkspace, format, workspace_size, fragment)
        if ok and status == 0 and workspace_size[0] > 0 and workspace_size[0] <= 1024 * 1024 then
            xpress_workspace, xpress_format = ffi.new('uint8_t[?]', workspace_size[0]), format
            break
        end
    end
    local output, final = ffi.new('uint8_t[?]', C.MAX_RAW + 4096), ffi.new('uint32_t[1]')
    return {
        formats = xpress_workspace and {'', 'x'} or {''},
        xpress_format = xpress_format,
        compress = function(bytes, tag)
            assert(type(bytes)=='string' and #bytes>0 and #bytes<=C.MAX_RAW,'Invalid LUT compression input')
            assert(not tag or tag == '' or tag == 'x', 'Unsupported LUT compression format')
            assert(tag ~= 'x' or xpress_workspace, 'XPRESS compression unavailable')
            local format, work = tag == 'x' and xpress_format or 2, tag == 'x' and xpress_workspace or workspace
            assert(dll.EpicLutCompress(format, bytes, #bytes, output, C.MAX_RAW + 4096, 4096, final, work) == 0, 'LUT compression failed')
            assert(final[0] > 0 and final[0] <= C.MAX_RAW + 4096)
            return ffi.string(output, final[0])
        end,
        decompress = function(bytes, size, tag)
            assert(type(size)=='number' and size>0 and size<=C.MAX_RAW and size%1==0
                and type(bytes)=='string' and #bytes>0 and #bytes<=C.MAX_TEXT,'Invalid LUT decompression bounds')
            assert(not tag or tag == '' or tag == 'x', 'Unsupported LUT compression format')
            assert(dll.EpicLutDecompress(tag == 'x' and 3 or 2, output, size, bytes, #bytes, final) == 0 and final[0] == size, 'Invalid compressed LUT appearance')
            return ffi.string(output, size)
        end,
    }
end
function C.new(compression, original)
    compression = compression or C.compression()
    local function word(n)
        assert(type(n) == 'number' and n >= 0 and n < 4294967296 and n % 1 == 0, 'Invalid shared kit')
        return ffi.string(ffi.new('uint32_t[1]', n), 4)
    end
    local function finite(doc)
        assert(((doc.width == 23 and doc.height >= 1 and doc.height <= 64) or (doc.width == 3 and doc.height == 1)) and doc.height % 1 == 0, 'Unsupported shared table shape')
        for i = 0, doc.width * doc.height * 4 - 1 do
            local n = tonumber(doc.data[i])
            assert(n == n and math.abs(n) <= 1e10, 'Invalid shared LUT float')
        end
    end
    local function checksum(bytes)
        local a, b = 1, 0
        for i = 1, #bytes do a = (a + bytes:byte(i)) % 65521; b = (b + a) % 65521 end
        return string.format('%08x', b * 65536 + a)
    end
    local function short(n) return string.char(n % 256, math.floor(n / 256)) end
    local self = {}
    function self.encode(identity, entries, checkpoint)
        checkpoint = checkpoint or function() end
        -- Published texture objects are immutable and can serve hundreds of
        -- bindings. Validate their finite pixels once per packet build.
        local validated = {}
        local function finite_once(document)
            if not validated[document] then
                finite(document)
                validated[document] = true
            end
        end
        local docs, delta_docs, xor_docs, lookup, bindings, seen = {}, {}, {}, {}, {}, {}
        local decoded_bytes = 0
        for _, entry in ipairs(entries) do
            local pattern = entry.key:sub(1,2) == 'p:'
            local destination = pattern and entry.key:sub(3) or entry.key
            local t, slot, mesh, material = destination:match('^(%d+):(%d+):(%d+):(%d+)$')
            t, slot, mesh, material = tonumber(t), tonumber(slot), tonumber(mesh), tonumber(material)
            assert(t and slot and mesh and material and t <= 2 and slot <= 9 and mesh <= 63 and material <= 63, 'Invalid shared destination')
            local key = (pattern and 'p:' or '') .. t .. ':' .. slot .. ':' .. mesh .. ':' .. material
            local d = entry.document
            finite_once(d)
            assert(d.width == (pattern and 3 or 23), 'Binding slot and table shape disagree')
            local pixels = ffi.string(d.data, d.width * d.height * 16)
            local signature = string.char(d.width, d.height) .. pixels
            assert(not seen[key] or seen[key] == signature, 'Conflicting shared destination')
            if not seen[key] then
                assert(#bindings < C.MAX_BINDINGS, 'Too many LUT bindings to share; limit is ' .. C.MAX_BINDINGS .. '; local edits are kept')
                local index = lookup[signature]
                if not index then
                    assert(#docs < C.MAX_DOCS, 'Too many unique LUT tables to share; limit is ' .. C.MAX_DOCS .. '; local edits are kept')
                    decoded_bytes = decoded_bytes + #pixels
                    assert(decoded_bytes <= C.MAX_RAW, 'Reconstructed shared appearance exceeds budget; local edits are kept')
                    docs[#docs + 1] = signature; index = #docs; lookup[signature] = index
                    local encoded = string.char(0) .. signature
                    xor_docs[index] = encoded
                    local base = entry.original
                    if base and base.resource and base.resource:match('^%x+$') and #base.resource == 16
                        and base.width == d.width and base.height == d.height then
                        finite_once(base)
                        local bytes = ffi.string(base.data, #pixels)
                        -- Four byte planes retain every IEEE-754 bit; XOR makes
                        -- unchanged bytes zero and groups similarly changing bytes.
                        local planes = {}
                        for lane = 1, 4 do
                            local plane = {}
                            for at = lane, #pixels, 4 do
                                plane[#plane + 1] = string.char(bit.bxor(pixels:byte(at), bytes:byte(at)))
                            end
                            planes[#planes + 1] = table.concat(plane)
                            checkpoint()
                        end
                        xor_docs[index] = string.char(2,d.width,d.height) .. base.resource:lower()
                            .. checksum(bytes) .. table.concat(planes)
                        local changes = {}
                        for at = 1, #pixels, 4 do
                            if pixels:sub(at, at + 3) ~= bytes:sub(at, at + 3) then
                                changes[#changes + 1] = short((at - 1) / 4) .. pixels:sub(at, at + 3)
                            end
                        end
                        local delta = string.char(1,d.width,d.height) .. base.resource:lower()
                            .. checksum(bytes) .. short(#changes) .. table.concat(changes)
                        if #delta < #encoded then encoded = delta end
                    end
                    delta_docs[index] = encoded
                end
                bindings[#bindings + 1] = {t = t, pattern = pattern, slot = slot, mesh = mesh, material = material, index = index}
                seen[key] = signature
            end
            checkpoint()
        end
        local legacy = #bindings <= C.LEGACY_BINDINGS
        local header = word(identity.body or 0) .. word(identity.armor or 0) .. word(identity.helmet or 0)
            .. string.char(#docs) .. (legacy and string.char(#bindings) or short(#bindings))
        local encoded_bindings, packed_bindings, full_docs = {}, {}, {}
        for i, b in ipairs(bindings) do
            local packed = b.index - 1 + b.material * 32 + b.mesh * 2048 + b.slot * 131072
                + (b.t + (b.pattern and 4 or 0)) * 2097152
            packed_bindings[i] = string.char(packed % 256, math.floor(packed / 256) % 256, math.floor(packed / 65536))
            if legacy then
                encoded_bindings[i] = string.char(b.t + (b.pattern and 128 or 0), b.slot, b.mesh, b.material, b.index)
            else
                -- Exactly 24 bits: document index minus one (5), material (6),
                -- mesh (6), slot (4), garment type (2), and Pattern flag (1).
                -- Keep all destination keys; repeated tables stay deduplicated.
                encoded_bindings[i] = packed_bindings[i]
            end
        end
        for i, doc in ipairs(docs) do full_docs[i] = (legacy and '' or string.char(0)) .. doc end
        local tail, text = table.concat(encoded_bindings), nil
        self.packet_sizes = {}
        local function packed_candidate(version, name, raw)
            if #raw <= C.MAX_RAW then
                for _,tag in ipairs(compression.formats or {''}) do
                    assert(tag == '' or tag == 'x', 'Unsupported LUT compression format')
                    local ok,bytes=pcall(compression.compress,raw,tag)
                    if not ok and tag == '' then error(bytes,0) end
                    if ok then
                        assert(type(bytes)=='string' and #bytes>0 and #bytes<=C.MAX_RAW+4096,'Invalid compressed LUT output')
                        local packed = version .. tag .. '|' .. #raw .. '|' .. base64(bytes)
                        self.packet_sizes[name] = math.min(self.packet_sizes[name] or math.huge,#packed)
                        if not text or #packed < #text then text = packed end
                        checkpoint()
                    end
                end
            end
        end
        local function candidate(version, name, representation)
            packed_candidate(version,name,'EL' .. version .. header .. table.concat(representation) .. tail)
        end
        candidate(legacy and '1' or '4', 'full', full_docs)
        candidate(legacy and '2' or '4', 'sparse', delta_docs)
        candidate(legacy and '3' or '4', 'xor', xor_docs)
        -- Original-independent exact F32 words shared across every document.
        -- Treat each four-byte word as opaque bytes, including signed zero.
        local words, word_ids, shapes = {}, {}, {}
        for i,doc in ipairs(docs)do
            shapes[i]=doc:sub(1,2)
            for at=3,#doc,4 do
                local value=doc:sub(at,at+3)
                local index=word_ids[value]
                if not index then words[#words+1]=value;index=#words;word_ids[value]=index end
            end
        end
        local word_count = #words
        assert(word_count <= decoded_bytes / 4, 'Shared word dictionary exceeds reconstructed budget')
        local first, frequencies = {}, {}
        for i, value in ipairs(words) do first[i] = value end
        for _, doc in ipairs(docs) do
            for at = 3, #doc, 4 do
                local value = doc:sub(at, at + 3)
                frequencies[value] = (frequencies[value] or 0) + 1
            end
        end
        -- Exact sparse destination masks retain every mesh/material assignment.
        -- One 64x64 bit mask per (kind, slot, document), independent of input order.
        local mask_groups, mask_order = {}, {}
        for _, b in ipairs(bindings) do
            local key = string.char(b.t + (b.pattern and 4 or 0), b.slot, b.index)
            local group = mask_groups[key]
            if not group then group = {}; mask_groups[key] = group; mask_order[#mask_order + 1] = key end
            local at = b.mesh * 64 + b.material
            local byte = math.floor(at / 8) + 1
            group[byte] = (group[byte] or 0) + 2 ^ (at % 8)
        end
        table.sort(mask_order)
        local masks = { short(#mask_order) }
        for _, key in ipairs(mask_order) do
            local bytes, group = {}, mask_groups[key]
            for i = 1, 512 do bytes[i] = string.char(group[i] or 0) end
            masks[#masks + 1] = key .. table.concat(bytes)
        end
        local mask_tail = table.concat(masks)
        local function dictionary_candidate(order)
            local ids, planes, low, high = {}, {}, {}, {}
            for i, value in ipairs(order) do ids[value] = i - 1 end
            for lane = 1, 4 do
                local plane = {}
                for i, value in ipairs(order) do plane[i] = value:sub(lane, lane) end
                planes[lane] = table.concat(plane)
            end
            for _, doc in ipairs(docs) do
                for at = 3, #doc, 4 do
                    local index = ids[doc:sub(at, at + 3)]
                    low[#low + 1] = string.char(index % 256)
                    if word_count > 256 then high[#high + 1] = string.char(math.floor(index / 256)) end
                end
            end
            local dictionary_header = word(identity.body or 0) .. word(identity.armor or 0)
                .. word(identity.helmet or 0)
                .. string.char(#docs) .. short(#bindings)  .. short(word_count)
            packed_candidate('5', 'dictionary', 'EL5' .. dictionary_header
                .. table.concat(shapes) .. table.concat(planes) .. table.concat(low)
                .. table.concat(high) .. table.concat(packed_bindings))
            local mask_header = word(identity.body or 0) .. word(identity.armor or 0)
                .. word(identity.helmet or 0) .. string.char(0)
                .. string.char(#docs) .. short(#bindings) .. short(word_count)
            packed_candidate('7', 'masked_dictionary', 'EL7' .. mask_header
                .. table.concat(shapes) .. table.concat(planes) .. table.concat(low)
                .. table.concat(high) .. mask_tail)
        end
        table.sort(words) -- Keep the established lexical candidate first on ties.
        dictionary_candidate(words)
        dictionary_candidate(first)
        table.sort(words, function(a, b)
            if frequencies[a] == frequencies[b] then return a < b end
            return frequencies[a] > frequencies[b]
        end)
        dictionary_candidate(words)
        assert(text, 'Shared LUT raw budget exceeded; local edits are kept')
        assert(#text <= C.MAX_TEXT, 'Full LUT appearance needs ' .. #text .. ' bytes; lobby budget is ' .. C.MAX_TEXT .. '; local edits are kept')
        return text
    end
    function self.decode(text)
        assert(type(text) == 'string' and #text <= C.MAX_TEXT, 'Invalid shared LUT packet size')
        local version, tag, size, encoded = text:match('^([123457])(x?)|(%d+)|(.+)$')
        size = tonumber(size)
        assert(size and size >= (version == '5' and 20 or version == '4' and 18 or 17) and size <= C.MAX_RAW, 'Unsupported shared LUT packet')
        local raw = compression.decompress(unbase64(encoded), size, tag)
        assert(#raw == size and raw:sub(1,3) == 'EL' .. version, 'Invalid shared LUT header')
        assert(version ~= '7' or size >= 23, 'Truncated masked LUT header')
        local at = 4
        local function take(n)
            assert(at + n - 1 <= #raw, 'Truncated shared appearance')
            local s = raw:sub(at, at + n - 1); at = at + n; return s
        end
        local function readword()
            local data = ffi.new('uint32_t[1]'); ffi.copy(data, take(4), 4); return tonumber(data[0])
        end
        local result = {body = readword(), armor = readword(), helmet = readword(), documents = {}, entries = {}}
        local masked_weapons
        if version == '7' then
            masked_weapons = take(1):byte()
            assert(masked_weapons == 0 or masked_weapons == 1, 'Invalid masked weapon flag')
        end
        assert(not masked_weapons or masked_weapons == 0, 'Weapon sharing requires R6')

        local docs, bindings = take(1):byte(), take(1):byte()
        local packed_bindings=version=='4' or version=='5' or version=='7'
        if packed_bindings then bindings = bindings + take(1):byte() * 256 end
        local decoded_bytes = 0
        assert(docs <= C.MAX_DOCS and bindings <= (packed_bindings and C.MAX_BINDINGS or C.LEGACY_BINDINGS), 'Shared appearance count exceeds budget')
        if version=='5' or version=='7' then
            local lo,hi=take(2):byte(1,2)
            local count=lo+hi*256
            local shapes={}
            for i=1,docs do
                local width,height=take(2):byte(1,2)
                assert((width==23 and height>=1 and height<=64)or(width==3 and height==1),'Invalid shared LUT shape')
                decoded_bytes=decoded_bytes+width*height*16
                assert(decoded_bytes<=C.MAX_RAW,'Reconstructed shared appearance exceeds budget')
                shapes[i]={width=width,height=height}
            end
            assert(count<=decoded_bytes/4 and (count>0 or decoded_bytes==0),'Invalid shared word dictionary size')
            local planes=take(count*4)
            local dictionary=ffi.new('uint8_t[?]',math.max(1,count*4))
            for lane=0,3 do
                for i=0,count-1 do dictionary[i*4+lane]=planes:byte(lane*count+i+1)end
            end
            local values=ffi.cast('const float *',dictionary)
            for i=0,count-1 do
                local value=tonumber(values[i])
                assert(value==value and math.abs(value)<=1e10,'Invalid shared LUT float')
            end
            local floats=decoded_bytes/4
            local indexes=take(floats*(count>256 and 2 or 1))
            local flat_index=0
            for i,shape in ipairs(shapes)do
                local document_floats=shape.width*shape.height*4
                local data=ffi.new('float[?]',document_floats)
                for at=0,document_floats-1 do
                    local index=indexes:byte(flat_index+1)
                    if count>256 then index=index+indexes:byte(floats+flat_index+1)*256 end
                    assert(index<count,'Invalid shared word dictionary index')
                    ffi.copy(data+at,dictionary+index*4,4)
                    flat_index=flat_index+1
                end
                local document={width=shape.width,height=shape.height,data=data}
                finite(document);result.documents[i]=document
            end
        else
        for i = 1, docs do
            local mode = version ~= '1' and take(1):byte() or 0
            assert(mode == 0 or mode == 1 or ((version == '3' or version == '4') and mode == 2), 'Invalid shared LUT representation')
            local width, height = take(2):byte(1,2)
            assert((width == 23 and height >= 1 and height <= 64) or (width == 3 and height == 1), 'Invalid shared LUT shape')
            decoded_bytes = decoded_bytes + width * height * 16
            assert(decoded_bytes <= C.MAX_RAW, 'Reconstructed shared appearance exceeds budget')
            local data = ffi.new('float[?]', width * height * 4)
            if mode == 0 then
                ffi.copy(data, take(width * height * 16), width * height * 16)
            else
                local resource, expected = take(16), take(8)
                assert(resource:match('^%x+$') and expected:match('^%x+$'), 'Invalid shared baseline identity')
                local base = original and original(resource)
                assert(base, 'Sharing: waiting for original LUT ' .. resource)
                assert(base.width == width and base.height == height, 'Shared baseline dimensions disagree')
                local bytes = ffi.string(base.data, width * height * 16)
                assert(checksum(bytes) == expected, 'Sharing: original LUT differs from sender ' .. resource)
                ffi.copy(data, bytes, #bytes)
                if mode == 2 then
                    local planes = take(#bytes)
                    local target = ffi.cast('uint8_t *',data)
                    local count = width * height * 4
                    for lane = 0, 3 do
                        for i = 0, count - 1 do
                            local at = i * 4 + lane
                            target[at] = bit.bxor(bytes:byte(at + 1), planes:byte(lane * count + i + 1))
                        end
                    end
                else
                local lo, hi = take(2):byte(1,2)
                local count, prior = lo + hi * 256, -1
                assert(count <= width * height * 4, 'Too many shared changes')
                for _ = 1, count do
                    lo, hi = take(2):byte(1,2)
                    local index = lo + hi * 256
                    assert(index > prior and index < width * height * 4, 'Invalid shared change index')
                    ffi.copy(data + index, take(4), 4)
                    prior = index
                end
                end
            end
            local doc = {width = width, height = height, data = data}
            finite(doc); result.documents[i] = doc
        end
        end
        local masked_bindings
        if version == '7' then
            local a, b = take(2):byte(1, 2)
            local groups = a + b * 256
            assert(groups <= bindings and groups * 515 <= #raw - at + 1, 'Invalid binding mask count')
            masked_bindings = {}
            local groups_seen = {}
            for _ = 1, groups do
                local key = take(3)
                assert(not groups_seen[key], 'Duplicate binding mask group')
                groups_seen[key] = true
                local kind, slot, index = key:byte(1, 3)
                assert(kind <= 7 and slot <= 9 and index >= 1 and index <= docs, 'Invalid binding mask group')
                local mask, count = take(512), 0
                for byte = 1, 512 do
                    local value = mask:byte(byte)
                    if value ~= 0 then
                        for lane = 0, 7 do
                            if math.floor(value / 2 ^ lane) % 2 == 1 then
                                local cell = (byte - 1) * 8 + lane
                                local mesh, material = math.floor(cell / 64), cell % 64
                                local packed = index - 1 + material * 32 + mesh * 2048 + slot * 131072 + kind * 2097152
                                masked_bindings[#masked_bindings + 1] = string.char(packed % 256,
                                    math.floor(packed / 256) % 256, math.floor(packed / 65536))
                                count = count + 1
                                assert(#masked_bindings <= bindings, 'Binding mask exceeds declared count')
                            end
                        end
                    end
                end
                assert(count > 0, 'Empty binding mask group')
            end
            assert(#masked_bindings == bindings, 'Binding mask count disagrees')
        end
        local seen = {}
        for i = 1, bindings do
            local t, slot, mesh, material, index, pattern
            if packed_bindings then
                local a, b, c = (masked_bindings and masked_bindings[i] or take(3)):byte(1, 3)
                local packed = a + b * 256 + c * 65536
                local kind = math.floor(packed / 2097152)
                t, pattern = kind % 4, kind >= 4
                slot, mesh = math.floor(packed / 131072) % 16, math.floor(packed / 2048) % 64
                material, index = math.floor(packed / 32) % 64, packed % 32 + 1
            else
                t, slot, mesh, material, index = take(5):byte(1,5)
                pattern = t >= 128
                if pattern then t = t - 128 end
            end
            assert(t <= 2 and slot <= 9 and mesh <= 63 and material <= 63 and result.documents[index], 'Invalid shared binding')
            local key = (pattern and 'p:' or '') .. t .. ':' .. slot .. ':' .. mesh .. ':' .. material
            assert(not seen[key], 'Duplicate shared binding'); seen[key] = true
            assert(result.documents[index].width == (pattern and 3 or 23), 'Binding slot and table shape disagree')
            result.entries[key] = {document = result.documents[index], helmet = slot == 0, pattern = pattern}
        end
        assert(at == #raw + 1, 'Trailing shared LUT bytes')
        return result
    end
    return self
end
return C
