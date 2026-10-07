local ffi=require('ffi')
local core=dofile('vendor/menu/core.lua');local api=core.new({load=function()return {}end,save=function()return true end})
local d={width=23,height=8,data=ffi.new('float[?]',23*8*4)}
for r=0,7 do for c=0,22 do local i=(r*23+c)*4;d.data[i],d.data[i+1],d.data[i+2],d.data[i+3]=(r+c)%5/4,c%7/6,r%3/2,.75 end end
local m={semantics=dofile('src/semantics.lua'),palette=dofile('src/palette.lua'),dds=dofile('src/dds.lua'),ui_core=core,windows=dofile('src/windows.lua')}
local editor=dofile('src/lut_editor.lua').new(m,function()return d end,function(s)return s end,function()return true end,'tests/tmp/presets')
local pages=editor.pages()
table.insert(pages,1,{id='import',name='Import / Apply',require_confirmation=false,controls={
    {id='target_helmet',type='toggle',label='Helmet',default=true},
    {id='target_armor',type='toggle',label='Armor',default=true},
    {id='save_palette',type='button',label='Save LUT to Palette',on_activate=function()end},
    {id='apply_checked',type='button',label='Apply LUT',on_activate=function()end},
    {id='browse',type='button',label='Choose file',on_activate=function()end},
    {id='refresh',type='button',label='Refresh',on_activate=function()end},
    {id='lut',type='choice',label='Target',default=1,choices={'Armor LUT 1','Helmet LUT 2'}},
    {id='palette',type='choice',label='Palette',default=1,choices={'Imported palette 1','Imported palette 2'}},
    {id='scope',type='choice',label='Scope',default=4,choices={'Selected LUT','All Armor LUTs','Helmet LUTs','All Armor + Helmet LUTs'}},
    {id='apply_armor',type='button',label='Apply Armor',on_activate=function()end},
    {id='apply_helmet',type='button',label='Apply Helmet',on_activate=function()end},
    {id='remove_lut',type='button',label='Remove LUT',on_activate=function()end},
    {id='reset_custom',type='button',label='Reset Custom LUT',on_activate=function()end},
    {id='save_setup',type='button',label='Save applied setup',on_activate=function()end},
    {id='apply',type='button',label='Apply',on_activate=function()end},
    {id='restore',type='button',label='Restore',on_activate=function()end}}})
