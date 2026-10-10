-- Uses stock Stingray GUI and stock font; no HUD asset dependency.
local M={}
function M.new(sr,preview_only,diagnostic_log)
    local preview_guis={}
    local gui,world;local ids={};local G=sr.Gui;local self={};local reported=false
    local preview_materials={}
    local preview_view=not preview_only and M.new(sr,true,diagnostic_log) or nil
    local popup_view=not preview_only and M.new(sr,true) or nil
    local function positive(value)return type(value)=='number'and value>0 and value<math.huge end
    local function drawable()
        if self.suspended then return false end
        if type(G.resolution)~='function'then return true end
        local ok,w,h=pcall(G.resolution)
        return ok and positive(w)and positive(h)
    end
    local function live()for _,w in pairs(sr.Application.worlds() or {})do if w==world then return true end end;return false end
    local metrics={};local metric_bases={}
    local vertical_metrics={};local vertical_count=0
    function self.text_metrics(size,label)
        if not positive(size)then return {min_y=0,max_y=0,height=0}end
        label=label or 'Ag0#'
        local key=tostring(size)..'|'..label
        if vertical_metrics[key]then return vertical_metrics[key]end
        local result={min_y=0,max_y=size,height=size}
        if drawable()and gui and live()and type(G.text_extents)=='function' and label~=''then
            local ok,lo,hi=pcall(G.text_extents,gui,label,'core/performance_hud/debug',size)
            if ok and lo and hi and type(lo.y)=='number' and type(hi.y)=='number'
                and lo.y==lo.y and hi.y==hi.y and hi.y>lo.y and hi.y-lo.y<size*3 then
                result={min_y=lo.y,max_y=hi.y,height=hi.y-lo.y}
            end
            if vertical_count>=512 then vertical_metrics={};vertical_count=0 end
            vertical_metrics[key]=result;vertical_count=vertical_count+1
        end
        return result
    end
    function self.measure(glyph,size)
        if glyph==''or not positive(size)then return 0 end
        local key=glyph..'|'..size;if metrics[key]then return metrics[key]end
        local width=size*.62
        if drawable()and gui and live() and type(G.text_extents)=='function' then
            local ok,value=pcall(function()
                local base=metric_bases[size]
                if not base then
                    local lo,hi=G.text_extents(gui,'MM','core/performance_hud/debug',size)
                    base=hi.x-lo.x
                    assert(positive(base)and base<2000,'Invalid native font metric')
                    metric_bases[size]=base
                end
                -- Keep both terminal glyphs constant so ink bearings cancel.
                local lo,hi=G.text_extents(gui,'M'..glyph..'M','core/performance_hud/debug',size)
                return (hi.x-lo.x)-base
            end)
            if ok and positive(value)and value<1000 then width=value;metrics[key]=width end
        end
        return width
    end
    local function destroy_item(item)
        if item.bold_id then pcall(G.destroy_text,item.gui or gui,item.bold_id)end
        pcall(G['destroy_'..item.type],item.gui or gui,item.id);if item.extra_id then pcall(G.destroy_triangle,item.gui or gui,item.extra_id)end
    end
    -- Each popup owns a bounded depth range. Roles stay inside that range even
    -- when native GUI IDs are retained and only a background is recreated.
    local surface_depth={window_background=0,control_border=.1,slider_track=.18,
        swatch_border=.2,swatch_fill=.25,slider_fill=.25,control_accent=.35,
        slider_thumb_border=.35,slider_thumb=.4,marker_border=.4,text_selection=.4,
        marker_fill=.45,selection_outline=.45,text_caret=.7,window_frame=.9}
    local content_depth={control_border=-.01,slider_track=.01,swatch_border=0,
        swatch_fill=.01,slider_fill=.02,selection_outline=.02,control_accent=.03,
        slider_thumb_border=.03,slider_thumb=.04,marker_border=.05,marker_fill=.06,
        text_selection=.07,text_caret=1.02}
    local function command_depth(c)
        if c.paint_plane and c.paint_span then
            local local_depth=surface_depth[c.ui_role]or(c.type=='text'and .6 or .15)
            return c.paint_plane+c.paint_span*local_depth
        end
        return (c.layer or 100)+(c.type=='text'and 1 or 0)+(content_depth[c.ui_role]or 0)
    end
    function self.clear()
        if not drawable()then return false end
        if gui and live()then for _,item in ipairs(ids)do destroy_item(item)end end;ids={}
        return true
    end
    function self.invalidate()
        if not drawable()then return false end
        self.clear();if preview_view then preview_view.clear()end;if popup_view then popup_view.clear()end
    end
    function self.release()
        if not drawable()then return false end
        if preview_view then preview_view.release()end;if popup_view then popup_view.release()end
        reported=false
        if gui and live()then
            self.clear();for _,g in pairs(preview_guis)do sr.World.destroy_gui(world,g)end
            preview_guis={};sr.World.destroy_gui(world,gui)
        end
        gui,world=nil,nil
        return true
    end
    function self.draw(commands)
        if not drawable()then return false end
        local valid
        for index,c in ipairs(commands)do
            if c.type=='text'and not positive(c.size)then
                if not valid then valid={};for i=1,index-1 do valid[#valid+1]=commands[i]end end
            elseif valid then valid[#valid+1]=c end
        end
        commands=valid or commands
        if preview_view then
            local menu,preview,popup={},{},{}
            for _,c in ipairs(commands)do
                local destination=c.hud_preview and preview or (c.popup and popup or menu)
                destination[#destination+1]=c
            end
            preview_view.draw(preview);popup_view.draw(popup);commands=menu
        end
        if #commands==0 then self.release();return end
        if gui and not live()then gui,world=nil,nil;ids={};preview_guis={}end
        if not gui then
            local main=sr.Application.main_world();world=main
            local animation_worlds=package.loaded['epic.preview.animation-worlds.v1']or{}
            for _,w in pairs(sr.Application.worlds() or {})do if w~=main and not animation_worlds[w]then world=w;break end end
            if not world then return end
            gui=sr.World.create_screen_gui(world,'scale',1,1)
        end
        local function command_gui(c)
            if not c.preview_role then return gui end
            preview_guis[c.preview_role]=preview_guis[c.preview_role] or sr.World.create_screen_gui(world,'scale',1,1)
            return preview_guis[c.preview_role]
        end
        local old_ids=ids;ids={};local report={};local seen={};local uniforms={}
        local report_now=diagnostic_log and not reported
        local signatures={}
        for index,c in ipairs(commands)do
            -- Sidebar command counts must not change unrelated content depth.
            local z=command_depth(c)
            signatures[index]=table.concat({c.type,c.text or '',c.x,c.y,c.w or 0,c.h or 0,c.size or 0,c.a,c.c[1],c.c[2],c.c[3],z,c.font_resource or '',c.font_material or '',c.preview_material or '',c.preview_uv and table.concat(c.preview_uv,',') or '',c.preview_role or '',tostring(c.bold)},'|')
        end
        -- Destroy all stale IDs before allocations: engines may reuse IDs immediately.
        for index,old in ipairs(old_ids)do
            if old.signature~=signatures[index] then
                destroy_item(old);old_ids[index]=false
            end
        end
        for index,c in ipairs(commands)do
            -- Sidebar command counts must not change unrelated content depth.
            local z=command_depth(c)
            local signature=signatures[index]
            local target_gui=command_gui(c)
            local old=old_ids[index]
            -- Refresh uniforms for retained preview triangles on every draw.
            local uniform_key=(c.preview_role or '')..':'..(c.preview_material or '')
            if c.preview_material and not uniforms[uniform_key] and sr.Application.can_get('material',c.preview_material) then
                local handle=G.material(target_gui,c.preview_material)
                if handle then
                    sr.Material.set_scalar(handle,'scissor_mode',0)
                    sr.Material.set_scalar(handle,'threshold_fade',0)
                    if c.preview_mapping then
                        local r=c.preview_mapping
                        sr.Material.set_vector4(handle,'scissor_rect',sr.Vector4(r[1],r[2],r[3],c.preview_time or 0))
                        sr.Material.set_vector4(handle,'atlas_scissor',sr.Vector4(r[4],r[5],r[6],c.preview_animation or 0))
                        sr.Material.set_vector4(handle,'clip_box',sr.Vector4(r[7],r[8],r[9],0))
                    end
                    uniforms[uniform_key]=true
                end
            end
            if report_now and c.type=='text' and not c.diagnostic_console then report[#report+1]=string.format('%d z=%.2f label=%q',index,z,c.text or '')end
            if old and old.signature==signature then
                ids[#ids+1]=old
            else
            local color=sr.Color(math.floor(c.a*255+.5),c.c[1],c.c[2],c.c[3]);local value;local primitive_type=c.type;local extra_id;local bold_id
            if c.type=='rect' and c.preview_material and type(G.triangle)=='function' and sr.Application.can_get('material',c.preview_material) then
                local handle=assert(G.material(target_gui,c.preview_material),'Preview material unavailable')
                sr.Material.set_scalar(handle,'scissor_mode',0);sr.Material.set_scalar(handle,'threshold_fade',0)
                local a=sr.Vector3(c.x,0,c.y);local b=sr.Vector3(c.x+c.w,0,c.y)
                local d=sr.Vector3(c.x+c.w,0,c.y+c.h);local e=sr.Vector3(c.x,0,c.y+c.h)
                local uv=c.preview_uv
                local ua=uv and sr.Vector2(uv[1],uv[4]) or nil;local ub=uv and sr.Vector2(uv[3],uv[4]) or nil
                local ud=uv and sr.Vector2(uv[3],uv[2]) or nil;local ue=uv and sr.Vector2(uv[1],uv[2]) or nil
                value=G.triangle(target_gui,a,b,d,z,color,c.preview_material,ua,ub,ud)
                extra_id=G.triangle(target_gui,a,d,e,z,color,c.preview_material,ua,ud,ue);primitive_type='triangle'
                if diagnostic_log and not preview_materials[c.preview_material] then preview_materials[c.preview_material]=true;diagnostic_log('MCM_PREVIEW_SHADER material='..c.preview_material..' triangles='..tostring(value)..','..tostring(extra_id)..' bounds='..c.x..','..c.y..','..c.w..','..c.h)end
            elseif c.type=='rect' then value=G.rect(target_gui,sr.Vector3(c.x,c.y,z),sr.Vector2(c.w,c.h),color)
            else
                local font,material='core/performance_hud/debug','core/performance_hud/debug'
                if c.font_resource then font,material=c.font_resource,c.font_material end
                value=G.text(target_gui,c.text,font,c.size,material,sr.Vector3(c.x,c.y,z),color)
                if c.bold then bold_id=G.text(target_gui,c.text,font,c.size,material,sr.Vector3(c.x+.65,c.y,z),color)end
            end
            if report_now and c.type=='text' and not c.diagnostic_console then report[#report]=report[#report]..' allocation='..tostring(value)end
            if value then ids[#ids+1]={type=primitive_type,id=value,extra_id=extra_id,bold_id=bold_id,signature=signature,gui=target_gui}else ids[#ids+1]={type=c.type,id=nil,signature=nil}end
            end
        end
        if report_now then
            local duplicate=0;for _,item in ipairs(ids)do local key=item.type..':'..tostring(item.id);if seen[key]then duplicate=duplicate+1 end;seen[key]=true end
            diagnostic_log('MCM TEXT DIAGNOSTIC primitives='..#commands..' duplicate_handles='..duplicate)
            for _,line in ipairs(report)do diagnostic_log('MCM TEXT '..line)end
            reported=true
        end
    end
    return self
end
return M
