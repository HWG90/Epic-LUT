-- Owned character preview lifecycle. An adapter may lease an initialized world;
-- its destroy_world must release only the lease, never a game-owned world.
-- Models, cameras, viewports, GUI and targets must always be independent.
local Preview = {}
function Preview.new(adapter)
    local self = { state = 'closed', error = nil, resources = {}, revision = nil }
    local function acquire(name, create, destroy, ...)
        local value = assert(create(...), 'Preview did not create ' .. name)
        self.resources[#self.resources + 1] = { name = name, value = value, destroy = destroy }
        return value
    end
    function self.close()
        if #self.resources > 0 and adapter.quiesce then
            self.state = 'closing'
            local ok, done = pcall(adapter.quiesce)
            if not ok then
                self.error = tostring(done)
                return false
            end
            if not done then
                return false
            end
        end
        local failed = {}
        for i = #self.resources, 1, -1 do
            local resource = self.resources[i]
            local ok, err = pcall(resource.destroy, resource.value)
            if not ok then
                -- Keep prerequisites alive if a dependent resource could not die.
                for j = 1, i do
                    failed[j] = self.resources[j]
                end
                self.error = tostring(err)
                break
            end
        end
        -- Retain failed cleanup receipts for a later retry; do not spawn again.
        self.resources = failed
        self.state = #failed == 0 and 'closed' or 'cleanup_failed'
        self.model = nil
        self.world = nil
        self.camera = nil
        self.viewport = nil
        self.target = nil
        self.revision = nil
        return #failed == 0
    end
    function self.open(gear)
        if not self.close() then
            return false, self.error
        end
        self.error = nil
        self.state = 'preparing'
        local ok, err = pcall(function()
            assert(gear and gear.body and gear.armor and gear.helmet, 'Equipped gear is incomplete')
            -- The portrait is referenced by the world/viewport/GUI. Acquire it
            -- first so reverse cleanup keeps it alive until they are gone.
            self.target = acquire('target', adapter.create_target, adapter.destroy_target)
            self.world = acquire('world', adapter.create_world, adapter.destroy_world)
            -- The assembly adapter owns attachments, animations and their teardown.
            self.model = acquire('model', adapter.create_model, adapter.destroy_model, self.world, gear)
            self.camera = acquire('camera', adapter.create_camera, adapter.destroy_camera, self.world, self.model)
            self.viewport =
                acquire('viewport', adapter.create_viewport, adapter.destroy_viewport, self.world, self.target)
            acquire('panel', adapter.create_panel, adapter.destroy_panel, self.target)
        end)
        if not ok then
            self.error = tostring(err)
            self.close()
            return false, self.error
        end
        self.state = 'ready'
        return true
    end
    function self.sync(document, revision)
        if self.state ~= 'ready' then
            return false
        end
        if revision == self.revision then
            return true
        end
        local ok, err = pcall(adapter.apply_luts, self.model, document)
        if not ok then
            self.error = tostring(err)
            self.close()
            return false, self.error
        end
        self.revision = revision
        return true
    end
    -- Called only by the loader's render callback, never its update callback.
    function self.render()
        if self.state ~= 'ready' then
            return false
        end
        local ok, err = pcall(adapter.render, self.world, self.camera, self.viewport)
        -- Native rendering can enqueue work before raising. Destruction must be
        -- requested here and performed by the next update/cleanup callback.
        if not ok then
            self.error = tostring(err)
            self.state = 'closing'
            return false, self.error
        end
        return true
    end
    return self
end
return Preview
