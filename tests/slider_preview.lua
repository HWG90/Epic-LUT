local api=dofile('vendor/menu/core.lua').new({load=function() return {} end,save=function() return true end})
local changes=0
local h=api.register({id='slider_test',name='Slider',pages={{id='p',name='Page',require_confirmation=false,controls={
    {id='value',type='slider',label='Value',min=0,max=1,step=.01,default=.2,on_change=function() changes=changes+1 end},
}}}})
api.mods[h.id].pages[1].render_layout=function(ui) ui.number('value',ui.x+10,ui.y+100,400,h.get('value'),function() end,true,0,1) end
local menu=dofile('vendor/menu/menu.lua').new(api,function(text,size) return #text*size*.5 end)
menu.visible=true
local function input(x,y,down) menu.tick({down=function(k) return down and k==1 end,mouse=function() return x,y end,wheel=function() return 0 end}) end
local bar
for _,c in ipairs(menu.compose(1920,1080)) do if c.type=='rect' and c.c[1]==49 and c.c[2]==111 then bar=c end end
assert(bar)
local x,y=bar.x+(bar.w/.2)*.8,bar.y+5
input(x,y,true)
local displayed=false
for _,c in ipairs(menu.compose(1920,1080)) do if c.full_text=='0.8' or c.text=='0.8' then displayed=true end end
assert(displayed and math.abs(h.get('value')-.8)<1e-9 and changes==1,'Slider did not update live while held')
input(x,y,false)
assert(math.abs(h.get('value')-.8)<1e-9 and changes==1,'Release duplicated the live update')
print('PASS slider preview: live numeric/bar display and live commit without duplicate release')
