-- Shared OS/config bootstrap. This owns no engine objects or game callbacks.
local R = {}
local active = setmetatable({}, { __mode = 'k' })
local function selected(ctx_value, model_value, label)
    assert(ctx_value == nil or type(ctx_value) == 'table', 'Invalid context ' .. label .. ' service')
    assert(model_value == nil or type(model_value) == 'table', 'Invalid model ' .. label .. ' service')
    assert(ctx_value == nil or model_value == nil or ctx_value == model_value,
        'Conflicting Epic LUT ' .. label .. ' services')
    return ctx_value or model_value
end
function R.start(model, ctx)
    assert(type(model) == 'table' and type(ctx) == 'table', 'Epic LUT runtime model/context required')
    assert(active[model] == nil, 'Epic LUT runtime services are already active; finish cleanup first')
    local previous = {
        { model, 'platform', rawget(model, 'platform') }, { ctx, 'platform', rawget(ctx, 'platform') },
        { model, 'storage', rawget(model, 'storage') }, { ctx, 'storage', rawget(ctx, 'storage') },
    }
    local platform = selected(previous[2][3], previous[1][3], 'platform')
    local storage = selected(previous[4][3], previous[3][3], 'storage')
    if storage then
        assert(type(storage.load) == 'function' and type(storage.save) == 'function', 'Invalid supplied settings service')
    end
    local owned_platform, owned_storage, published, closed = false, false, false, false
    local lease = { ready = false, platform = platform, storage = storage, owned_platform = false, owned_storage = false }
    active[model] = lease
    local function publish()
        rawset(model, 'platform', platform);rawset(ctx, 'platform', platform)
        rawset(model, 'storage', storage);rawset(ctx, 'storage', storage)
        lease.platform, lease.storage = platform, storage
        lease.owned_platform, lease.owned_storage = owned_platform, owned_storage
        published = true
    end
    local function close_platform()
        if not owned_platform then return true end
        if type(platform) ~= 'table' or type(platform.close) ~= 'function' then
            return false, 'Created platform service has no cleanup operation'
        end
        local called, done, why = pcall(platform.close)
        if not called then return false, tostring(done) end
        if done ~= true then return false, why or 'Epic LUT platform cleanup is pending' end
        return true
    end
    function lease.close(cleanup_ready)
        if closed then return true end
        if cleanup_ready ~= true then return false, 'Epic LUT consumer cleanup is still pending' end
        local done, why = close_platform()
        if not done then return false, why end
        if published then
            for _, field in ipairs(previous) do
                local value
                if field[2] == 'platform' then value = platform else value = storage end
                if rawget(field[1], field[2]) == value then rawset(field[1], field[2], field[3]) end
            end
        end
        if active[model] == lease then active[model] = nil end
        closed, lease.closed, lease.ready = true, true, false
        return true
    end
    local ok, why = pcall(function()
        if not platform and model.native_platform_name ~= nil then
            local name, directory = model.native_platform_name, ctx.dir
            assert(type(name) == 'string' and #name > 0 and #name <= 240
                and name:match('^[%w_.-]+%.dll$'), 'Explicit packaged platform DLL filename required')
            assert(type(directory) == 'string' and #directory > 0 and not directory:find('%z'),
                'Platform package directory required')
            local provider = assert(model.native_platform, 'Native platform module unavailable')
            assert(type(provider.new) == 'function', 'Native platform constructor unavailable')
            local tail = directory:sub(-1)
            platform = provider.new({ library = directory .. ((tail == '/' or tail == '\\') and '' or '/') .. name })
            owned_platform = true
            assert(type(platform) == 'table' and type(platform.close) == 'function', 'Invalid created platform service')
        end
        local host = ctx
        if ctx.config == nil and ctx.set == nil and model.loader_host ~= nil
            and (platform ~= nil or model.use_loader_storage == true) then
            assert(type(model.loader_host) == 'table', 'Explicit public loader host required')
            host = model.loader_host
            assert(type(host.config) == 'table' and type(host.set) == 'function', 'Public loader settings context required')
        end
        if not storage and (host.config ~= nil or host.set ~= nil) then
            assert(type(host.config) == 'table' and type(host.set) == 'function', 'Public loader settings context required')
            local provider = assert(model.loader_store, 'Loader settings module unavailable')
            assert(type(provider.new) == 'function', 'Loader settings constructor unavailable')
            storage = provider.new(host)
            owned_storage = true
            assert(type(storage) == 'table' and type(storage.load) == 'function' and type(storage.save) == 'function',
                'Invalid created settings service')
        end
    end)
    if not ok then
        local done, cleanup_error = close_platform()
        if done then
            active[model] = nil
            error(why, 0)
        end
        -- Return the retained lease before the caller raises the constructor
        -- error. Its ordinary cleanup path can then retry the exact owner.
        publish()
        lease.error = tostring(why) .. '; runtime cleanup pending: ' .. tostring(cleanup_error)
        return lease, lease.error
    end
    publish()
    lease.ready = true
    return lease
end
return R
