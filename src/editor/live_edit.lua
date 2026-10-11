-- Coalesce transient editor revisions without owning documents, history or
-- native buffers. Callers upload their latest revision only when ready is true.
local L = { INTERVAL = 1 / 15 }
function L.new()
    local elapsed, was_active = L.INTERVAL, false
    local self = {}
    function self.reset()
        elapsed, was_active = L.INTERVAL, false
    end
    function self.ready(dirty, active, dt)
        active = not not active
        if not active then
            elapsed, was_active = L.INTERVAL, false
            return not not dirty
        end
        if not was_active then
            elapsed = L.INTERVAL
        end
        was_active = true
        if type(dt) == 'number' and dt == dt and dt > 0 and dt < math.huge then
            elapsed = math.min(L.INTERVAL, elapsed + math.min(dt, L.INTERVAL))
        end
        if dirty and elapsed + 1e-9 >= L.INTERVAL then
            elapsed = 0
            return true
        end
        return false
    end
    return self
end
return L
