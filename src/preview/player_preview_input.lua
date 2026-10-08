-- Owns only the preview's mouse/wheel wrappers. Never replaces a foreign wrapper on release.
local P = {}
function P.new(deps)
    local self = {}
    local owner, original_mouse, mouse_wrapper, original_wheel, wheel_wrapper
    function self.release()
        if owner and owner.mouse == mouse_wrapper then
            owner.mouse = original_mouse
        end
        if owner and owner.wheel == wheel_wrapper then
            owner.wheel = original_wheel
        end
        owner, original_mouse, mouse_wrapper, original_wheel, wheel_wrapper = nil, nil, nil, nil, nil
    end
    function self.attach(front)
        if not front or not front.input or owner == front.input then
            return
        end
        self.release()
        owner = front.input
        local input = owner
        original_mouse = input.mouse
        local mouse = original_mouse
        local function active()
            return deps.ready() and front.menu.visible and input.focused()
        end
        mouse_wrapper = function(...)
            local x, y = mouse(...)
            if not active() then
                deps.controls.cancel()
                return x, y
            end
            local controls = deps.controls
            local preview_dragging = controls.drag or controls.resize or controls.pan or controls.orbit
            if not preview_dragging and front.menu.owns_pointer and front.menu.owns_pointer(x,y) then
                controls.cancel()
                return x,y
            end
            local w, h = deps.resolution()
            local hit, event = deps.controls.pointer(x, y, input.down(1), w, h, input.down(2))
            local ok, why = pcall(deps.event, event)
            if not ok then
                deps.failed('panel control', why)
            end
            if hit then
                return
            end
            return x, y
        end
        input.mouse = mouse_wrapper
        original_wheel = input.wheel
        if original_wheel then
            local wheel = original_wheel
            wheel_wrapper = function(...)
                local delta = wheel(...)
                local x, y = mouse(...)
                local controls = deps.controls
                if
                    active()
                    and x
                    and y
                    and x >= controls.x
                    and x <= controls.x + controls.w
                    and y >= controls.y
                    and y <= controls.y + controls.h
                then
                    if delta ~= 0 then
                        controls.fov = math.max(12, math.min(65, controls.fov - delta / 120 * 5))
                        local ok, why = pcall(deps.zoom)
                        if not ok then
                            deps.failed('zoom', why)
                        end
                        deps.changed()
                    end
                    return 0
                end
                return delta
            end
            input.wheel = wheel_wrapper
        end
    end
    return self
end
return P
