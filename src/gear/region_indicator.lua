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
        assert(type(row) == 'number' and row % 1 == 0 and row >= 1, 'Invalid highlight region')
        -- Validate the complete target set before allocating or changing any
        -- binding. Only the material and Pattern layouts have known colors.
        for _, item in ipairs(items) do
            local source, b = item.source, item.binding
            assert(source and source.data and b, 'Highlight target pixels unavailable')
            assert(
                (
                    source.width == 23
                    and type(source.height) == 'number'
                    and source.height % 1 == 0
                    and source.height >= 1
                    and source.height <= 64
                ) or (source.width == 3 and source.height == 1),
                'Unsupported highlight table shape'
            )
            assert(row <= source.height, 'Selected region does not exist on this target')
            assert(
                item.object ~= nil and deps.present(b) and deps.binding(b) == item.object,
                'Live highlight target changed; load current colors again'
            )
        end
        self.job = {
            items = items,
            remaining = 4,
            elapsed = 0,
            on = true,
            context = deps.context and deps.context(),
        }
        local ok, why = pcall(function()
            for _, item in ipairs(items) do
                local source = item.source
                local data = ffi.new('float[?]', source.width * source.height * 4)
                ffi.copy(data, source.data, source.width * source.height * 16)
                -- Camo and bump/curvature colors can cover the primary color.
                -- Flash those documented RGB contributions too; retain every
                -- alpha, material/mask value, tint, emission and camo selector.
                local columns = source.width == 23 and { 1, 3, 6, 7, 13, 17, 18, 19, 20 } or { 1 }
                for _, column in ipairs(columns) do
                    local at = ((row - 1) * source.width + column - 1) * 4
                    data[at], data[at + 1], data[at + 2] = 1, 0, 1
                end
                local b = item.binding
                local applied, texture = pcall(function()
                    assert(
                        deps.present(b) and deps.binding(b) == item.object,
                        'Live highlight target changed; load current colors again'
                    )
                    local _, result = deps.apply({ data = data, width = source.width, height = source.height }, { b })
                    return result
                end)
                -- Binding sessions normally publish applied pixels to these
                -- fields. A flash owns only the temporary native object;
                -- reads, edits, exports and appearance snapshots must keep
                -- seeing the prior document even during its off phase.
                item.highlight = applied and texture.object or b.current
                b.texture, b.document = item.texture, item.document
                assert(applied, texture)
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
        if job.remaining <= 0 or not visible or (deps.context and deps.context() ~= job.context) then
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
