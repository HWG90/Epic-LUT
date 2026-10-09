-- Bounded CF_UNICODETEXT access. Clipboard memory is borrowed on reads and
-- transferred to Windows only after SetClipboardData succeeds on writes.
local C = { MAX_BYTES = 32768, MAX_UNITS = 16384 }
local function windows()
    local ffi = require('ffi')
    if not pcall(ffi.typeof, 'epic_clip_handle') then
        ffi.cdef([[
        typedef void *epic_clip_handle;
        int epic_clip_open(epic_clip_handle) __asm__("OpenClipboard");
        int epic_clip_close(void) __asm__("CloseClipboard");
        int epic_clip_empty(void) __asm__("EmptyClipboard");
        epic_clip_handle epic_clip_get(unsigned int) __asm__("GetClipboardData");
        epic_clip_handle epic_clip_set(unsigned int,epic_clip_handle) __asm__("SetClipboardData");
        epic_clip_handle epic_clip_alloc(unsigned int,size_t) __asm__("GlobalAlloc");
        epic_clip_handle epic_clip_free(epic_clip_handle) __asm__("GlobalFree");
        epic_clip_handle epic_clip_lock(epic_clip_handle) __asm__("GlobalLock");
        int epic_clip_unlock(epic_clip_handle) __asm__("GlobalUnlock");
        size_t epic_clip_size(epic_clip_handle) __asm__("GlobalSize");
        int epic_clip_wide(unsigned int,unsigned int,const char *,int,uint16_t *,int) __asm__("MultiByteToWideChar");
        int epic_clip_utf8(unsigned int,unsigned int,const uint16_t *,int,char *,int,void *,void *) __asm__("WideCharToMultiByte");
    ]])
    end
    local user, kernel = ffi.load('user32'), ffi.load('kernel32')
    return {
        open = function(hwnd)
            return user.epic_clip_open(hwnd) ~= 0
        end,
        close = function()
            user.epic_clip_close()
        end,
        empty = function()
            return user.epic_clip_empty() ~= 0
        end,
        get = function()
            return user.epic_clip_get(13)
        end,
        set = function(handle)
            return user.epic_clip_set(13, handle) ~= nil
        end,
        alloc = function(bytes)
            return kernel.epic_clip_alloc(0x42, bytes)
        end,
        free = function(handle)
            kernel.epic_clip_free(handle)
        end,
        size = function(handle)
            return tonumber(kernel.epic_clip_size(handle))
        end,
        lock = function(handle)
            return kernel.epic_clip_lock(handle)
        end,
        unlock = function(handle)
            kernel.epic_clip_unlock(handle)
        end,
        to_wide = function(text)
            if text == '' then
                return ffi.new('uint16_t[1]'), 0
            end
            local count = kernel.epic_clip_wide(65001, 8, text, #text, nil, 0)
            if count <= 0 or count > C.MAX_UNITS then
                return nil
            end
            local out = ffi.new('uint16_t[?]', count + 1)
            if kernel.epic_clip_wide(65001, 8, text, #text, out, count) ~= count then
                return nil
            end
            return out, count
        end,
        from_wide = function(data, count)
            if count == 0 then
                return ''
            end
            local length = kernel.epic_clip_utf8(65001, 128, data, count, nil, 0, nil, nil)
            if length <= 0 or length > C.MAX_BYTES then
                return nil
            end
            local out = ffi.new('char[?]', length)
            if kernel.epic_clip_utf8(65001, 128, data, count, out, length, nil, nil) ~= length then
                return nil
            end
            return ffi.string(out, length)
        end,
    }
end
function C.new(deps)
    deps = deps or {}
    local ffi = require('ffi')
    local driver = deps.driver or windows()
    local self = {}
    function self.get()
        if not driver.open(deps.window and deps.window() or nil) then
            return nil, 'Clipboard is busy.'
        end
        local handle, data
        local ok, text = pcall(function()
            handle = driver.get()
            if handle == nil then
                return nil
            end
            local bytes = driver.size(handle)
            if not bytes or bytes < 2 or bytes > (C.MAX_UNITS + 1) * 2 or bytes % 2 ~= 0 then
                return nil
            end
            data = driver.lock(handle)
            if data == nil then
                return nil
            end
            local wide = ffi.cast('const uint16_t *', data)
            local count = 0
            while count < bytes / 2 and wide[count] ~= 0 do
                count = count + 1
            end
            if count == bytes / 2 then
                return nil
            end
            return driver.from_wide(wide, count)
        end)
        if data ~= nil then
            driver.unlock(handle)
        end
        driver.close()
        if not ok or text == nil or #text > C.MAX_BYTES then
            return nil, 'Clipboard has no valid Unicode text.'
        end
        return text
    end
    function self.set(text)
        if type(text) ~= 'string' or #text > C.MAX_BYTES or text:find('%z') then
            return false, 'Clipboard text is too large or invalid.'
        end
        local wide, count = driver.to_wide(text)
        if wide == nil or not count or count > C.MAX_UNITS then
            return false, 'Clipboard text is not valid UTF-8.'
        end
        local handle = driver.alloc((count + 1) * 2)
        if handle == nil then
            return false, 'Clipboard allocation failed.'
        end
        local data = driver.lock(handle)
        if data == nil then
            driver.free(handle)
            return false, 'Clipboard allocation is unavailable.'
        end
        ffi.copy(data, wide, (count + 1) * 2)
        driver.unlock(handle)
        local hwnd = deps.window and deps.window()
        if hwnd == nil or not driver.open(hwnd) then
            driver.free(handle)
            return false, 'Clipboard is busy.'
        end
        local ok, accepted = pcall(function()
            return driver.empty() and driver.set(handle)
        end)
        driver.close()
        if not ok or not accepted then
            driver.free(handle)
            return false, 'Could not copy to the clipboard.'
        end
        return true
    end
    return self
end
return C
