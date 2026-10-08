-- Full-float working documents. UI previews are separate from the immutable original source.
local ffi=require('ffi')
local M={}
function M.new(dds)
    local self={documents={},undo_stack={},redo_stack={},clipboard=nil}
    local function clone(lut,data)local out=ffi.new('float[?]',lut.width*lut.height*4);ffi.copy(out,data,lut.width*lut.height*16);return out end
    function self.attach(catalog,folder,handle,prefix)
        self.documents={};self.undo_stack={};self.redo_stack={}
        for _,lut in ipairs(catalog.luts)do
            local d={lut=lut,data=clone(lut,lut.values),active=true,path=(prefix or folder..'/')..lut.name..'.dds',stamp=nil}
            local f=io.open(d.path,'rb')
            if f then local bytes=f:read(dds.MAX_BYTES+1);f:close();local ok,data=pcall(dds.decode,bytes,lut.width,lut.height)
                if ok then d.data=data;d.active=true;d.stamp=bytes else d.error=tostring(data)end
            else
                for row=0,lut.height-1 do
                    local id=lut.name..'_r'..(row+1)
                    if handle.get and handle.get(id..'_on') then
                        local hex=handle.get(id..'_color');local at=row*lut.width*4
                        d.data[at],d.data[at+1],d.data[at+2]=tonumber(hex:sub(2,3),16)/255,tonumber(hex:sub(4,5),16)/255,tonumber(hex:sub(6,7),16)/255
                    end
                end
            end
            self.documents[lut.name]=d
        end
    end
    local function retain_history(d)
        self.undo_stack[#self.undo_stack+1]={name=d.lut.name,data=clone(d.lut,d.data),active=d.active}
        if #self.undo_stack>64 then table.remove(self.undo_stack,1)end;self.redo_stack={}
    end
    function self.edit(name,changes)
        local d=assert(self.documents[name]);local nextdata=clone(d.lut,d.data)
        for index,value in pairs(changes)do assert(index%1==0 and index>=0 and index<d.lut.width*d.lut.height*4,'Invalid float index');nextdata[index]=value end
        dds.validate(nextdata,d.lut.width,d.lut.height);retain_history(d);d.data=nextdata;d.active=true;return d
    end
    function self.replace(name,data)
        local d=assert(self.documents[name]);dds.validate(data,d.lut.width,d.lut.height);retain_history(d);d.data=clone(d.lut,data);d.active=true;return d
    end
    function self.reset()
        for _,d in pairs(self.documents)do d.data=clone(d.lut,d.lut.values);d.active=false end
        self.undo_stack={};self.redo_stack={}
    end
    local function history(from,to)
        local snapshot=table.remove(from);if not snapshot then return false end
        local d=assert(self.documents[snapshot.name]);to[#to+1]={name=d.lut.name,data=clone(d.lut,d.data),active=d.active}
        d.data=snapshot.data;d.active=snapshot.active;return snapshot.name
    end
    function self.undo()return history(self.undo_stack,self.redo_stack)end
    function self.redo()return history(self.redo_stack,self.undo_stack)end
    function self.row_copy(name,row)
        local d=assert(self.documents[name]);assert(row>=1 and row<=d.lut.height)
        local data=ffi.new('float[?]',d.lut.width*4);ffi.copy(data,d.data+(row-1)*d.lut.width*4,d.lut.width*16)
        self.clipboard={width=d.lut.width,data=data};return true
    end
    function self.row_paste(name,row)
        local d=assert(self.documents[name]);local c=assert(self.clipboard,'Copy a row first');assert(c.width==d.lut.width and row>=1 and row<=d.lut.height,'Incompatible row')
        local changes={};for i=0,c.width*4-1 do changes[(row-1)*c.width*4+i]=tonumber(c.data[i])end;return self.edit(name,changes)
    end
    function self.save(name,path)
        local d=assert(self.documents[name]);dds.write(path or d.path,d.data,d.lut.width,d.lut.height);d.stamp=dds.encode(d.data,d.lut.width,d.lut.height);return path or d.path
    end
    function self.poll(name,path)
        local d=assert(self.documents[name]);local f=io.open(path or d.path,'rb');if not f then return false end
        local bytes=f:read(dds.MAX_BYTES+1);f:close();if bytes==d.stamp then return false end
        local data=dds.decode(bytes,d.lut.width,d.lut.height);self.replace(name,data);d.stamp=bytes;return true
    end
    function self.poll_all(locked)
        local pending={}
        for name,d in pairs(self.documents)do
            local f=io.open(d.path,'rb')
            if f then local bytes=f:read(dds.MAX_BYTES+1);f:close()
                if bytes~=d.stamp then pending[#pending+1]={name=name,bytes=bytes,data=dds.decode(bytes,d.lut.width,d.lut.height)}end
            end
        end
        if locked()then return {}end
        for _,p in ipairs(pending)do self.replace(p.name,p.data);self.documents[p.name].stamp=p.bytes end
        return pending
    end
    function self.compose(name,handle)
        local d=self.documents[name];if not d or not d.active then return nil end
        local data=clone(d.lut,d.lut.values)
        for row=0,d.lut.height-1 do if handle.get(name..'_r'..(row+1)..'_on')then
            ffi.copy(data+row*d.lut.width*4,d.data+row*d.lut.width*4,d.lut.width*16)
        end end
        return data
    end
    return self
end
return M
