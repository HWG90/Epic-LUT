local ffi=require('ffi');local core=dofile('vendor/menu/core.lua');local menu_factory=dofile('vendor/menu/menu.lua')
local api=core.new({load=function()return {}end,save=function()return true end})
local a,b=ffi.new('float[?]',23*8*4),ffi.new('float[?]',23*8*4)
for i=0,23*8*4-1 do a[i]=(i%7)/6;b[i]=(i%11)/10 end
local state={loaded={width=23,height=8,data=a},armor={{name='Armor LUT 1',width=23,height=8,data=a}},helmet={{name='Helmet LUT 2',width=23,height=8,data=b}},
    status='Import ready',busy=true,phase='Reading archive...',time=1,elapsed=2,armor_checked=true,helmet_checked=false,palette_name='my-palette'}
local view=dofile('src/import_view.lua').new(function()return state end)
local controls={}
for _,id in ipairs({'palette','lut'})do controls[#controls+1]={id=id,type='choice',label=id,choices={'LUT 1','LUT 2'},default=1}end
for _,id in ipairs({'target_armor','target_helmet'})do controls[#controls+1]={id=id,type='toggle',label=id,default=true}end
controls[#controls+1]={id='preserve_emissives',type='toggle',label='Preserve Original Emissives',default=false}
for _,id in ipairs({'refresh','browse','cancel_import','retry_import','save_palette','apply_checked','restore','restore_imported','save_setup'})do controls[#controls+1]={id=id,type='button',label=id,on_activate=function()return true end}end
api.register({id='import_test',name='Epic LUT',pages={{id='direct',name='Import / Apply',require_confirmation=false,controls=controls}}})
api.mods.import_test.tabs_top=true;local page=api.mods.import_test.pages[1];page.render_layout=view.draw;page.on_wheel=view.wheel
local menu=menu_factory.new(api,function(t,size)return #t*size*.5 end);menu.visible=true;menu.window_width=1800;menu.window_height=1000;menu.compact_fonts=true
local first=menu.compose(1920,1080);local texts={}
for _,c in ipairs(first)do if c.text then texts[c.full_text or c.text]=c end end
assert(texts['Save LUT to Palette']and texts['Apply LUT']and texts['Restore Imported LUT'],'Import layout did not complete')
assert(texts.Armor and texts.Helmet and texts['Armor LUT 1']and texts['Helmet LUT 2'],'Target color previews were not grouped')
assert(texts['LUT 1'].x<texts['Import DDS / ZIP / RAR...'].x,'LUT selectors are not on the left')
state.time=1.13;local second=menu.compose(1920,1080);local changed=false
for i,c in ipairs(first)do local other=second[i];if c.type=='rect'and other and c.c[1]~=other.c[1]then changed=true end end
assert(changed,'Loader throbber did not animate')
local function esc(t)return tostring(t):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local f=assert(io.open('dist/import-menu-preview.svg','wb'));f:write('<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="#101114"/>')
for _,c in ipairs(second)do local color=string.format('#%02X%02X%02X',c.c[1],c.c[2],c.c[3])
    if c.type=='rect'then f:write(string.format('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',c.x,1080-c.y-c.h,c.w,c.h,color))
    else f:write(string.format('<text x="%.2f" y="%.2f" font-family="Segoe UI" font-size="%.2f" fill="%s">%s</text>',c.x,1080-c.y,c.size,color,esc(c.text)))end
end
f:write('</svg>');f:close()
print('PASS friendly import view: complete two-column UI, explained left LUT selectors, independent Armor/Helmet row previews, separated editor/apply controls and animated throbber')
