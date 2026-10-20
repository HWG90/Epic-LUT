-- Lazy weapon service composition. Session/UI state stays behind explicit ports.
-- Construction never discovers gear or schedules work; each service owns its lifecycle.
local W = {}
function W.new(m, operations, host)
    local S = {}
function S.workflow()
    if not operations.weapon_workflow_service then
        operations.weapon_workflow_service = m.weapon_workflow.new(m, {
            bridge = host.bridge,
            menu = function()
                return host.menu()
            end,
            mod = function()
                return host.mod()
            end,
            outfits = function()
                return host.outfits()
            end,
            selected_preset = function()
                return host.selected_preset()
            end,
            original = function(b)
                return host.original(b.original)
            end,
            provenance = function(b, context)
                local _, refs = operations.weapon_sources().capture(b, context)
                return refs
            end,
            invalidate = host.invalidate,
            message = host.message,
            mutate = operations.weapon_mutation,
            imports = {
                palettes = function()
                    return host.imports.palettes()
                end,
                document = function(path)
                    return host.imports.document(path)
                end,
                resource = function(path, document)
                    return host.imports.resource(path, document)
                end,
                pending = function()
                    return host.imports.pending()
                end,
                indexing = function()
                    return host.imports.indexing()
                end,
            },
            prepare_imports = host.prepare_imports,
            when_sources_ready = function(callback)
                return operations.weapon_sources().when_ready(callback)
            end,
            export_pending = function(why)
                return why == m.export_provenance.PENDING or m.weapon_provenance and why == m.weapon_provenance.PENDING
            end,
            export_options = host.export_options,
            exporter = function(preset)
                return m.preset_export.new(m, host.paths(), {
                    include_patterns = function()
                        return true
                    end,
                    binding_provenance = operations.binding_export_provider(preset),
                    original_patch = operations.export_original_patch,
                    material_source = operations.export_material_source,
                    unit_layout = m.binding_unit_layout,
                    resource_id_available = operations.export_id_available,
                    weapon_patch_archive = function(entries)
                        return operations.weapon_sources().patch_archive(entries)
                    end,
                    weapon_export_batch = function(entries, serialize)
                        return operations.weapon_sources().with_export_batch(entries, serialize)
                    end,
                })
            end,
        })
    end
    return operations.weapon_workflow_service
end
function S.startup()
    if not operations.weapon_setup_service then
        operations.weapon_setup_service = m.weapon_setup.new(m, {
            bridge = host.bridge,
            sources = operations.weapon_sources,
            restore_slot = function(preset, slot)
                return operations.weapon_mutation(function()
                    return operations.weapon_workflow().plan(preset, {slots={[slot]=true}}).apply()
                end, true)
            end,
            original = function(b)
                return host.original(b.original)
            end,
            time = function()
                return host.time()
            end,
            busy = host.busy,
            apply = function(plans)
                return operations.weapon_mutation(function()
                    return host.bridge().runtime().apply_plan(plans)
                end, true)
            end,
            message = host.message,
        })
    end
    return operations.weapon_setup_service
end
function S.sources()
    if not operations.weapon_sources_service then
        operations.weapon_sources_service = assert(m.weapon_provenance, 'Weapon provenance module unavailable').new(m, {
            discovery = function()
                return host.bridge().discovery()
            end,
            groups = function()
                return host.bridge().descriptors()
            end,
            original = function(b)
                return host.original(b.original)
            end,
            paths = host.paths(),
            memory = host.memory(),
            game = host.game(),
            native = host.native(),
            lua_engine = function()
                return rawget(_G, 'stingray')
            end,
            log = host.log,
        })
    end
    return operations.weapon_sources_service
end
function S.sharing()
    if not operations.weapon_sharing_service then
        local editor = host.bridge()
        operations.weapon_sharing_service = m.weapon_shared.new({
            runtime = editor.runtime(),
            discovery = editor.discovery(),
            weapon_mapping = m.weapon_mapping,
            remote_snapshot = editor.remote_snapshot,
            remote_authorized = host.remote_authorized,
            original = function(object)
                return host.original(object)
            end,
            binding_session = m.binding_session,
            retain = host.retain,
            cohort = operations.texture_cohort,
            create_texture = function(w, h, data)
                return host.create_texture(w, h, data)
            end,
            bind = function(b, object)
                host.bind(b, object)
            end,
        })
    end
    return operations.weapon_sharing_service
end
    return S
end
return W
