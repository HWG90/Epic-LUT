-- Publish validated worker rows as local presets. Never edits a LUT or game binding.
local P = { MAX_ROWS = 4096, MAX_MANIFEST = 256 * 1024 }
function P.manifest(text)
    assert(type(text) == 'string' and #text <= P.MAX_MANIFEST, 'Paydex row manifest exceeds budget')
    local names, seen = {}, {}
    for line in text:gmatch('[^\r\n]+') do
        local name = line:match('^row%-([%w _%-]+)%.dds$')
        assert(name and #name <= 48 and not name:match('^%s') and not name:match('%s$'), 'Invalid Paydex row filename')
        assert(not seen[name:lower()], 'Duplicate Paydex row filename')
        seen[name:lower()] = true
        names[#names + 1] = { name = name, file = line }
        assert(#names <= P.MAX_ROWS, 'Paydex row count exceeds budget')
    end
    assert(#names > 0, 'No Paydex row presets found')
    return names
end
function P.new(deps)
    local read, write = assert(deps.read), assert(deps.write)
    local move, remove = deps.move or os.rename, deps.remove or os.remove
    local folder, dds = assert(deps.folder), assert(deps.dds)
    local self = {}
    function self.import(base, manifest)
        assert(manifest == 'rows.tsv', 'Invalid Paydex row manifest')
        local rows = P.manifest(read(base .. '/' .. manifest, P.MAX_MANIFEST))
        local plan, chosen, used, cached = {}, {}, {}, {}
        local function existing(path)
            if cached[path] == nil then
                cached[path] = read(path, dds.MAX_BYTES, true) or false
            end
            return cached[path] ~= false and cached[path] or nil
        end
        -- Validate every row and resolve every name before publishing any file.
        for index, row in ipairs(rows) do
            local data = dds.decode(read(base .. '/' .. row.file, 1024), 23, 1)
            local bytes = dds.encode(data, 23, 1)
            local name, suffix = row.name, 1
            while true do
                local path = folder .. '/row-' .. name .. '.dds'
                local prior = existing(path)
                if not used[name:lower()] and (not prior or prior == bytes) then
                    used[name:lower()] = true
                    chosen[index] = name
                    if not prior then
                        plan[#plan + 1] =
                            { path = path, stage = base .. '/publish-' .. index .. '.pending', bytes = bytes }
                    end
                    break
                end
                suffix = suffix + 1
                assert(suffix <= 10000, 'Too many conflicting Paydex preset names')
                local tail = '-' .. suffix
                name = row.name:sub(1, 48 - #tail):gsub('%s+$', '') .. tail
            end
        end
        local published, staged = {}, {}
        local ok, why = pcall(function()
            for _, item in ipairs(plan) do
                assert(not read(item.stage, 1024, true), 'Paydex staging file already exists')
                staged[#staged + 1] = item
                assert(write(item.stage, item.bytes))
            end
            for _, item in ipairs(plan) do
                assert(not read(item.path, dds.MAX_BYTES, true), 'Preset changed during Paydex import')
                -- Windows rename refuses an existing target, including a race
                -- after the read above. Existing preset files are never replaced.
                assert(move(item.stage, item.path))
                published[#published + 1] = item
            end
        end)
        if not ok then
            for _, item in ipairs(published) do
                local got, bytes = pcall(read, item.path, dds.MAX_BYTES, true)
                if got and bytes == item.bytes then
                    pcall(remove, item.path)
                end
            end
            for _, item in ipairs(staged) do
                local got, bytes = pcall(read, item.stage, 1024, true)
                if got and bytes == item.bytes then
                    pcall(remove, item.stage)
                end
            end
            error(why, 0)
        end
        return chosen, #published
    end
    return self
end
return P
