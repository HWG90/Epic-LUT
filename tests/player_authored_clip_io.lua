-- Actual authored resource loader with owned streams; no game bytes or decoder substitute.
local FileIO = dofile('src/core/file_io.lua')
local function scenario(kind, explicit)
    local opened, closed = 0, 0
    local function open(path, mode)
        assert(path:sub(1, #'cache-服装/') == 'cache-服装/' and mode == 'rb')
        opened = opened + 1
        return {
            read = function(_, limit)
                assert(limit == 1048577)
                if kind == 'read-throw' then error('owned-read-threw') end
                if kind == 'read-error' then return nil, 'owned-read-error' end
                if kind == 'oversize' then return string.rep('x', limit) end
                -- Invalid format intentionally exercises decoder failure after all IO closes.
                return 'invalid-authored-resource'
            end,
            close = function()
                closed = closed + 1
                if kind == 'close-throw' then error('owned-close-threw') end
                if kind == 'close-error' then return nil, 'owned-close-error' end
                return true
            end,
        }
    end
    local files = FileIO.new({ open = open })
    local env = setmetatable({
        m = { file_io = explicit and { open = function() error('Default used before explicit IO') end } or files },
        io = { open = function() error('Global IO reached') end },
    }, { __index = _G })
    local Clip = setfenv(assert(loadfile('src/preview/player_authored_clip.lua')), env)()
    local ok, why = pcall(Clip.load, 'cache-服装', explicit and files or nil)
    assert(not ok, 'Malformed resources must not decode successfully')
    assert(opened == closed and opened > 0, 'Owned stream was not closed on failure')
    if kind == 'read-throw' then assert(tostring(why):find('owned-read-threw', 1, true))
    elseif kind == 'read-error' then assert(tostring(why):find('owned-read-error', 1, true))
    elseif kind == 'close-throw' then assert(tostring(why):find('owned-close-threw', 1, true))
    elseif kind == 'close-error' then assert(tostring(why):find('owned-close-error', 1, true))
    elseif kind == 'oversize' then assert(tostring(why):find('size bound', 1, true))
    else
        local expected = 0
        for _ in pairs(Clip.FILES) do expected = expected + 1 end
        assert(opened == expected, 'Failed before all resource reads completed')
    end
end
for _, kind in ipairs({ 'read-throw', 'read-error', 'close-throw', 'close-error', 'oversize', 'decode-error' }) do
    scenario(kind, false)
    scenario(kind, true)
end
print('player_authored_clip_io: PASS')
