local P = {}
function P.new(m)
    local ffi = require('ffi')
    local _, kernel = m.native_import.verify_interface()
    if not pcall(function()
        return kernel.epic_paths3_mkdir
    end) then
        ffi.cdef('int epic_paths3_mkdir(const uint16_t *,void *) __asm__("CreateDirectoryW");')
    end
    local function wide(text)
        local n = kernel.epic_native_wide(65001, 8, text, -1, nil, 0)
        assert(n > 0)
        local out = ffi.new('uint16_t[?]', n)
        assert(kernel.epic_native_wide(65001, 8, text, -1, out, n) == n)
        return out
    end
    local function mkdir(path)
        kernel.epic_paths3_mkdir(wide(path), nil)
        local attr = tonumber(kernel.epic_native_attributes(wide(path)))
        assert(attr ~= 4294967295 and require('bit').band(attr, 16) ~= 0, 'Epic LUT data folder unavailable: ' .. path)
    end
    local root = assert(os.getenv('LOCALAPPDATA')) .. '/Epic LUT'
    mkdir(root)
    local self = { root = root }
    for _, name in ipairs({ 'settings', 'files', 'presets', 'cache', 'originals' }) do
        self[name] = root .. '/' .. name
        mkdir(self[name])
    end
    self.exports = self.files .. '/exports'
    mkdir(self.exports)
    function self.directory_exists(path)
        local attr = tonumber(kernel.epic_native_attributes(wide(path)))
        return attr ~= 4294967295
    end
    function self.mkdir_new(path)
        assert(kernel.epic_paths3_mkdir(wide(path), nil) ~= 0, 'Export folder exists or cannot be created: ' .. path)
    end
    if not pcall(function()
        return kernel.epic_paths3_rmdir
    end) then
        ffi.cdef('int epic_paths3_rmdir(const uint16_t *) __asm__("RemoveDirectoryW");')
    end
    function self.rmdir(path)
        return kernel.epic_paths3_rmdir(wide(path)) ~= 0
    end
    self.storage = m.ui_store.new(self.settings)
    return self
end
return P
