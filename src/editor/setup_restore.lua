-- One bounded startup restore job, separate from UI and lifecycle recovery.
-- Cancellation state is shared explicitly with manual actions and teardown.
local C = {}
function C.new(m, host)
    local S = {}
function S.update()
    if host.resume_state.done or not host.setup() then
        return
    end
    if not host.resume_state.job then
        local identity = m.avatar.resolve_live(host.memory(), host.game())
        if not identity then
            return
        end
        local valid, plan, capes, weapons = pcall(host.setup().read)
        if not valid then
            host.resume_state.done = true
            return host.message('Saved setup is invalid: ' .. tostring(plan))
        end
        if weapons then
            assert(host.start_weapons, 'Weapon startup storage is unavailable in this build')
            host.start_weapons(weapons)
        end
        if not next(plan) then
            host.resume_state.done = true
            return
        end
        capes = capes or {}
        local function matches(key, b)
            local captured = capes[key]
            if not b.cape then
                return captured == nil
            end
            if not captured then
                return false
            end
            local proof = host.appearance_proof()
            if not proof or not proof.cape then
                return nil
            end
            if proof.cape ~= captured.proof then
                return false
            end
            local original = host.original_luts() and host.original_luts().get(b.original)
            if not original then
                return nil
            end
            return original.resource == captured.resource
        end
        host.resume_state.job = coroutine.create(function()
            local documents = {}
            local total = 0
            for _, file in pairs(plan) do
                if not documents[file] then
                    local f = assert(io.open(host.paths().presets .. '/' .. file, 'rb'), 'Saved palette missing')
                    local bytes = f:read(m.dds.MAX_BYTES + 1)
                    f:close()
                    local data, w, h = m.dds.decode(bytes)
                    assert(w == 23 or (w == 3 and h == 1), 'Saved palette is not a material or Pattern LUT')
                    total = total + w * h * 16
                    assert(total <= 8 * 1024 * 1024, 'Saved palette budget exceeded')
                    documents[file] = { data = data, width = w, height = h }
                    coroutine.yield()
                end
            end
            local files = {}
            local has_patterns = false
            for key, file in pairs(plan) do
                local pattern = key:sub(1, 2) == 'p:'
                local document = documents[file]
                assert(
                    (pattern and document.width == 3 and document.height == 1) or (not pattern and document.width == 23),
                    'Saved LUT layout does not match its destination'
                )
                has_patterns = has_patterns or pattern
            end
            if has_patterns then
                assert(host.pattern_editor() and host.operations.pattern_session, 'Pattern setup restoration unavailable')
            end
            for file, document in pairs(documents) do
                if document.width == 23 then
                    files[#files + 1] = file
                end
            end
            table.sort(files)
            local palettes = {}
            local labels = {}
            for i, file in ipairs(files) do
                palettes[i] = host.paths().presets .. '/' .. file
                labels[i] = file == plan['armor-all']
                        and (file == plan['helmet-all'] and 'Saved Armor + Helmet' or 'Saved Armor')
                    or file == plan['helmet-all'] and 'Saved Helmet'
                    or 'Saved LUT override ' .. i
            end
            host.set_palettes(palettes)
            host.palette_choices(#labels > 0 and labels or { 'Import first' })
            if not host.edit.loaded and files[1] then
                host.edit.loaded = documents[files[1]]
                if host.palette_editor() then
                    host.palette_editor().sync()
                end
            end
            local ok, changed = host.disable_matching()
            assert(ok, changed)
            coroutine.yield()
            coroutine.yield() -- Let the original provider release its bindings.
            local by_file = {}
            local pattern_files = {}
            local began = os.time()
            local expected = 0
            local next_scan = 0
            for key in pairs(plan) do
                if key ~= 'armor-all' and key ~= 'helmet-all' then
                    expected = expected + 1
                end
            end
            repeat
                local now = host.memory().time and host.memory().time() or os.clock()
                if now < next_scan then
                    coroutine.yield()
                else
                    next_scan = now + 0.25
                    local scanned = pcall(host.refresh)
                    local matched, seen = 0, {}
                    by_file = {}
                    pattern_files = {}
                    if scanned then
                        for _, group in ipairs(host.groups()) do
                            for _, b in ipairs(group.bindings) do
                                local accepted = matches(b.save_key, b)
                                if plan[b.save_key] and accepted ~= nil and not seen[b.save_key] then
                                    matched = matched + 1
                                    seen[b.save_key] = true
                                end
                                local file = accepted and plan[b.save_key]
                                    or (b.armor and plan['armor-all'])
                                    or (b.helmet and plan['helmet-all'])
                                if file then
                                    by_file[file] = by_file[file] or {}
                                    table.insert(by_file[file], b)
                                end
                            end
                        end
                    end
                    local patterns_ready = not has_patterns or pcall(host.pattern_editor().scan)
                    if has_patterns and patterns_ready then
                        for _, group in ipairs(host.pattern_editor().all_groups or {}) do
                            for _, b in ipairs(group.bindings) do
                                local key = 'p:' .. b.save_key
                                local accepted = matches(key, b)
                                local file = accepted and plan[key]
                                if plan[key] and accepted == false and not seen[key] then
                                    matched = matched + 1
                                    seen[key] = true
                                end
                                if file then
                                    if not seen[key] then
                                        matched = matched + 1
                                        seen[key] = true
                                    end
                                    pattern_files[file] = pattern_files[file] or {}
                                    table.insert(pattern_files[file], b)
                                end
                            end
                        end
                    end
                    if scanned and patterns_ready and (matched >= expected or os.time() - began >= 10) then
                        break
                    end
                    assert(os.time() - began < 15, 'Local LUTs are not ready for the saved setup')
                    coroutine.yield()
                end
            until false
            local applied = 0
            for file, targets in pairs(by_file) do
                local checked = {}
                for _, b in ipairs(targets) do
                    if matches(b.save_key, b) then
                        checked[#checked + 1] = b
                    end
                end
                local count, texture = 0
                if #checked > 0 then
                    count, texture = host.apply_bindings(documents[file], checked)
                end
                applied = applied + count
                if file == plan['armor-all'] then
                    host.set_default('armor', texture)
                end
                if file == plan['helmet-all'] then
                    host.set_default('helmet', texture)
                end
                if not host.edit.loaded then
                    host.edit.loaded = documents[file]
                    if host.palette_editor() then
                        host.palette_editor().sync()
                    end
                end
                coroutine.yield()
            end
            for file, targets in pairs(pattern_files) do
                local checked = {}
                for _, b in ipairs(targets) do
                    if matches('p:' .. b.save_key, b) then
                        checked[#checked + 1] = b
                    end
                end
                if #checked > 0 then
                    applied = applied + host.operations.pattern_session.apply(documents[file], checked)
                    host.remember_appearance(checked, true)
                end
                coroutine.yield()
            end
            host.edit.remember_application = applied > 0
            host.message('Saved setup restored to ' .. applied .. ' local bindings. Unmatched slots were skipped.')
        end)
    end
    local ok, why = coroutine.resume(host.resume_state.job)
    if not ok then
        host.resume_state.done = true
        host.resume_state.job = nil
        host.message('Saved setup could not resume: ' .. tostring(why))
    elseif coroutine.status(host.resume_state.job) == 'dead' then
        host.resume_state.done = true
        host.resume_state.job = nil
    end
end
    return S
end
return C
