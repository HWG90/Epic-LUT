-- Production view/font paths in stock Lua 5.1. The public Gui.text,
-- Gui.text_extents and owned screen-GUI operations are present in the retained
-- build25988413 startup inventory and used by LLL's Steam manager.
-- Explicit GUI fixtures prove control flow; they do not claim visual acceptance.
local View = dofile('vendor/menu/view.lua')
local Font = dofile('src/platform/ui_font.lua')
local font = 'core/performance_hud/debug'
local state = { width=1920, height=1080, world={}, allocations=0, extents=0, destroys=0, serial=0 }
local guis, items, texts = {}, {}, {}
local function live(gui)
    assert(guis[gui] == state.world and not gui.destroyed, 'GUI operation escaped an owned live world')
end
local function advance(label, size)
    local result = 0
    for glyph in label:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        result = result + (glyph == 'i' and 0.2 or glyph == 'M' and 0.8 or glyph == ' ' and 0.3 or 0.5) * size
    end
    return result
end
local function allocate(gui, kind)
    live(gui)
    state.serial, state.allocations = state.serial + 1, state.allocations + 1
    local id = state.serial
    items[id] = { gui=gui, kind=kind }
    return id
end
local function destroy(gui, id, kind)
    live(gui)
    assert(items[id] and items[id].gui == gui and items[id].kind == kind, 'Released a foreign/stale GUI primitive')
    items[id] = nil
    state.destroys = state.destroys + 1
end
-- Intentionally no IdString64, Material, process memory or font-resource loader.
local sr = {
    Application = {
        main_world=function() return state.world end,
        worlds=function() return { state.world } end,
    },
    World = {
        create_screen_gui=function(world, mode, x, y)
            assert(world == state.world and mode == 'scale' and x == 1 and y == 1)
            local gui = {}
            guis[gui] = world
            return gui
        end,
        destroy_gui=function(world, gui)
            live(gui); assert(world == state.world)
            for _, item in pairs(items) do assert(item.gui ~= gui, 'GUI destroyed before its owned text/rects') end
            gui.destroyed = true
            state.destroys = state.destroys + 1
        end,
    },
    Vector2=function(x,y) return {x=x,y=y} end,
    Vector3=function(x,y,z) return {x=x,y=y,z=z} end,
    Color=function(a,r,g,b) return {a=a,r=r,g=g,b=b} end,
    Gui = {
        resolution=function() return state.width,state.height end,
        rect=function(gui, position, size, color)
            assert(position.z % 1 == 0 and size.x > 0 and size.y > 0 and color.a >= 0)
            return allocate(gui,'rect')
        end,
        text=function(gui, label, face, size, material, position, color)
            assert(face == font and material == font and size > 0, 'Portable text used an unverified HUD resource')
            assert(position.z % 1 == 0 and color.a >= 0)
            texts[#texts + 1] = { gui=gui, label=label, face=face, material=material, size=size, position=position }
            return allocate(gui,'text')
        end,
        text_extents=function(gui, label, face, size)
            live(gui); assert(face == font and size > 0)
            state.extents = state.extents + 1
            -- Constant terminal bearings cancel in the production advance query.
            return {x=0.03*size,y=-0.2*size}, {x=0.03*size+advance(label,size)-0.08*size,y=0.75*size}
        end,
        destroy_text=function(gui,id) destroy(gui,id,'text') end,
        destroy_rect=function(gui,id) destroy(gui,id,'rect') end,
    },
}
local view = View.new(sr)
view.set_font_source(Font.new(nil,nil))
assert(not view.refresh_font() and view.font_key == font, 'Missing native font source did not retain stock face')
assert(view.measure('',16)==0 and view.measure('MM',0)==0)
local commands = {
    {type='rect',x=5,y=10,w=200,h=70,a=0.5,c={20,30,40}},
    {type='text',text='Mié',x=20,y=30,size=16,a=1,c={255,255,255},bold=true},
    {type='text',text='Popup',x=50,y=60,size=20,a=1,c={255,255,0},popup=true},
    {type='text',text='Preview',x=80,y=90,size=24,a=1,c={0,255,255},hud_preview=true},
}
view.draw(commands)
assert(#texts == 4, 'Stock text/bold/popup/preview surfaces were not drawn')
local main
for _, text in ipairs(texts) do if text.label=='Mié' and text.position.x==20 then main=text end end
assert(main and main.position.y==30 and main.size==16, 'GUI coordinates or font size changed')
assert(view.refresh_font(), 'Initial owned GUI did not invalidate cold font metrics')
assert(math.abs(view.measure('Mié',16)-24)<1e-8, 'Public native glyph advances were not used')
local metrics = view.text_metrics(20,'Ag0#')
assert(metrics.min_y==-4 and metrics.max_y==15 and metrics.height==19 and metrics.optical_y==0,
    'Portable debug font bearings used custom HUD corrections')
local allocations, extents = state.allocations, state.extents
local key = view.metric_key
for _=1,1000 do
    assert(not view.refresh_font())
    view.draw(commands)
    assert(math.abs(view.measure('Mié',16)-24)<1e-8 and view.text_metrics(20,'Ag0#')==metrics)
end
assert(state.allocations==allocations and state.extents==extents and view.metric_key==key,
    'Unchanged view recreated text or remeasured cached font geometry')
view.suspended=true
assert(view.draw(commands)==false and view.release()==false and state.destroys==0,
    'Suspended UI performed GUI retirement')
view.suspended=false; state.width=0
assert(view.draw(commands)==false and view.release()==false and state.destroys==0,
    'Invalid display dimensions performed GUI operations')
state.width=1920
assert(view.release())
for _, item in pairs(items) do assert(false,'Owned GUI primitive survived acknowledged release') end
local destroyed = state.destroys
assert(view.release() and state.destroys==destroyed, 'Repeated close destroyed another owner')
texts={}; view.draw(commands); view.refresh_font()
assert(#texts==4 and math.abs(view.measure('Mié',16)-24)<1e-8, 'Closed portable font view did not reopen')
local prior_world = state.world
state.world = {}
local before_transition = state.destroys
view.draw(commands); view.refresh_font()
assert(state.destroys==before_transition, 'World replacement tried to destroy resources in a dead world')
assert(math.abs(view.measure('Mié',16)-24)<1e-8, 'World replacement retained dead GUI font metrics')
for _, text in ipairs(texts) do
    if guis[text.gui] == state.world then assert(not text.gui.destroyed) end
end
assert(view.release())
assert(prior_world ~= state.world and view.font_key==font)
print('PASS portable font/view: public stock text and extents, exact coordinates, metric cache, owned GUI release, suspend/reopen and world replacement')
