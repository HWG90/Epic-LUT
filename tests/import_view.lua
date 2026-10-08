local ffi=require('ffi');local core=dofile('vendor/menu/core.lua');local menu_factory=dofile('vendor/menu/menu.lua')
local api=core.new({load=function()return {}end,save=function()return true end})
local a,b=ffi.new('float[?]',23*8*4),ffi.new('float[?]',23*8*4)
for i=0,23*8*4-1 do a[i]=(i%7)/6;b[i]=(i%11)/10 end
local state={loaded={width=23,height=8,data=a},armor={{name='Armor LUT 1',width=23,height=8,data=a}},helmet={{name='Helmet LUT 2',width=23,height=8,data=b}},
    palette_count=2,status='Import ready',busy=true,phase='Reading archive...',time=1,elapsed=2,armor_checked=true,helmet_checked=false,palette_name='my-palette'}
local picked
local view=dofile('src/import_view.lua').new(function()return state end,dofile('src/table_groups.lua'),function(entry,row,col)picked={entry=entry,row=row,col=col}end,core)
local controls={}
for _,id in ipairs({'palette','lut','basic_armor_lut','basic_helmet_lut'})do controls[#controls+1]={id=id,type='choice',label=id,choices={'LUT 1','LUT 2'},default=1}end
for _,id in ipairs({'target_armor','target_helmet'})do controls[#controls+1]={id=id,type='toggle',label=id,default=true}end
controls[#controls+1]={id='ui_scale',type='slider',label='UI scale (%)',min=70,max=130,step=5,default=100}
controls[#controls+1]={id='quick_color',type='color',label='Quick Scratch',default='#FFFFFF'}
controls[#controls+1]={id='preserve_emissives',type='toggle',label='Preserve Original Emissives',default=false}
for _,id in ipairs({'apply_matching','global_undo','global_redo','apply_file_armor','apply_file_helmet','apply_file_both','apply_import_armor','apply_import_helmet','refresh','browse','cancel_import','retry_import','save_palette','apply_checked','restore','restore_imported','save_setup','undo','redo'})do controls[#controls+1]={id=id,type='button',label=id,on_activate=function()return true end}end
api.register({id='import_test',name='Epic LUT',pages={{id='direct',name='Import / Apply',require_confirmation=false,controls=controls}}})
api.mods.import_test.tabs_top=true;local page=api.mods.import_test.pages[1];page.render_layout=view.draw;page.on_wheel=view.wheel
local menu=menu_factory.new(api,function(t,size)return #t*size*.5 end);menu.visible=true;menu.window_width=1800;menu.window_height=1000;menu.compact_fonts=true
local first=menu.compose(1920,1080);local texts={}
for _,c in ipairs(first)do if c.text then texts[c.full_text or c.text]=c end end
assert(texts['Quick Scratch'] and texts['Quick Scratch'].x>texts['Armor LUT 1'].x,'Quick Scratch is not beside palette tables')
assert(texts['Send to LUT Editor']and texts['Apply Matching LUTs']and not texts['Apply to All Armor & Helmet LUTs']and texts['Restore Imported LUT (editor)'],'Import layout did not complete')
assert(texts['Apply LUT 1 to All Armor LUTs']and texts['Apply LUT 1 to All Helmet LUTs'],'Multi-LUT selected-source broadcast controls missing')
assert(texts.Armor and texts.Helmet and texts['Armor LUT 1']and texts['Helmet LUT 2'],'Target color previews were not grouped')
assert(texts['LUT 1'].x<texts['Choose file - DDS / ZIP / RAR...'].x,'LUT selectors are not on the left')
assert(not texts['Refresh live LUTs'],'Advanced refresh visible by default')
view.advanced=true
local advanced=false
for _,c in ipairs(menu.compose(1920,1080))do if c.full_text=='Refresh live LUTs'then advanced=true end end
assert(not advanced,'Obsolete manual refresh section remains visible')
local advanced_complete=false
for _,c in ipairs(menu.compose(1920,1080))do
    if c.text then assert(not c.text:find('nil value',1,true),'Advanced layout errored')end
    if c.full_text=='Send to LUT Editor'then advanced_complete=true end
end
assert(advanced_complete,'Advanced expansion stopped rendering the panel')
view.advanced=false
state.palette_count=1
local single=menu.compose(1920,1080)
local selectors=0;for _,c in ipairs(single)do if c.full_text=='LUT 1'then selectors=selectors+1 end end
assert(selectors==3,'Single imported LUT should show two gear selectors and one imported color strip')
state.palette_count=2
-- Floating scratch opens independently, displays ten empty slots and closes cleanly.
view.scratch_open=true
local floating=menu.compose(1920,1080);local empty_count=0;local close_button
for _,c in ipairs(floating)do
    if c.full_text and c.full_text:match('^Empty %d+$')then empty_count=empty_count+1 end
    if c.text=='X'and c.popup then close_button=c end
end
assert(empty_count==10 and close_button,'Floating scratch missing slots or close')
menu.tick({down=function(k)return k==1 end,mouse=function()return close_button.x+2,close_button.y+2 end,wheel=function()return 0 end})
menu.tick({down=function()return false end,mouse=function()return close_button.x+2,close_button.y+2 end,wheel=function()return 0 end})
assert(not view.scratch_open,'Floating scratch close did not return to table interaction')
assert(next(view.swatches)==nil,'Empty fresh-session slots unexpectedly populated')
state.time=1.13;local second=menu.compose(1920,1080);local changed=false
for i,c in ipairs(first)do local other=second[i];if c.type=='rect'and other and c.c[1]~=other.c[1]then changed=true end end
assert(changed,'Loader throbber did not animate')
state.tables={{name='Table 1',width=23,height=8,data=a}}
local dedup=menu.compose(1920,1080);local primary_rows=0;local linked=false
for _,c in ipairs(dedup)do
    if c.text=='Row 1'then primary_rows=primary_rows+1 end
    if c.full_text and c.full_text:find('shared preview',1,true)then linked=true end
end
assert(primary_rows==2 and not linked,'Armor/Helmet previews should remain visible without the imported grid')
-- Real swatch click routes exact RGB cell to the simple color picker.
local swatch
for _,c in ipairs(dedup)do if c.type=='rect'and c.w==22*menu.window_bounds.scale and c.h==16*menu.window_bounds.scale then swatch=c;break end end
assert(swatch,'Table swatches missing')
menu.tick({down=function(k)return k==1 end,mouse=function()return swatch.x+2,swatch.y+2 end,wheel=function()return 0 end})
menu.tick({down=function()return false end,mouse=function()return swatch.x+2,swatch.y+2 end,wheel=function()return 0 end})
assert(picked and picked.row==1 and picked.col==1,'Swatch selection routed wrong cell')
assert(not menu.color_picker,'Left click unexpectedly opened the color picker')
local highlights=0
for _,c in ipairs(menu.compose(1920,1080))do if c.type=='rect'and c.w==26*menu.window_bounds.scale and c.h==2*menu.window_bounds.scale and c.c[1]==244 then highlights=highlights+1 end end
assert(highlights==2,'Selection highlighted shared data in multiple sections')

-- Selecting another cell must not replace the held scratch color.
view.scratch={12,34,56};state.time=state.time+.5
menu.tick({down=function(k)return k==1 end,mouse=function()return swatch.x+2,swatch.y+2 end,wheel=function()return 0 end})
menu.tick({down=function()return false end,mouse=function()return swatch.x+2,swatch.y+2 end,wheel=function()return 0 end})
assert(view.scratch[1]==12,'Palette selection replaced scratch color')
assert(menu.color_picker and menu.color_picker.control.id=='quick_color','Double-click did not open the swatch color picker')
menu.color_picker=nil;menu.compose(1920,1080)
menu.tick({down=function(k)return k==2 end,mouse=function()return swatch.x+2,swatch.y+2 end,wheel=function()return 0 end})
menu.tick({down=function()return false end,mouse=function()return swatch.x+2,swatch.y+2 end,wheel=function()return 0 end})
assert(api.mods.import_test.handle.get('quick_color')=='#0C2238','Right click did not paint scratch color')
assert(not menu.color_picker,'Right click unexpectedly opened the color picker')
menu.color_picker=nil
state.raw={tables=state.tables,armor=state.armor,helmet=state.helmet}
view.show_all=true;assert(menu.compose(1920,1080));view.show_all=false
state.tables=nil
local function esc(t)return tostring(t):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local f=assert(io.open('dist/import-menu-preview.svg','wb'));f:write('<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="#101114"/>')
for _,c in ipairs(second)do local color=string.format('#%02X%02X%02X',c.c[1],c.c[2],c.c[3])
    if c.type=='rect'then f:write(string.format('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',c.x,1080-c.y-c.h,c.w,c.h,color))
    else f:write(string.format('<text x="%.2f" y="%.2f" font-family="Segoe UI" font-size="%.2f" fill="%s">%s</text>',c.x,1080-c.y,c.size,color,esc(c.text)))end
end
f:write('</svg>');f:close()
print('PASS friendly import view: complete two-column UI, explained left LUT selectors, independent Armor/Helmet row previews, separated editor/apply controls and animated throbber')

assert(menu_factory.key_name(45)=='Insert'and menu_factory.key_name(120)=='F9'and menu_factory.key_name(32)=='Space'and menu_factory.key_name(162)=='Left Ctrl','Readable shortcut names missing')
