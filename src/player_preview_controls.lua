-- Floating portrait controls; GUI coordinates have their origin at the bottom.
local C={}
function C.new()
    local self={x=32,y=150,w=300,h=500,fov=30,yaw=0,pan_x=0,pan_y=0,held=false,right_held=false}
    function self.cancel()self.drag=nil;self.resize=nil;self.orbit=nil;self.pan=nil;self.held=true;self.right_held=true end
    function self.pointer(x,y,down,width,height,right)
        if not x or not y then self.cancel();self.held=down;self.right_held=right;return false end
        local hit=x>=self.x and x<=self.x+self.w and y>=self.y-28 and y<=self.y+self.h+28
        local event
        if down and not self.held and hit then
            if y>self.y+self.h then
                if x>self.x+self.w-30 then event='close'
                elseif self.can_dock and x>self.x+self.w-96 then event='dock'
                elseif not self.docked then self.drag={x-self.x,y-self.y}end
            elseif y<self.y then
                if x>self.x+self.w-24 and not self.docked then self.resize={x=x,y=y,w=self.w,h=self.h,top=self.y+self.h}
                else
                    if x>self.x+self.w/2 then self.fov=math.max(12,self.fov-5)
                    else self.fov=math.min(65,self.fov+5)end
                    event='zoom'
                end
            else self.pan={x=x,y=y,px=self.pan_x,py=self.pan_y}
            end
        end
        if right and not self.right_held and hit and y>=self.y and y<=self.y+self.h and not down then self.orbit={x=x,yaw=self.yaw}end
        if down and self.drag then
            local nx=math.max(2,math.min(width-self.w-2,x-self.drag[1]))
            local ny=math.max(30,math.min(height-self.h-30,y-self.drag[2]))
            if nx~=self.x or ny~=self.y then event='move'end
            self.x,self.y=nx,ny;hit=true
        end
        if down and self.resize then
            local r=self.resize;local sx=(x-r.x)/r.w;local sy=(r.y-y)/r.h
            local scale=1+(math.abs(sx)>math.abs(sy)and sx or sy)
            local maxw=math.min(width-self.x-2,(r.top-30)*.6)
            local nw=math.max(math.min(240,maxw),math.min(maxw,r.w*scale))
            if nw~=self.w then self.w=nw;self.h=nw/.6;self.y=r.top-self.h;event='resize'end
            hit=true
        end
        if down and self.pan then
            local px=math.max(-.25,math.min(.25,self.pan.px+(x-self.pan.x)/self.w))
            local py=math.max(-.25,math.min(.25,self.pan.py+(y-self.pan.y)/self.h))
            if px~=self.pan_x or py~=self.pan_y then self.pan_x,self.pan_y=px,py;event='pan'end
            hit=true
        end
        if right and self.orbit then
            local yaw=(self.orbit.yaw+(x-self.orbit.x)*360/self.w)%360
            if yaw~=self.yaw then self.yaw=yaw;event='rotate'end
            hit=true
        end
        if not down then self.drag=nil;self.resize=nil;self.pan=nil end
        if not right then self.orbit=nil end
        self.held=down;self.right_held=right
        return hit,event
    end
    return self
end
return C
