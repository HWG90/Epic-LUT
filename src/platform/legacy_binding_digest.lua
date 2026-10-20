-- Exact legacy BCrypt implementation; selected only without a portable platform.
local D = {}
function D.digest(bytes, expected_bytes)
    local ffi = require('ffi')
    if not pcall(ffi.typeof, 'epic_binding_hash_marker') then
        ffi.cdef([[
            typedef struct epic_binding_hash_marker { int unused; } epic_binding_hash_marker;
            int32_t epic_binding_BCryptOpenAlgorithmProvider(void **, const uint16_t *, const uint16_t *, uint32_t) __asm__("BCryptOpenAlgorithmProvider");
            int32_t epic_binding_BCryptCloseAlgorithmProvider(void *, uint32_t) __asm__("BCryptCloseAlgorithmProvider");
            int32_t epic_binding_BCryptCreateHash(void *, void **, void *, uint32_t, const void *, uint32_t, uint32_t) __asm__("BCryptCreateHash");
            int32_t epic_binding_BCryptHashData(void *, const void *, uint32_t, uint32_t) __asm__("BCryptHashData");
            int32_t epic_binding_BCryptFinishHash(void *, void *, uint32_t, uint32_t) __asm__("BCryptFinishHash");
            int32_t epic_binding_BCryptDestroyHash(void *) __asm__("BCryptDestroyHash");
        ]])
    end
    local lib = ffi.load('bcrypt')
    local algorithm, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
    local ok, result = pcall(function()
        local name = ffi.new('uint16_t[7]', { 83, 72, 65, 50, 53, 54, 0 })
        assert(lib.epic_binding_BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0, 'Binding SHA256 unavailable')
        assert(
            lib.epic_binding_BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) == 0,
            'Binding SHA256 creation failed'
        )
        if type(bytes) == 'function' then
            local total, limit = 0, expected_bytes or 512 * 1024 * 1024
            while true do
                local chunk = bytes()
                if chunk == nil then
                    break
                end
                assert(type(chunk) == 'string' and #chunk > 0 and #chunk <= 65536, 'Invalid binding digest chunk')
                assert(#chunk <= limit - total, 'Binding digest file exceeds its limit')
                total = total + #chunk
                assert(lib.epic_binding_BCryptHashData(hash[0], chunk, #chunk, 0) == 0, 'Binding SHA256 update failed')
            end
            assert(expected_bytes == nil or total == expected_bytes, 'Binding digest file length differs')
        else
            assert(lib.epic_binding_BCryptHashData(hash[0], bytes, #bytes, 0) == 0, 'Binding SHA256 update failed')
        end
        local digest = ffi.new('uint8_t[32]')
        assert(lib.epic_binding_BCryptFinishHash(hash[0], digest, 32, 0) == 0, 'Binding SHA256 finish failed')
        local out = ''
        for i = 0, 31 do
            out = out .. string.format('%02x', digest[i])
        end
        return out
    end)
    if hash[0] ~= nil then
        lib.epic_binding_BCryptDestroyHash(hash[0])
    end
    if algorithm[0] ~= nil then
        lib.epic_binding_BCryptCloseAlgorithmProvider(algorithm[0], 0)
    end
    assert(ok, result)
    return result
end
return D
