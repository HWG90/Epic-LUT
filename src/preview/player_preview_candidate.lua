-- Preview lifecycle adapter shared by integrated builds and the standalone test sidecar.
local enable, update, disable, cleanup = editor.on_enable, editor.on_update, editor.on_disable, editor.on_cleanup_poll
local controller, adapter, memory, game, log
local authored_source
local activated, base_enabled = false, false
local frontend_owner
local initialization_stage
local wrapper, previous
local pressed = false
local elapsed = 0
local due = false
local first = true
local request_path = (os.getenv('LOCALAPPDATA') or '') .. '/Epic LUT/cache/player-preview-request.txt'
local request_elapsed = 0
local capture_requested = false
local debug_requested = false
local single_frame = false
local recovering = false
local render_fault
local retry_at = 0
local recovery_attempts = 0
local controls = m.player_preview_controls.new()
local pose_state = { applied = 'idle', pending = false, reopen = false }
local source_signature
local source_elapsed = 0
local recovery_elapsed = 0
local close_pending = false
local suspended = false
local frame_clock
local clock_fallback_logged = false
local function finite_delta(value)
    return type(value) == 'number' and value == value and value >= 0 and value < math.huge
end
local function update_delta(context, delta)
    local now
    if memory and type(memory.time) == 'function' then
        local ok, value = pcall(memory.time)
        if ok and finite_delta(value) then
            now = value
        end
    end
    local measured = now and frame_clock and math.min(0.05, math.max(0, now - frame_clock)) or nil
    frame_clock = now
    -- Both loader callback forms are supported; a missing delta must not
    -- silently freeze the portrait's pose and redraw timers.
    if finite_delta(delta) then
        return delta
    elseif finite_delta(context) then
        return context
    end
    if not clock_fallback_logged and log then
        clock_fallback_logged = true
        log('preview: missing update delta; using ' .. (now and 'measured frame clock' or 'default frame interval'))
    end
    return measured or (now and 0 or 1 / 60)
end
local function render_ready()
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    if not front or not front.input.focused() then
        return false
    end
    if front.render_ready then
        return front.render_ready()
    end
    local w, h = stingray.Gui.resolution()
    return type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 and w < math.huge and h < math.huge
