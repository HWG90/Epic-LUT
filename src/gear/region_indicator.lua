-- Temporary live bindings only; editor pixels and preset state remain untouched.
local R = {}
function R.new(deps)
    local ffi = require('ffi')
    local self = {}
    function self.stop()
        local job = self.job
        if not job then
            return true
        end
        local remaining = {}
        for _, item in ipairs(job.items) do
            local b = item.binding
            if deps.present(b) and (deps.binding(b) == item.highlight or deps.binding(b) == item.object) then
                local ok = pcall(function()
                    deps.bind(b, item.object)
                    assert(deps.binding(b) == item.object)
                end)
                if not ok then
                    remaining[#remaining + 1] = item
                else
                    b.current = item.object
                    b.texture = item.texture
                    b.document = item.document
                end
            end
        end
        job.items = remaining
        self.job = #remaining > 0 and job or nil
        return self.job == nil
    end
    function self.start(items, row)
        assert(self.stop(), 'Previous highlight restoration pending')
        assert(#items > 0, 'No live target for this region')
        self.job = { items = items, remaining = 4, elapsed = 0, on = true }
        local ok, why = pcall(function()
            for _, item in ipairs(items) do
                local source = item.source
                assert(row >= 1 and row <= source.height, 'Selected region does not exist on this target')
                local data = ffi.new('float[?]', source.width * source.height * 4)
                ffi.copy(data, source.data, source.width * source.height * 16)
                local at = (row - 1) * source.width * 4
                data[at] = 1
                data[at + 1] = 0
                data[at + 2] = 1
                local _, texture = deps.apply(
                    { data = data, width = source.width, height = source.height },
                    { item.binding }
                )
                item.highlight = texture.object
            end
        end)
        if not ok then
            self.stop()
            error(why, 0)
        end
    end
    function self.tick(dt, visible)
        local job = self.job
        if not job then
            return
        end
        local delta = math.max(0, tonumber(dt) or 0)
        job.remaining = job.remaining - delta
        job.elapsed = job.elapsed + delta
        if job.remaining <= 0 or not visible then
            self.stop()
            return
        end
        local on = math.floor(job.elapsed * 4) % 2 == 0
        if on == job.on then
            return
        end
        local ok = pcall(function()
            for _, item in ipairs(job.items) do
                local b = item.binding
                local expected = job.on and item.highlight or item.object
                if deps.present(b) and deps.binding(b) == expected then
                    local object = on and item.highlight or item.object
                    deps.bind(b, object)
                    assert(deps.binding(b) == object)
                    b.current = object
                end
            end
        end)
        job.on = on
        if not ok then
            self.stop()
        end
    end
    return self
end
return R