local h=api.register({id='palette_test',name='Epic LUT',pages=pages});editor.attach(api,h)
api.mods.palette_test.tabs_top=true
local alpha=d.data[3];local other=d.data[4]
assert(h.set('cell_color','#FF0080'));assert(d.data[0]==1 and d.data[1]==0 and math.abs(d.data[2]-128/255)<1e-6 and d.data[3]==alpha and d.data[4]==other)
assert(h.activate('undo'));assert(d.data[0]==0 and d.data[3]==alpha)
assert(h.activate('redo'));assert(d.data[0]==1)
assert(h.set('advanced_row',3));assert(h.get('edit_row')==3)
assert(h.set('edit_column',22));assert(h.set('unlock',true));assert(h.set('cell_a',4));assert(d.data[((3-1)*23+21)*4+3]==4)
assert(h.activate('copy_row'));assert(h.set('edit_row',4));assert(h.activate('paste_row'))
assert(ffi.string(d.data+2*23*4,23*16)==ffi.string(d.data+3*23*4,23*16))
local before=d.data[2*23*4];assert(h.activate('undo'));assert(d.data[3*23*4]~=before)
assert(h.activate('save_row'));assert(h.set('edit_row',5));assert(h.activate('load_row'))
assert(ffi.string(d.data+3*23*4,23*16)==ffi.string(d.data+4*23*4,23*16))
assert(h.set('row_preset','new-test-row'));assert(h.activate('save_row'))
local choices=api.mods.palette_test.controls.row_preset_select.choices;local selected
for i,name in ipairs(choices)do if name=='new-test-row'then selected=i end end
assert(selected,'New row preset did not appear in the dropdown')
assert(h.set('row_preset','different-name'));assert(h.set('row_preset_select',1));assert(h.set('row_preset_select',selected))
assert(h.get('row_preset')=='new-test-row','Dropdown selection did not fill the editable preset name')
local commands,hits={},{}
local function command(t)commands[#commands+1]=t end
local ui={x=0,y=0,w=1300,h=800,
    rect=function(x,y,w,h,c)command({type='rect',x=x,y=y,w=w,h=h,c=c})end,
    text=function(x,y,text,size,c)command({type='text',x=x,y=y,text=text,size=size,c=c})end,
    bounded=function(x,y,text,size,c,w)command({type='text',x=x,y=y,text=text,size=size,c=c})end,
    hit=function(x,y,w,h,fn)hits[#hits+1]={x=x,y=y,w=w,h=h,click=fn}end,activate=function()end}
editor.layout(ui)
local cells={};for _,hit in ipairs(hits)do if hit.w==hit.h and hit.w<40 then cells[#cells+1]=hit end end
assert(#cells==8*23,'Pixel grid did not expose every cell')
cells[23*2+7].click();assert(h.get('edit_row')==3 and h.get('edit_column')==7 and h.get('color_field')==4)
assert(h.set('scratch_color','#123456'));assert(h.set('grid_tool',2));cells[1].click()
assert(math.abs(d.data[0]-0x12/255)<1e-6 and d.data[3]==alpha,'Draw changed an unselected alpha channel')
assert(h.set('grid_tool',1));cells[1].click();ui.shift=function()return true end;cells[25].click();ui.shift=nil
assert(editor.selection.r2==2 and editor.selection.c2==2)
assert(h.activate('copy_selection'));assert(editor.clip.width==2 and editor.clip.height==2)
assert(h.set('grid_tool',3));cells[4*23+3].click()
assert(d.data[0]==0 and math.abs(d.data[(4*23+2)*4]-0x12/255)<1e-6,'Move did not preserve copied pixels')
assert(h.activate('undo'));assert(math.abs(d.data[0]-0x12/255)<1e-6,'Move was not one undoable operation')
assert(h.set('grid_tool',1));cells[23*2+1].click();editor.value_scroll=0;editor.focus_column=nil
commands,hits={},{};editor.layout(ui)
local menu=dofile('vendor/menu/menu.lua').new(api,function(text,size)return #text*size*.5 end)
menu.visible=true;menu.selected=1;menu.page=2;menu.window_width=1800;menu.window_height=1000
menu.compact_fonts=true
local rendered=menu.compose(1920,1080);local grid=false;local saved=false
for _,c in ipairs(rendered)do
    if c.text=='Pixel Grid'then grid=true;assert(c.x<menu.window_bounds.x+50,'Sidebar still consumes editor width')end
    if c.full_text=='Save applied setup'then saved=true end
    assert(c.text~='MODS','Tabbed editor still shows a left mod selector')
end
assert(grid,'Actual menu controller did not render the custom LUT workspace')
assert(saved,'Custom renderer failed before drawing its action controls')
local function tap(x,y)
    menu.tick({down=function(k)return k==1 end,mouse=function()return x,y end,wheel=function()return 0 end})
    menu.tick({down=function()return false end,mouse=function()return x,y end,wheel=function()return 0 end})
end
-- A typed value must use its own field context, not a stale grid selection.
local numeric
for _,c in ipairs(rendered)do if c.full_text=='0.5'and c.x>menu.window_bounds.x+1200 then numeric=c;break end end
assert(numeric,'Typed float box was not rendered');tap(numeric.x+10,numeric.y+2)
assert(menu.text_edit and menu.text_edit.control.type=='slider','Float value did not open typed editing')
local typed_row,typed_column=h.get('edit_row'),h.get('edit_column')
menu.text_edit.text='0.125';menu.key(13)
assert(d.data[((typed_row-1)*23+typed_column-1)*4]==.125,'Typed float affected the wrong cell');assert(h.activate('undo'))
local slider_x,slider_y=numeric.x-180,numeric.y+2
menu.tick({down=function(k)return k==1 end,mouse=function()return slider_x,slider_y end,wheel=function()return 0 end})
menu.tick({down=function(k)return k==1 end,mouse=function()return slider_x+40,slider_y end,wheel=function()return 0 end})
menu.tick({down=function()return false end,mouse=function()return slider_x+40,slider_y end,wheel=function()return 0 end})
assert(menu.visible,'Shader slider drag closed the menu');assert(h.activate('undo'))
for _,c in ipairs(rendered)do if c.type=='text'then assert(c.size<=14,'Compact editor font exceeded its cap')end end
local initial_scroll=editor.value_scroll;local vb=editor.value_bounds;local wb=menu.window_bounds
menu.wheel(-120,wb.x+(vb.x+10)*wb.scale,wb.y+(vb.y+20)*wb.scale)
assert(editor.value_scroll>initial_scroll,'Value editor did not scroll independently')
menu.wheel(120,wb.x+(vb.x+10)*wb.scale,wb.y+(vb.y+20)*wb.scale)
local combo
for _,c in ipairs(rendered)do if c.full_text=='Armor LUT 1'then combo=c;break end end
assert(combo,'Scope combo was not rendered');tap(combo.x+20,combo.y+2)
assert(menu.dropdown and menu.dropdown.control.id=='lut','Combo center did not open its dropdown')
menu.key(40);menu.key(13);assert(h.get('lut')==2,'Dropdown selection was not applied')
-- Tabs are real click targets and the rail remains absent.
local target_tab
for _,c in ipairs(menu.compose(1920,1080))do if c.full_text=='Material / camo'then target_tab=c;break end end
assert(target_tab);tap(target_tab.x+20,target_tab.y+2);assert(menu.page==3,'Top tab did not navigate to material editing')
menu.page=2;editor.value_scroll=0;rendered=menu.compose(1920,1080)
commands=rendered
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local f=assert(io.open('dist/lut-editor-layout-preview.svg','wb'));f:write('<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080"><rect width="1920" height="1080" fill="#101114"/>')
for _,c in ipairs(commands)do local color=string.format('#%02X%02X%02X',c.c[1],c.c[2],c.c[3])
    if c.type=='rect'then f:write(string.format('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',c.x,1080-c.y-c.h,c.w,c.h,color))
    else f:write(string.format('<text x="%.2f" y="%.2f" font-family="Segoe UI, sans-serif" font-size="%.2f" fill="%s">%s</text>',c.x,1080-c.y,c.size,color,esc(c.text)))end
end
f:write('</svg>');f:close()
print('PASS palette editor: exact RGB/alpha isolation, float/camo edits, shared row navigation, undo/redo, row copy/paste, 184 selectable grid cells and source-derived layout preview')
