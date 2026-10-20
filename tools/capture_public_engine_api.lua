-- One-shot reflection only: never calls an engine function or reads game memory.
-- Kept separate from the editor; no on_update callback, polling or native library.
local I = {}
local namespaces = { 'Application', 'World', 'Unit', 'Mesh', 'Material', 'RenderBuffer',
    'Renderer', 'RenderResource', 'Float32Array', 'Float32ArrayBox', 'Gui', 'Script',
    'Actor', 'Camera', 'Window', 'Keyboard', 'Mouse', 'Player', 'GameSession' }
function I.collect(sr, runtime)
    assert(type(sr) == 'table' and type(runtime) == 'string', 'Engine namespace and Lua version required')
    local capture = { schema = 1, runtime = runtime, lookup = 'raw table members', namespaces = {} }
    local entries, bytes = 0, 0
    for _, name in ipairs(namespaces) do
        local namespace = rawget(sr, name)
        local item = { kind = type(namespace), members = {} }
        if type(namespace) == 'table' then
            for key, value in pairs(namespace) do
                assert(type(key) ~= 'string' or #key <= 240, 'Engine member name exceeds inventory budget')
                if type(key) == 'string' and key:match('^[%w_]+$') then
                    entries, bytes = entries + 1, bytes + #name + #key + 16
                    assert(entries <= 4096 and bytes <= 131072, 'Engine inventory exceeds budget')
                    item.members[#item.members + 1] = key .. ':' .. type(value)
                end
            end
            table.sort(item.members)
        end
        capture.namespaces[name] = item
    end
    capture.entries = entries
    return capture
end
return I
