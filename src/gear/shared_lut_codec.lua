-- Full RGBA32F tables and stable garment/material destinations. No lossy color conversion.
local C = { MAX_RAW = 65536, MAX_TEXT = 3600, MAX_DOCS = 32, MAX_BINDINGS = 128 }
local ffi = require('ffi')
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
function C.compression()
    pcall(ffi.cdef, [[
        int32_t EpicLutWorkspace(uint16_t, uint32_t *, uint32_t *) __asm__("RtlGetCompressionWorkSpaceSize");
        int32_t EpicLutCompress(uint16_t, const uint8_t *, uint32_t, uint8_t *, uint32_t, uint32_t, uint32_t *, void *) __asm__("RtlCompressBuffer");
        int32_t EpicLutDecompress(uint16_t, uint8_t *, uint32_t, const uint8_t *, uint32_t, uint32_t *) __asm__("RtlDecompressBuffer");
    ]])
    local dll = ffi.load('ntdll')
    local workspace_size, fragment = ffi.new('uint32_t[1]'), ffi.new('uint32_t[1]')
    assert(dll.EpicLutWorkspace(2, workspace_size, fragment) == 0 and workspace_size[0] <= 1024 * 1024, 'LUT compression unavailable')
    local workspace = ffi.new('uint8_t[?]', workspace_size[0])
    local output, final = ffi.new('uint8_t[?]', C.MAX_RAW + 4096), ffi.new('uint32_t[1]')
    return {
        compress = function(bytes)
            assert(#bytes <= C.MAX_RAW)
            assert(dll.EpicLutCompress(2, bytes, #bytes, output, C.MAX_RAW + 4096, 4096, final, workspace) == 0, 'LUT compression failed')
            assert(final[0] <= C.MAX_RAW + 4096)
            return ffi.string(output, final[0])
        end,
        decompress = function(bytes, size)
            assert(size <= C.MAX_RAW and #bytes <= C.MAX_TEXT)
            assert(dll.EpicLutDecompress(2, output, size, bytes, #bytes, final) == 0 and final[0] == size, 'Invalid compressed LUT appearance')
            return ffi.string(output, size)
        end,
    }
end
function C.new(compression)
    compression = compression or C.compression()
    local function word(n)
        assert(type(n) == 'number' and n >= 0 and n < 4294967296 and n % 1 == 0, 'Invalid shared kit')
        return ffi.string(ffi.new('uint32_t[1]', n), 4)
    end
    local function finite(doc)
        assert(((doc.width == 23 and doc.height >= 1 and doc.height <= 16) or (doc.width == 3 and doc.height == 1)) and doc.height % 1 == 0, 'Unsupported shared table shape')
        for i = 0, doc.width * doc.height * 4 - 1 do
            local n = tonumber(doc.data[i])
            assert(n == n and math.abs(n) <= 1e10, 'Invalid shared LUT float')
        end
    end
    local self = {}
    function self.encode(identity, entries)
        local docs, lookup, bindings, seen = {}, {}, {}, {}
        for _, entry in ipairs(entries) do
            if not seen[entry.key] then
                local d = entry.document
                finite(d)
                local pixels = ffi.string(d.data, d.width * d.height * 16)
                local signature = string.char(d.width, d.height) .. pixels
                local index = lookup[signature]
                if not index then docs[#docs + 1] = signature; index = #docs; lookup[signature] = index end
                local pattern = entry.key:sub(1,2) == 'p:'
                local destination = pattern and entry.key:sub(3) or entry.key
                local t, slot, mesh, material = destination:match('^(%d+):(%d+):(%d+):(%d+)$')
                t, slot, mesh, material = tonumber(t), tonumber(slot), tonumber(mesh), tonumber(material)
                assert(t and t <= 2 and slot <= 9 and mesh <= 63 and material <= 63, 'Invalid shared destination')
                bindings[#bindings + 1] = string.char(t + (pattern and 128 or 0), slot, mesh, material, index)
                seen[entry.key] = true
            end
        end
        assert(#docs <= C.MAX_DOCS and #bindings <= C.MAX_BINDINGS, 'Too many LUTs to share')
        local raw = 'EL1' .. word(identity.body or 0) .. word(identity.armor or 0) .. word(identity.helmet or 0)
            .. string.char(#docs, #bindings) .. table.concat(docs) .. table.concat(bindings)
        assert(#raw <= C.MAX_RAW, 'Shared LUT raw budget exceeded')
        local text = '1|' .. #raw .. '|' .. base64(compression.compress(raw))
        assert(#text <= C.MAX_TEXT, 'Full LUT appearance exceeds lobby size limit; local edits are kept')
        return text
    end
    function self.decode(text)
        assert(type(text) == 'string' and #text <= C.MAX_TEXT, 'Invalid shared LUT packet size')
        local size, encoded = text:match('^1|(%d+)|(.+)$')
        size = tonumber(size)
        assert(size and size >= 17 and size <= C.MAX_RAW, 'Unsupported shared LUT packet')
        local raw = compression.decompress(unbase64(encoded), size)
        assert(#raw == size and raw:sub(1,3) == 'EL1', 'Invalid shared LUT header')
        local at = 4
        local function take(n)
            assert(at + n - 1 <= #raw, 'Truncated shared appearance')
            local s = raw:sub(at, at + n - 1); at = at + n; return s
        end
        local function readword()
            local data = ffi.new('uint32_t[1]'); ffi.copy(data, take(4), 4); return tonumber(data[0])
        end
        local result = {body = readword(), armor = readword(), helmet = readword(), documents = {}, entries = {}}
        local docs, bindings = take(1):byte(), take(1):byte()
        assert(docs <= C.MAX_DOCS and bindings <= C.MAX_BINDINGS, 'Shared appearance count exceeds budget')
        for i = 1, docs do
            local width, height = take(2):byte(1,2)
            assert((width == 23 and height >= 1 and height <= 16) or (width == 3 and height == 1), 'Invalid shared LUT shape')
            local data = ffi.new('float[?]', width * height * 4)
            ffi.copy(data, take(width * height * 16), width * height * 16)
            local doc = {width = width, height = height, data = data}
            finite(doc); result.documents[i] = doc
        end
        local seen = {}
        for i = 1, bindings do
            local t, slot, mesh, material, index = take(5):byte(1,5)
            local pattern = t >= 128
            if pattern then t = t - 128 end
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
