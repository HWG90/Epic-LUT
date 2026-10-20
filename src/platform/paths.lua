-- Existing Epic LUT folders through an explicitly supplied platform service.
-- The LuaJIT path remains isolated; no settings migration or native-path guessing.
local P = {}
function P.new(m)
    if not m.platform then
        return (m.legacy_paths or require('src.platform.legacy_paths')).new(m)
    end
    local platform = m.platform
    assert(type(platform) == 'table', 'Epic LUT platform service required')
    for _, name in ipairs({ 'mkdir', 'directory_exists', 'mkdir_new', 'rmdir', 'open_folder' }) do
        assert(type(platform[name]) == 'function', 'Epic LUT platform service missing ' .. name)
    end
    local function mkdir(path)
        -- Existing directories remain valid when mkdir reports already-exists.
        platform.mkdir(path)
        assert(platform.directory_exists(path) == true, 'Epic LUT data folder unavailable: ' .. path)
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
        return platform.directory_exists(path) == true
    end
    function self.mkdir_new(path)
        local ok, why = platform.mkdir_new(path)
        assert(ok == true, why or 'Export folder exists or cannot be created: ' .. path)
    end
    function self.rmdir(path)
        return platform.rmdir(path) == true
    end
    function self.open_exports()
        local ok, why = platform.open_folder(self.exports)
        assert(ok == true, why or 'Could not open export folder: ' .. self.exports)
        return true
    end
    self.storage = m.storage or m.ui_store.new(self.settings)
    return self
end
return P
