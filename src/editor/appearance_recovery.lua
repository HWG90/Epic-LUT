-- Event-requested garment recovery. No subscriptions, timers, UI, or ownership bypasses.
local R = {}

function R.update(state, dt)
    local operations, edit = state.operations, state.edit
    local appearance, appearance_pending = state.appearance, state.pending
    local region_indicator, pattern_editor, frontend = state.indicator, state.patterns, state.frontend
    local appearance_resource, appearance_proof = state.resource, state.proof
    local refresh, groups, bindings = state.refresh, state.groups, state.bindings
    operations.appearance_elapsed = operations.appearance_elapsed or 0
    operations.appearance_worked = false
    if not appearance then return end
    -- One recovery stage per update. Keep both scanners and replay work from
    -- landing in the same gameplay frame; never retain a native read snapshot.
    local job = operations.appearance_recovery
    if not job then
        -- No native reads/scans for unchanged appearance. Only a lifecycle
        -- notification or a bounded unresolved-source retry can request work.
        local generation = edit.appearance_generation or 0
        if generation == (edit.appearance_completed or 0) then
            -- Native actor/equipment events or an explicit edit wake recovery.
            -- Absence of a third-party Lua event bus never enables idle scans.
            return
        end
        if (edit.appearance_retry or 0) >= 40 then
            edit.appearance_completed = generation
            return
        end
        if edit.appearance_wake then
            operations.appearance_elapsed, edit.appearance_wake = 0.5, nil
        end
        operations.appearance_elapsed = operations.appearance_elapsed + math.max(0, dt or 0)
        if operations.appearance_elapsed < 0.5 then return end
        operations.appearance_elapsed = 0
    end
    if (region_indicator and region_indicator.job)
        or (pattern_editor and pattern_editor.flashing())
        or (frontend and frontend.menu and frontend.menu.visible
            and frontend.menu.is_interacting and frontend.menu.is_interacting()) then
        operations.appearance_recovery = nil
        return
    end
    if not job then
        edit.appearance_retry = (edit.appearance_retry or 0) + 1
        for key, pending in pairs(appearance_pending) do
            local b = { original = pending.original, save_key = pending.save_key,
                kind = pending.kind, texture = pending.texture }
            local count = appearance.remember({ b }, pending.pattern,
                { [pending.kind] = pending.proof }, appearance_resource)
            if count > 0 then appearance_pending[key] = nil end
        end
    end
    if appearance.count() == 0 and not (edit.editor_target and edit.editor_target.kind == 'cape') then
        operations.appearance_recovery = nil
        edit.appearance_completed = edit.appearance_generation or 0
        return
    end
    local proof = appearance_proof()
    if not proof then operations.appearance_recovery = nil; return end
    if job and (job.proof.armor ~= proof.armor or job.proof.helmet ~= proof.helmet
        or job.proof.cape ~= proof.cape) then
        operations.appearance_recovery = nil
        operations.appearance_elapsed = 0.5 -- Restart promptly with current gear.
        return
    end
    if not job then
        job = { phase = 1, proof = proof, generation = edit.appearance_generation or 0, pattern_ready = true }
        operations.appearance_recovery = job
    end
    operations.appearance_worked = true
    local function replay(collection, pattern, session)
        local targets = {}
        for _, group in ipairs(collection or {}) do
            for _, b in ipairs(group.bindings) do targets[#targets + 1] = b end
        end
        -- Fresh binding reads and the session's present/ownership/readback
        -- checks still run immediately before every write.
        local observe = operations.discovery_binding()
        for _, batch in ipairs(appearance.batches(targets, pattern, proof, appearance_resource, observe)) do
            session.apply(batch.document, batch.targets)
            for _, b in ipairs(batch.targets) do
                if b.cape then b.applied_cape_proof = proof.cape end
            end
        end
    end
    local phase = job.phase
    job.phase = phase + 1 -- Errors cannot pin a failed stage to every frame.
    if phase == 1 then
        job.material_ready = pcall(refresh, true)
    elseif phase == 2 then
        if job.material_ready then replay(groups, false, bindings) end
    elseif phase == 3 then
        if pattern_editor and operations.pattern_session then
            local ok, discovered = pcall(pattern_editor.scan, true)
            job.pattern_ready = ok
            if ok then job.pattern_groups = discovered end
        end
    else
        operations.appearance_recovery = nil
        if job.pattern_groups and operations.pattern_session then
            replay(job.pattern_groups, true, operations.pattern_session)
        end
        if job.material_ready and job.pattern_ready and not next(appearance_pending) then
            edit.appearance_completed = job.generation
        end
    end
end

return R
