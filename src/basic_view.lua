-- Primary RGB only. No shader, alpha or raw-column controls.
local B={}
function B.new(info,select_row)
    local self={scroll=0}
    function self.wheel(x,y,delta)
        local b=self.bounds
        if b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then self.scroll=math.max(0,math.min(self.maximum or 0,self.scroll-delta/120*36));return true end
    end
    function self.draw(ui)
        local state=info();local d=state.editor;local top=ui.y+ui.h
        local left=ui.w*.54;local right=ui.x+left+18;local width=ui.w-left-18
        local white,muted,blue={225,230,235},{155,166,175},{35,62,90}
        local function text(x,y,t)ui.bounded(x,y,t,14,white,ui.w-(x-ui.x)-10)end
        local function button(x,y,w,label,id)
            ui.rect(x,y,w,28,blue);ui.bounded(x+8,y+8,label,14,white,w-16);ui.hit(x,y,w,28,function()ui.activate(id)end)
        end
        text(ui.x+10,top-20,'Basic - primary colors only')
        text(ui.x+10,top-44,'Click a color region to edit. Importing a file is optional.')
        local panels=state.raw and state.raw.basic
        if panels and ((panels.armor and panels.armor.document)or(panels.helmet and panels.helmet.document))then
            button(ui.x+10,top-85,left-20,'Load Current Armor & Helmet','populate_worn')
        else ui.bounded(ui.x+10,top-75,'Loading current colors...',12,muted,left-20)end
        local cliptop,clipbottom=top-142,ui.y+56;local y=cliptop+self.scroll
        self.bounds={x=ui.x,y=clipbottom,w=left,h=cliptop-clipbottom}
        local rows=0;local half=(left-26)/2
        for n,kind in ipairs({'armor','helmet'})do
            local x=ui.x+10+(n-1)*(half+6);local panel=state.raw and state.raw.basic and state.raw.basic[kind]
            local document=panel and panel.document
            ui.bounded(x,top-110,kind=='armor'and 'Armor'or 'Helmet',14,white,half)
            ui.choice('basic_'..kind..'_lut',x,top-142,half)
            local cursor=top-153+self.scroll
            if document then
                rows=math.max(rows,document.height)
                for row=1,document.height do
                    cursor=cursor-34
                    if cursor>=clipbottom and cursor+28<=cliptop then
                        local at=(row-1)*document.width*4;local rgb={}
                        for ch=0,2 do rgb[#rgb+1]=math.floor(math.max(0,math.min(1,document.data[at+ch]))*255+.5)end
                        local pulse=.5+.5*math.sin((state.time or 0)*3)
                        ui.bounded(x+3,cursor+9,'Region '..row,12,{math.floor(175+69*pulse),math.floor(180+22*pulse),math.floor(140-87*pulse)},75)
                        ui.rect(x+80,cursor+2,half-83,26,rgb)
                        local selected=row;local target=kind
                        ui.hit(x,cursor,78,28,function()if select_row(selected,target)~=false then ui.activate('identify_region')end end)
                        ui.hit(x+80,cursor,half-80,28,function()if select_row(selected,target)~=false then ui.activate('cell_color')end end)
                    end
                end
            else
                ui.bounded(x,top-181,panel and panel.unavailable and 'Original LUT unavailable.'or 'Reading colors...',12,muted,half)
                ui.bounded(x,top-201,'Try another LUT # or Load Current Colors.',12,muted,half)
            end
            if kind=='armor'then
                button(x,ui.y+10,(half-6)*.43,'Copy Helmet','basic_copy_helmet')
                button(x+(half-6)*.43+6,ui.y+10,(half-6)*.57,'Copy Helmet to All','basic_copy_helmet_all')
            else button(x,ui.y+10,half,'Copy Armor','basic_copy_armor')end
        end
        y=cliptop+self.scroll-rows*34-11
        self.maximum=math.max(0,cliptop+self.scroll-y-(cliptop-clipbottom));self.scroll=math.min(self.scroll,self.maximum)
        ui.bounded(right,top-160,state.status or '',13,muted,width)
        text(right,top-48,'Import a palette (optional)')
        button(right,top-85,width,'Import DDS / ZIP / RAR...','browse')
        text(right,top-115,'Color changes apply live. Region label: identify.')
        button(right+width-150,ui.y-24,150,'Stop Highlight','stop_identify')
        text(right,top-224,'Saved palettes')
        ui.preset('basic_preset_name','basic_preset',right,top-261,width)
        button(right,top-300,width,'Save preset','basic_save')
        button(right,top-337,width,'Export DDS','basic_export')
        button(right,top-374,(width-6)/2,'Undo','undo');button(right+(width+6)/2,top-374,(width-6)/2,'Redo','redo')
        button(right,top-412,(width-6)/2,'Restore Imported','restore_imported');button(right+(width+6)/2,top-412,(width-6)/2,'Restore Original','restore')
        if state.dirty then text(right,ui.y+20,'Modified - save or export to keep your colors.')end
    end
    return self
end
return B
