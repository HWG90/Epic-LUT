-- Bounded file operations with deterministic handle cleanup. A supplied platform
-- owns Unicode stream handles; the legacy default retains ordinary Lua IO.
local function create(open, remove, rename)
    local F = { open = open }
    function F.remove(path)
        assert(type(remove) == 'function', 'File removal service required')
        return remove(path)
    end
    function F.rename(source, destination)
        assert(type(rename) == 'function', 'File rename service required')
        return rename(source, destination)
    end
    function F.read(path, limit, optional)
        assert(type(limit) == 'number' and limit >= 0 and limit % 1 == 0, 'File read limit required')
        local file, why, code = open(path, 'rb')
        if not file then
            -- Access/sharing failures cannot stand in for an absent snapshot.
            if optional and (code == nil or code == 2 or code == 3) then
                return nil, why
            end
            error(why or 'File not found', 0)
        end
        local ok, bytes, read_error = pcall(file.read, file, limit + 1)
        local closed, close_error = file:close()
        if not ok then
            error(bytes, 0)
        end
        assert(bytes ~= nil or read_error == nil, read_error)
        assert(closed, close_error)
        bytes = bytes or ''
        assert(#bytes <= limit, 'File size budget exceeded: ' .. path)
        return bytes
    end
    function F.write(path, bytes)
        local file, why = open(path, 'wb')
        assert(file, why)
        local ok, written, write_error = pcall(file.write, file, bytes)
        local closed, close_error = file:close()
        if not ok then
            error(written, 0)
        end
        assert(written, write_error)
        assert(closed, close_error)
        return true
    end
    return F
end
local F = create(function(path, mode)
    if m and m.platform then
        assert(type(m.platform.open) == 'function', 'Unicode file stream service required')
        return m.platform.open(path, mode)
    end
    return io.open(path, mode)
end, function(path)
    if m and m.platform then
        assert(type(m.platform.remove) == 'function', 'Unicode file removal service required')
        return m.platform.remove(path)
    end
    return os.remove(path)
end, function(source, destination)
    if m and m.platform then
        assert(type(m.platform.rename) == 'function', 'Unicode file rename service required')
        return m.platform.rename(source, destination)
    end
    return os.rename(source, destination)
end)
function F.new(platform)
    assert(type(platform) == 'table' and type(platform.open) == 'function', 'Explicit file stream service required')
    return create(platform.open, platform.remove, platform.rename)
end
return F