end
local function signature(identity)
    local parts = { identity.unit, identity.body, identity.armor, identity.helmet, identity.cape or 0 }
    for _, piece in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
        parts[#parts + 1] = piece.unit
    end
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    return table.concat(parts, ':')
end
local public = {}
function public.is_enabled()
    if not activated then
        return false
    end
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    local owner = front and front.api and front.api.mods and front.api.mods.epic_direct_lut
    if not owner or not owner.controls or not owner.controls.disable_player_preview or not owner.handle then
        return true
    end
    local ok, disabled = pcall(owner.handle.get, 'disable_player_preview')
    return not ok or disabled ~= true
end
local preview_disabled = false
local dock_request
local dock_age = 1
local docked = false
local floating_geometry
local dock_hidden = false
local floating_on_editor = false
local input_bridge
local function clear_pose_dropdown()
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    if front and front.menu and front.menu.dropdown and front.menu.dropdown.preview_owner == public then
        front.menu.dropdown = nil
    end
end
local function release_input()
    if input_bridge then
        input_bridge.release()
    end
end
local state_path = (os.getenv('LOCALAPPDATA') or '') .. '/Epic LUT/cache/player-preview-state.txt'
local function write_state(detail)
    local owner = package.loaded['epic.player_preview.v1']
    if owner and owner ~= public then
        return
    end
    local file = io.open(state_path, 'wb')
    if file then
        file:write((controller and controller.state or 'disabled') .. '\n' .. (detail or ''):sub(1, 512))
        file:close()
    end
end
local capture_path = (os.getenv('LOCALAPPDATA') or '') .. '/Epic LUT/cache/player-preview-frame.dds'
local function unhook()
    if wrapper and rawget(_G, 'render') == wrapper then
        rawset(_G, 'render', previous)
    end
    wrapper = nil
    previous = nil
end
local function close(pose_transition)
    clear_pose_dropdown()
    if not pose_transition then
        pose_state.reopen = false
    end
    release_input()
    unhook()
    due = false
    single_frame = false
    capture_requested, debug_requested = false, false
    if controller and #controller.resources > 0 and not render_ready() then
        close_pending = true
        return false
    end
    local done = not controller or controller.close()
    close_pending = not done
    write_state(render_fault or (not done and controller and controller.error) or '')
    return done
end
local function reset_transients()
    -- Only after close() acknowledges retirement. Adapter cleanup may still
    -- reference the old controls until its render fence completes.
    activated = false
    pressed, due, first = false, false, true
    elapsed, request_elapsed, source_elapsed, recovery_elapsed = 0, 0, 0, 0
    capture_requested, debug_requested, single_frame = false, false, false
    recovering, render_fault, retry_at, recovery_attempts = false, nil, 0, 0
    source_signature = nil
    close_pending = false
    suspended = false
    frame_clock, clock_fallback_logged = nil, false
    preview_disabled = false
    initialization_stage = nil
    authored_source = nil
    dock_request, dock_age, docked = nil, 1, false
    floating_geometry, dock_hidden, floating_on_editor = nil, false, false
    input_bridge = nil
    controls = m.player_preview_controls.new()
    pose_state = { applied = 'idle', pending = false, reopen = false }
end
local function discard_request()
    os.remove(request_path)
    local stale = io.open(request_path, 'rb')
    if stale then
        stale:close()
        error('Stale Player Preview request could not be cleared', 0)
    end
end
local function open()
    assert(render_ready(), 'Player Preview waits for game focus and valid display dimensions')
    assert(public.is_enabled(), 'Player Preview is turned off in Configuration')
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    assert(
        front and front.preview_cleanup_guard == true,
        'Editor cleanup handshake is unavailable; update editor before enabling preview'
    )
    assert(type(rawget(_G, 'render')) == 'function', 'Render callback is unavailable')
    local identity, why = m.avatar.resolve(memory, game)
    assert(identity, why)
    local current_signature = signature(identity)
    local gear = adapter.capture(identity)
    local ok, err = controller.open(gear)
    assert(ok, err)
    adapter.zoom(controller.camera, controls.fov)
    adapter.rotate(controller.camera, controls.yaw, controls)
    source_signature = current_signature
    source_elapsed = 0
    previous = rawget(_G, 'render')
    local forward = previous
    local render_owner = controller
    first = true
    wrapper = function(...)
        forward(...)
        -- A foreign wrapper may retain this function after we detach. It must
        -- not submit a later activation's controller or consume its captures.
        if not activated or controller ~= render_owner then
            return
        end
        if not render_ready() then
            due = false
            return
        end
        local front = package.loaded['dbf.epic_lut.frontend.v1']
        if front and not front.menu.visible then
            due = false
        end
        if due and controller.state == 'ready' then
            due = false
            if first then
                log('preview: first portrait render begin')
            end
            local done, problem = controller.render()
            if
                not done
                and (
                    tostring(problem):find('context disappeared', 1, true)
                    or tostring(problem):find('resolution changed', 1, true)
                )
            then
                recovering = recovery_attempts < 3
                retry_at = recovery_elapsed + 1
            elseif not done then
                -- Missing APIs or invalid shader preparation are permanent for
                -- this activation. Automatic docking must not recreate a failed
                -- panel every frame; manual open is the retry boundary.
                render_fault = tostring(problem)
                recovering, dock_hidden = false, true
            end
            if first or not done then
                log(
                    done and 'preview: portrait render submitted; pixels unverified'
                        or 'preview: render failed ' .. tostring(problem)
                )
            end
            first = false
            write_state(done and 'render submitted' or tostring(problem))
        end
        if capture_requested then
            capture_requested = false
            if debug_requested then
                debug_requested = false
                local ok, why = pcall(adapter.debug_target)
                log(
                    ok and 'preview: target diagnostic composite submitted'
                        or 'preview: target diagnostic failed ' .. tostring(why)
                )
            end
            log('preview: game frame capture begin')
            local ok, why = pcall(stingray.Application.save_render_target, 'back_buffer', capture_path)
            log(ok and 'preview: game frame capture requested' or 'preview: capture failed ' .. tostring(why))
        end
    end
    rawset(_G, 'render', wrapper)
    write_state('waiting for first render')
    log('preview: copied portrait opened')
end
local function inspect()
    local identity, why = m.avatar.resolve(memory, game)
    assert(identity, why)
    return adapter.capture(identity)
end
local function pose_notice(text)
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    if front and front.menu then
        front.menu.notice = text
        front.menu.redraw_revision = (front.menu.redraw_revision or 0) + 1
    end
    log('preview: ' .. text)
end
local function pose_failed(why)
    pose_state.pending, pose_state.caption_dirty = false, true
    pose_state.error = tostring(why)
    controls.pose = pose_state.applied
    controls.animation_pending, controls.animation_error = false, pose_state.error
    pose_notice('Preview pose unavailable: ' .. pose_state.error)
end
local function update_pose()
    if pose_state.caption_dirty and controller.state == 'ready' then
        adapter.layout_panel()
        pose_state.caption_dirty = false
    end
    if not pose_state.pending then
        return false
    end
    local selected = controls.pose
    if selected ~= 'idle' then
        if authored_source and (authored_source.state == 'closed' or authored_source.state == 'failed') then
            if authored_source.state == 'failed' and not pose_state.source_retry then
                pose_failed(authored_source.error or 'Authored pose resources unavailable')
                return false
            end
            if not authored_source.close() then
                return false
            end
            authored_source = nil
        end
        if not authored_source then
            authored_source = m.player_authored_source.new(m, { time = memory.time, log = log })
        end
        pose_state.source_retry = false
        authored_source.start()
        authored_source.tick()
        if authored_source.state == 'failed' then
            pose_failed(authored_source.error or 'Authored pose resources unavailable')
            return false
        end
        if not authored_source.get() then
            return false
        end
    elseif authored_source and (authored_source.state == 'loading' or authored_source.state == 'failed') then
        if not authored_source.close() then
            return false
        end
    end
    if controller.state ~= 'closed' and not close(true) then
        return true
    end
    pose_state.pending = false
    controls.animation_pending = false
    if pose_state.reopen then
        local ok, why = pcall(open)
        if not ok then
            close(true)
            pose_state.applied = 'idle'
            pose_failed(why)
        elseif controller.model.animation_failed then
            pose_state.applied = 'idle'
            pose_failed(controls.animation_error or 'Owned garment pose unavailable')
        else
            pose_state.applied = selected
        end
    else
        pose_state.applied = selected
    end
    pose_state.reopen = false
    return true
end
local function initialize_preview(ctx)
    local owner = package.loaded['epic.player_preview.v1']
    assert(not owner or owner == public, 'Player Preview is already owned by another addon instance')
    discard_request()
    assert(close(), 'Player Preview cleanup is pending; wait before re-enabling')
    assert(not authored_source or authored_source.close(), 'Authored salute worker cleanup is pending')
    reset_transients()
    initialization_stage = 'editor'
    base_enabled = true
    enable(ctx)
    frontend_owner = package.loaded['dbf.epic_lut.frontend.v1']
    log = ctx.log
    initialization_stage = 'memory'
    memory = m.bingus_memory.new(m.bingus_runtime)
    controls.pose_available = not not (
        m.player_authored_clip
        and m.player_authored_clip.POSES
        and m.player_authored_clip.find_pose
        and m.player_authored_source
    )
    game = memory.address(assert(memory.module('game.dll')))
    local native = assert(m.engine.open(memory, game, memory.address(assert(memory.module()))))
    initialization_stage = 'submission_bindings'
    local submit = m.player_preview_submit.new(memory, game, memory.address(assert(memory.module())))
    initialization_stage = nil
    log('preview: native submission signatures verified')
    adapter = m.player_preview_native.new(stingray, m, {
        memory = memory,
        native = native,
        log = log,
        submit = submit,
        game = game,
        use_ui_world = true,
        -- Every package starts with the static portrait. An explicit pose
        -- request supplies authored data and captures only owned hierarchies.
        animate = false,
        get_animation_source = function()
            return authored_source
        end,
        controls = controls,
    })
    controller = m.player_preview.new(adapter)
    activated = true
    public.get_pose = function()
        return controls.pose or 'idle', pose_state.error
    end
    public.set_pose = function(id)
        if not activated or not public.is_enabled() then
            return false, 'Player Preview is turned off'
        end
        local selected = m.player_authored_clip and m.player_authored_clip.find_pose(id)
        if not selected then
            return false, 'Unknown Player Preview pose'
        end
        if id ~= 'idle' and not m.player_authored_source then
            return false, 'Authored pose resources unavailable in this preview'
        end
        if controls.pose == id and not pose_state.error then
            return true
        end
        clear_pose_dropdown()
        controls.pose = id
        controls.animation_pending, controls.animation_error = id ~= 'idle', nil
        pose_state.pending, pose_state.error, pose_state.caption_dirty = true, nil, true
        pose_state.source_retry = true
        pose_state.reopen = pose_state.reopen or controller.state ~= 'closed'
        return true
    end
    public.open_pose_dropdown = function()
        local front = package.loaded['dbf.epic_lut.frontend.v1']
        local menu = front and front.menu
        local catalog = m.player_authored_clip and m.player_authored_clip.POSES
        if
            not menu
            or not menu.open_dropdown
            or not catalog
            or not controls.pose_available
            or not public.is_ready()
        then
            return false
        end
        local choices, selected = {}, 1
        for index, pose in ipairs(catalog) do
            choices[index] = pose.label
            if pose.id == controls.pose then
                selected = index
            end
        end
        local control = { id = 'player_preview_pose', type = 'choice', choices = choices }
        local handle = {}
        handle.get = function()
            for index, pose in ipairs(catalog) do
                if pose.id == controls.pose then
                    return index
                end
            end
            return 1
        end
        handle.preview = handle.get
        handle.set = function(id, value)
            if id ~= control.id or type(value) ~= 'number' or value % 1 ~= 0 or not catalog[value] then
                return false, 'Unknown Player Preview pose'
            end
            return public.set_pose(catalog[value].id)
        end
        handle.edit = handle.set
        local b = menu.window_bounds or { x = 0, y = 0, scale = 1 }
        menu.open_dropdown({
            mod = { handle = handle },
            control = control,
            selected = selected,
            scroll = 0,
            x = (controls.x + controls.w / 3 - b.x) / b.scale,
            top = (controls.y - b.y) / b.scale,
            width = math.max(160, controls.w / 3) / b.scale,
            screen_anchor = true,
            preview_owner = public,
        })
        controls.cancel()
        return true
    end
    public.before_editor_close = function()
        recovering = false
        dock_hidden = false
        return close()
    end
    public.toggle = function()
        if not public.is_enabled() then
            local why = 'Player Preview is turned off in Configuration'
            log('preview: ' .. why)
            return false, why
        end
        local retry_fault = render_fault ~= nil
        -- Diagnostic one-frame requests apply to that opening only. The
        -- ordinary UI toggle always returns to a live portrait.
        single_frame = false
        render_fault = nil
        recovering = false
        recovery_attempts = 0
        if dock_request and dock_age < 0.2 then
            if not retry_fault then
                floating_on_editor = not floating_on_editor
            end
            dock_hidden = false
            return true
        end
        if controller.state ~= 'closed' then
            dock_hidden = docked
            return close()
        end
        dock_hidden = false
        local ok, why = pcall(open)
        if not ok then
            close()
            log('preview: setup stopped ' .. tostring(why))
        end
        return ok, why
    end
    public.is_ready = function()
        return public.is_enabled() and controller.state == 'ready' and controller.model ~= nil
    end
    public.last_error = function()
        return render_fault
    end
    public.is_docked = function()
        return public.is_enabled()
            and docked
            and not dock_hidden
            and not floating_on_editor
            and controller.state == 'ready'
    end
    public.dock = function(bounds)
        if not public.is_enabled() then
            return
        end
        local front = package.loaded['dbf.epic_lut.frontend.v1']
        local window = front and front.menu.window_bounds
        if not window then
            return
        end
        local s = window.scale
        dock_request = { x = window.x + bounds.x * s, y = window.y + bounds.y * s, w = bounds.w * s, h = bounds.h * s }
        dock_age = 0
    end
    package.loaded['epic.player_preview.v1'] = public
    write_state(PREVIEW_INSPECT_ONLY and 'inspection only' or 'ready to open')
    local cleanup_owner = controller
    ctx.on_cleanup(function()
        if controller ~= cleanup_owner then
            if #cleanup_owner.resources > 0 and not render_ready() then
                return false
            end
            return cleanup_owner.close()
        end
        return close()
    end)
    log(
        PREVIEW_INSPECT_ONLY and 'preview: read-only model inspector ready'
            or 'preview: independent player portrait candidate ready'
    )
    log(
        'preview: build='
            .. tostring(m.build_label or m.version or 'sidecar')
            .. '; id='
            .. tostring(m.dev_build_id or 'unmarked')
            .. '; animation='
            .. (PREVIEW_ANIMATION_ENABLED == true and (m.preview_animation or 'garment_poses') or 'static')
    )
end
editor.on_enable = function(ctx)
    local ok, result = xpcall(function()
        return initialize_preview(ctx)
    end, debug.traceback)
    if not ok then
        local problem = tostring(result)
        local first_line = problem:match('^[^\r\n]*') or problem
        local stage = initialization_stage
        initialization_stage = nil
        -- Loader status labels reject control characters and oversized text.
        -- Keep the useful trace bounded on one line; do not feed tabs/newlines
        -- from debug.traceback back into the loader's native log panel.
        ctx.log(('preview: initialization failed ' .. problem:gsub('[%c]+', ' | ')):sub(1, 480))
        if
            stage == 'submission_bindings'
            and first_line:match('table overflow$')
            and base_enabled
            and frontend_owner
            and (not controller or #controller.resources == 0)
        then
            -- No portrait has been created at this point. The editor is ready
            -- and may keep running while this optional native binding is absent.
            render_fault = 'Player Preview native binding limit reached; restart the game to restore preview.'
            ctx.log('preview: ' .. render_fault .. ' Editor remains available.')
            write_state(render_fault)
            return
        end
        error(first_line:gsub('[%c]+', ' '):sub(1, 400), 0)
    end
    return result
end
local function read_request(dt)
    request_elapsed = request_elapsed + (dt or 0)
    if request_elapsed < 0.25 then
        return
    end
    request_elapsed = 0
    local file = io.open(request_path, 'rb')
    if file then
        local request = file:read(16)
        file:close()
        os.remove(request_path)
        return request
    end
end
editor.on_update = function(ctx, dt)
    if activated then
        dt = update_delta(ctx, dt)
    end
    update(ctx, dt)
    if not activated then
        return
    end
    if authored_source then
        authored_source.tick()
    end
    if not render_ready() then
        clear_pose_dropdown()
        due = false
        controls.cancel()
        suspended = true
        return
    end
    local resumed = suspended
    suspended = false
    if close_pending and not close(pose_state.pending and pose_state.reopen) then
        return
    end
    dock_age = dock_age + (dt or 0)
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    if not public.is_enabled() then
        if not preview_disabled then
            log('preview: Player Preview turned off in Configuration')
        end
        preview_disabled = true
        recovering = false
        recovery_attempts = 0
        capture_requested, debug_requested = false, false
        floating_on_editor, dock_hidden = false, false
        dock_request = nil
        controls.can_dock = false
        controls.cancel()
        if docked then
            docked = false
            controls.docked = false
            controls.x, controls.y, controls.w, controls.h = unpack(floating_geometry)
            floating_geometry = nil
        end
        -- Retain the controller and its cleanup receipts until the normal
        -- render fence acknowledges retirement. Never force-release a lease.
        if controller.state ~= 'closed' then
            close()
        end
        -- Discard diagnostic requests while disabled so they cannot open a
        -- stale portrait when the saved preference is enabled again.
        read_request(dt)
        pressed = false
        return
    end
    if preview_disabled then
        render_fault = nil
    end
    preview_disabled = false
    if front and not front.menu.visible then
        recovering = false
    end
    if front and not front.menu.visible and controller.state == 'ready' then
        recovering = false
        dock_hidden = false
        close()
        log('preview: closed with editor before game UI transition')
    end
    if front and front.menu.visible then
        local ok, changed = pcall(update_pose)
        if not ok then
            pose_failed(changed)
        elseif changed then
            return
        end
    end
    local editor_page = dock_request and dock_age < 0.2 and front and front.menu.visible
    local wants_dock = editor_page and not floating_on_editor
    controls.can_dock = editor_page
    if wants_dock then
        if not docked then
            clear_pose_dropdown()
            floating_geometry = { controls.x, controls.y, controls.w, controls.h }
            docked = true
            controls.docked = true
            controls.cancel()
        end
        local b = dock_request
        local changed = controls.x ~= b.x or controls.y ~= b.y or controls.w ~= b.w or controls.h ~= b.h
        controls.x, controls.y, controls.w, controls.h = b.x, b.y, b.w, b.h
        if controller.state == 'closed' and not dock_hidden and not recovering and not render_fault then
            local ok, why = pcall(open)
            if not ok then
                close()
                dock_hidden = true
                log('preview: dock unavailable ' .. tostring(why))
            end
        elseif changed and controller.state == 'ready' then
            adapter.layout_panel()
        end
    elseif docked then
        clear_pose_dropdown()
        docked = false
        controls.docked = false
        dock_hidden = false
        controls.cancel()
        close()
        controls.x, controls.y, controls.w, controls.h = unpack(floating_geometry)
        floating_geometry = nil
        if floating_on_editor and editor_page then
            local ok, why = pcall(open)
            if not ok then
                close()
                log('preview: pop-out unavailable ' .. tostring(why))
            end
        end
    end
    if controller.state == 'closing' then
        close()
    end
    -- Development submissions are explicit file requests until rendering is
    -- proven. An accidental F6 must not enter the repeated-render path.
    local preview_key = front
            and front.preferences
            and front.preferences.preview_key
            and front.preferences.preview_key()
        or 117
    public.key_label = preview_key >= 112 and preview_key <= 135 and ('F' .. (preview_key - 111))
        or ('VK ' .. preview_key)
    local key = front
            and front.menu.visible
            and not front.menu.capture
            and not front.menu.text_edit
            and front.input.focused()
            and front.input.down(preview_key)
        or false
    local request = read_request(dt)
    if resumed then
        pressed = key
    end
    if request == 'close' then
        close()
    end
    if request == 'close' then
        recovering = false
        recovery_attempts = 0
    end
    if request == 'capture' then
        capture_requested = true
    end
    if request == 'debug' then
        debug_requested = true
        capture_requested = true
    end
    -- Development-only fault injection: exercise the normal identity-change
    -- recovery without modifying a game unit, kit or native pointer.
    if request == 'rebuild' and controller.state == 'ready' then
        source_signature = ''
        source_elapsed = 1
    end
    if request == 'turn' and controller.state == 'ready' then
        controls.yaw = (controls.yaw + 90) % 360
        adapter.rotate(controller.camera, controls.yaw, controls)
        due = true
        log('preview: test camera yaw ' .. controls.yaw)
    end
    if request == 'inspect' or (PREVIEW_INSPECT_ONLY and key and not pressed) then
        local ok, why = pcall(inspect)
        if not ok then
            log('preview: inspection stopped ' .. tostring(why))
        end
    end
    if request == 'once' then
        single_frame = true
        request = 'open'
    end
    if request == 'live' then
        single_frame = false
        request = 'open'
    end
    if key and not pressed and not PREVIEW_INSPECT_ONLY then
        single_frame = false
        public.toggle()
    end
    if not PREVIEW_INSPECT_ONLY and (request == 'open' and controller.state == 'closed') then
        render_fault = nil
        if controller.state ~= 'closed' then
            close()
            log('preview: portrait closed')
        else
            recovering = false
            recovery_attempts = 0
            local ok, why = pcall(open)
            if not ok then
                close()
                log('preview: setup stopped ' .. tostring(why))
            end
        end
    end
    pressed = key
    recovery_elapsed = recovery_elapsed + (dt or 0)
    if
        recovering
        and front
        and front.menu.visible
        and controller.state == 'closed'
        and recovery_elapsed >= retry_at
    then
        recovery_attempts = recovery_attempts + 1
        local ok, why = pcall(open)
        if ok then
            recovering = false
            log('preview: rebuilt copied model after context change')
        else
            close()
            retry_at = recovery_elapsed + 1
            if recovery_attempts >= 3 then
                recovering = false
                dock_hidden = docked
                log('preview: recovery stopped ' .. tostring(why))
            end
        end
    end
    if controller.state == 'ready' then
        local advanced, changed = true, false
        if not single_frame or first then
            advanced, changed = controller.advance(resumed and 0 or dt)
        end
        if not advanced then
            close()
            dock_hidden = docked
            log('preview: animation stopped ' .. tostring(changed))
            if tostring(changed):find('changed', 1, true) or tostring(changed):find('disappeared', 1, true) then
                recovering = recovery_attempts < 3
                retry_at = recovery_elapsed + 1
            end
            return
        end
        if changed then
            due = true
        end
        local front = package.loaded['dbf.epic_lut.frontend.v1']
        if not front or not front.menu.visible or not front.input.focused() then
            controls.cancel()
        end
        if not input_bridge then
            local input_owner = controller
            input_bridge = m.player_preview_input.new({
                controls = controls,
                ready = function()
                    return activated and controller == input_owner and controller.state == 'ready'
                end,
                resolution = function()
                    return stingray.Gui.resolution()
                end,
                event = function(event)
                    if event == 'close' then
                        recovering = false
                        dock_hidden = docked
                        close()
                    elseif event == 'dock' then
                        public.toggle()
                    elseif event == 'pose' then
                        public.open_pose_dropdown()
                    elseif event == 'move' or event == 'resize' or event == 'animation' then
                        clear_pose_dropdown()
                        adapter.layout_panel()
                    elseif event == 'rotate' or event == 'pan' then
                        clear_pose_dropdown()
                        adapter.rotate(controller.camera, controls.yaw, controls)
                        due = true
                    elseif event == 'zoom' then
                        clear_pose_dropdown()
                        adapter.zoom(controller.camera, controls.fov)
                        adapter.rotate(controller.camera, controls.yaw, controls)
                        due = true
                    end
                end,
                zoom = function()
                    adapter.zoom(controller.camera, controls.fov)
                    adapter.rotate(controller.camera, controls.yaw, controls)
                end,
                changed = function()
                    due = true
                end,
                failed = function(kind, why)
                    if not activated or controller ~= input_owner then
                        return
                    end
                    close()
                    log('preview: ' .. kind .. ' stopped ' .. tostring(why))
                end,
            })
        end
        input_bridge.attach(front)
        elapsed = elapsed + (dt or 0)
        source_elapsed = source_elapsed + (dt or 0)
        if elapsed >= 0.1 then
            elapsed = 0
            -- Read live material bindings so F9/F10 edits appear on the copy.
            local ok, why = pcall(function()
                if source_elapsed >= 1 then
                    source_elapsed = 0
                    local current, reason = m.avatar.resolve(memory, game)
                    assert(current, 'Equipped source changed: ' .. tostring(reason))
                    assert(signature(current) == source_signature, 'Equipped source changed; rebuild preview')
                end
                adapter.apply_luts(controller.model, { armor = true, helmet = true })
            end)
            if not ok then
                close()
                log('preview: palette sync stopped ' .. tostring(why))
                dock_hidden = docked
                if
                    tostring(why):find('disappeared', 1, true)
                    or tostring(why):find('Source changed', 1, true)
                    or tostring(why):find('source changed', 1, true)
                then
                    recovering = recovery_attempts < 3
                    retry_at = recovery_elapsed + 1
                    if not recovering then
                        dock_hidden = docked
                    end
                end
            elseif not single_frame or first then
                due = true
            end
        end
    end
end
local function dismiss_frontend()
    local owner = package.loaded['epic.player_preview.v1']
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    if not base_enabled or not front or front ~= frontend_owner or (owner and owner ~= public) then
        return true
    end
    if type(front.dismiss) ~= 'function' then
        return true
    end
    local ok, done = pcall(front.dismiss)
    if not ok then
        if log then
            log('preview: editor dismissal pending ' .. tostring(done))
        end
        return false
    end
    return done ~= false
end
local function close_authored_source()
    if not authored_source then
        return true
    end
    local ok, done = pcall(authored_source.close)
    return ok and done ~= false
end
editor.on_disable = function(...)
    -- Dismiss owned UI before waiting for native retirement. A failed fence
    -- must retain resource receipts without trapping the editor/cursor.
    local dismissed = dismiss_frontend()
    local stopped = close_authored_source()
    local retired = close()
    if not dismissed or not stopped or not retired then
        return false
    end
    if package.loaded['epic.player_preview.v1'] == public then
        package.loaded['epic.player_preview.v1'] = nil
    end
    reset_transients()
    if not base_enabled then
        return true
    end
    local done = disable(...)
    if done ~= false then
        base_enabled = false
        frontend_owner = nil
    end
    return done
end
editor.on_cleanup_poll = function(...)
    local dismissed = dismiss_frontend()
    local stopped = close_authored_source()
    local retired = close()
    if not dismissed or not stopped or not retired then
        return false
    end
    if package.loaded['epic.player_preview.v1'] == public then
        package.loaded['epic.player_preview.v1'] = nil
    end
    reset_transients()
    if not base_enabled then
        return true
    end
    local done = cleanup(...)
    if done ~= false then
        base_enabled = false
        frontend_owner = nil
    end
    return done
end
return editor
