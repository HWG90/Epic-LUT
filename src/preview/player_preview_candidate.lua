-- Preview lifecycle adapter shared by integrated builds and the standalone test sidecar.
local enable, update, disable, cleanup = editor.on_enable, editor.on_update, editor.on_disable, editor.on_cleanup_poll
local controller, adapter, memory, game, log
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
local retry_at = 0
local recovery_attempts = 0
local controls = m.player_preview_controls.new()
local source_signature
local source_elapsed = 0
local recovery_elapsed = 0
local function signature(identity)
    local parts = { identity.unit, identity.body, identity.armor, identity.helmet }
    for _, piece in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
        parts[#parts + 1] = piece.unit
    end
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    return table.concat(parts, ':')
end
local public = {}
local dock_request
local dock_age = 1
local docked = false
local floating_geometry
local dock_hidden = false
local floating_on_editor = false
local input_bridge
local function release_input()
    if input_bridge then
        input_bridge.release()
    end
end
local state_path = (os.getenv('LOCALAPPDATA') or '') .. '/Epic LUT/cache/player-preview-state.txt'
local function write_state(detail)
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
local function close()
    release_input()
    unhook()
    due = false
    local done = not controller or controller.close()
    write_state(not done and controller and controller.error or '')
    return done
end
local function open()
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
    first = true
    wrapper = function(...)
        forward(...)
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
editor.on_enable = function(ctx)
    enable(ctx)
    log = ctx.log
    memory = m.bingus_memory.new(m.bingus_runtime)
    game = memory.address(assert(memory.module('game.dll')))
    local native = assert(m.engine.open(memory, game, memory.address(assert(memory.module()))))
    local submit = m.player_preview_submit.new(memory, game, memory.address(assert(memory.module())))
    log('preview: native submission signatures verified')
    adapter = m.player_preview_native.new(stingray, m, {
        memory = memory,
        native = native,
        log = log,
        submit = submit,
        game = game,
        use_ui_world = true,
        controls = controls,
    })
    controller = m.player_preview.new(adapter)
    public.before_editor_close = function()
        recovering = false
        dock_hidden = false
        return close()
    end
    public.toggle = function()
        recovering = false
        recovery_attempts = 0
        if dock_request and dock_age < 0.2 then
            floating_on_editor = not floating_on_editor
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
    public.is_docked = function()
        return docked and not dock_hidden and not floating_on_editor and controller.state == 'ready'
    end
    public.dock = function(bounds)
        local front = package.loaded['dbf.epic_lut.frontend.v1']
        local window = front and front.menu.window_bounds
        if not window then
            return
        end
        local s = window.scale
        dock_request = { x = window.x + bounds.x * s, y = window.y + bounds.y * s, w = bounds.w * s, h = bounds.h * s }
        dock_age = 0
    end
    public.material_masks = function()
        if controller.state ~= 'ready' or not controller.model then
            return {}
        end
        return adapter.material_masks(controller.model)
    end
    public.set_material_mask = function(pi, ai, slot, mode)
        if controller.state ~= 'ready' or not controller.model then
            return
        end
        adapter.set_material_mask(controller.model, pi, ai, slot, mode)
        due = true
    end
    public.reset_material_masks = function()
        if controller.state ~= 'ready' or not controller.model then
            return
        end
        adapter.reset_material_masks(controller.model)
        due = true
    end
    public.meshes = function()
        if controller.state ~= 'ready' or not controller.model then
            return {}
        end
        return adapter.meshes(controller.model)
    end
    public.set_mesh = function(pi, mi, visible)
        if controller.state ~= 'ready' or not controller.model then
            return
        end
        adapter.set_mesh(controller.model, pi, mi, visible)
        due = true
    end
    public.reset_meshes = function()
        if controller.state ~= 'ready' or not controller.model then
            return
        end
        adapter.reset_meshes(controller.model)
        due = true
    end
    package.loaded['epic.player_preview.v1'] = public
    write_state(PREVIEW_INSPECT_ONLY and 'inspection only' or 'ready to open')
    ctx.on_cleanup(close)
    log(
        PREVIEW_INSPECT_ONLY and 'preview: read-only model inspector ready'
            or 'preview: independent player portrait candidate ready'
    )
end
editor.on_update = function(ctx, dt)
    update(ctx, dt)
    dock_age = dock_age + (dt or 0)
    local front = package.loaded['dbf.epic_lut.frontend.v1']
    if front and not front.menu.visible then
        recovering = false
    end
    if front and not front.menu.visible and controller.state == 'ready' then
        recovering = false
        dock_hidden = false
        close()
        log('preview: closed with editor before game UI transition')
    end
    local editor_page = dock_request and dock_age < 0.2 and front and front.menu.visible
    local wants_dock = editor_page and not floating_on_editor
    controls.can_dock = editor_page
    if wants_dock then
        if not docked then
            floating_geometry = { controls.x, controls.y, controls.w, controls.h }
            docked = true
            controls.docked = true
            controls.cancel()
        end
        local b = dock_request
        local changed = controls.x ~= b.x or controls.y ~= b.y or controls.w ~= b.w or controls.h ~= b.h
        controls.x, controls.y, controls.w, controls.h = b.x, b.y, b.w, b.h
        if controller.state == 'closed' and not dock_hidden and not recovering then
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
    local request
    request_elapsed = request_elapsed + (dt or 0)
    if request_elapsed >= 0.25 then
        request_elapsed = 0
        local file = io.open(request_path, 'rb')
        if file then
            request = file:read(16)
            file:close()
            os.remove(request_path)
        end
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
        local front = package.loaded['dbf.epic_lut.frontend.v1']
        if not front or not front.menu.visible or not front.input.focused() then
            controls.cancel()
        end
        if not input_bridge then
            input_bridge = m.player_preview_input.new({
                controls = controls,
                ready = function()
                    return controller.state == 'ready'
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
                    elseif event == 'move' or event == 'resize' then
                        adapter.layout_panel()
                    elseif event == 'rotate' or event == 'pan' then
                        adapter.rotate(controller.camera, controls.yaw, controls)
                        due = true
                    elseif event == 'zoom' then
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
editor.on_disable = function(...)
    if not close() then
        return false
    end
    if package.loaded['epic.player_preview.v1'] == public then
        package.loaded['epic.player_preview.v1'] = nil
    end
    return disable(...)
end
editor.on_cleanup_poll = function(...)
    if not close() then
        return false
    end
    return cleanup(...)
end
return editor
