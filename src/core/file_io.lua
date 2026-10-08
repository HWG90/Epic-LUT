-- Bounded file operations with deterministic handle cleanup.
local F = {}
function F.read(path, limit, optional)
    assert(type(limit) == 'number' and limit >= 0 and limit % 1 == 0, 'File read limit required')
    local file, why = io.open(path, 'rb')
    if not file then
        if optional then
            return nil, why
        end
        error(why or 'File not found', 0)
    end
    local ok, bytes = pcall(file.read, file, limit + 1)
    local closed, close_error = file:close()
    if not ok then
        error(bytes, 0)
    end
    assert(closed, close_error)
    bytes = bytes or ''
    assert(#bytes <= limit, 'File size budget exceeded: ' .. path)
    return bytes
end
function F.write(path, bytes)
    local file, why = io.open(path, 'wb')
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
