-- Strict data-only presets: legacy armor RGB v1 and full-float target-specific v2.
local ffi=require('ffi')
local P={MAX_BYTES=4*1024*1024}
local function item(c)return string.format('%08x',c.identity.target_id or c.identity.armor)end
local function kind(c)return c.identity.target_kind or 'armor'end
local function color(hex)return type(hex)=='string' and hex:match('^#%x%x%x%x%x%x$')end
function P.encode(c,h,documents)
    local version=c.identity.target_kind and 2 or 1
    local lines={version==1 and 'DBF-ARMOR-LUT\t1'or 'EPIC-LUT\t2',version==1 and ('armor\t'..item(c))or ('target\t'..kind(c)..'\t'..item(c)),
        'body\t'..c.identity.body,'enabled\t'..(h.get('enabled')and '1'or '0')}
    if version==2 then local ok,v=pcall(h.get,'preserve_effects');lines[#lines+1]='effects\t'..((not ok or v~=false)and '1'or '0')end
    for _,lut in ipairs(c.luts)do
        assert(lut.name:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'))
        lines[#lines+1]=string.format('lut\t%s\t%d\t%d',lut.name,lut.width,lut.height)
        local doc=documents and documents.documents[lut.name]
        for row=1,lut.height do local id=lut.name..'_r'..row;local hex=h.get(id..'_color');assert(color(hex),'Invalid preset RGB')
            lines[#lines+1]=table.concat({'row',lut.name,row,h.get(id..'_on')and '1'or '0',hex},'\t')
            if version==2 then for col=1,lut.width do
                local values={};local at=((row-1)*lut.width+col-1)*4
                for ch=0,3 do
                    local v=tonumber((doc and doc.data or lut.values)[at+ch])
                    if not doc and col==1 and ch<3 and h.get(id..'_on')then v=tonumber(hex:sub(2+ch*2,3+ch*2),16)/255 end
                    assert(v==v and math.abs(v)~=math.huge,'Nonfinite preset float');values[#values+1]=string.format('%.9g',v)
                end
                lines[#lines+1]=table.concat({'float',lut.name,row,col,unpack(values)},'\t')
            end end
        end
    end
    local text=table.concat(lines,'\n')..'\n';assert(#text<=P.MAX_BYTES,'Preset exceeds size limit');return text
end
function P.decode(text,c)
    assert(type(text)=='string' and #text<=P.MAX_BYTES and not text:find('[%z\1-\8\11\12\14-\31]'),'Invalid preset data')
    text=text:gsub('\r\n','\n');assert(text:sub(-1)=='\n','Preset must end in newline')
    local expected={};for _,lut in ipairs(c.luts)do expected[lut.name]=lut end
    local values,seen,declared,documents,float_seen={}, {},{},{},{};local line,version=0,nil
    for record in text:gmatch('([^\n]*)\n')do
        line=line+1;local f={};for field in (record..'\t'):gmatch('(.-)\t')do f[#f+1]=field end
        if line==1 then
            assert(record=='DBF-ARMOR-LUT\t1'or record=='EPIC-LUT\t2','Unsupported preset version');version=record=='DBF-ARMOR-LUT\t1'and 1 or 2
        elseif line==2 then
            if version==1 then assert(kind(c)=='armor' and #f==2 and f[1]=='armor' and f[2]==item(c),'Legacy preset is for a different armor target')
            else assert(#f==3 and f[1]=='target' and f[2]==kind(c) and f[3]==item(c),'Preset target identity mismatch')end
        elseif line==3 then assert(#f==2 and f[1]=='body' and f[2]==tostring(c.identity.body),'Preset body type mismatch')
        elseif line==4 then assert(#f==2 and f[1]=='enabled' and (f[2]=='0'or f[2]=='1'),'Invalid enabled value');values.enabled=f[2]=='1'
        elseif version==2 and line==5 then assert(#f==2 and f[1]=='effects' and (f[2]=='0'or f[2]=='1'),'Invalid effect preservation flag');values.preserve_effects=f[2]=='1'
        elseif f[1]=='lut' then
            local lut=expected[f[2]];assert(#f==4 and lut and not declared[f[2]] and f[3]==tostring(lut.width) and f[4]==tostring(lut.height),'Unknown, duplicate or incompatible LUT')
            declared[f[2]]=true
            if version==2 then documents[f[2]]=ffi.new('float[?]',lut.width*lut.height*4)end
        elseif f[1]=='row' then
            local lut=expected[f[2]];local n=tonumber(f[3]);assert(#f==5 and lut and declared[f[2]] and n and n%1==0 and n>=1 and n<=lut.height and f[3]==tostring(n),'Invalid row')
            local id=f[2]..'_r'..n;assert(not seen[id] and (f[4]=='0'or f[4]=='1') and color(f[5]),'Invalid or duplicate color row')
            seen[id]=true;values[id..'_on']=f[4]=='1';values[id..'_color']=f[5]:upper()
        elseif f[1]=='float' and version==2 then
            local lut=expected[f[2]];local r,col=tonumber(f[3]),tonumber(f[4])
            assert(#f==8 and lut and declared[f[2]] and r and col and r%1==0 and col%1==0 and r>=1 and r<=lut.height and col>=1 and col<=lut.width,'Invalid float cell')
            local key=f[2]..':'..r..':'..col;assert(not float_seen[key],'Duplicate float cell');float_seen[key]=true
            local at=((r-1)*lut.width+col-1)*4
            for ch=0,3 do local v=tonumber(f[5+ch]);assert(v and v==v and math.abs(v)~=math.huge,'Invalid float');documents[f[2]][at+ch]=v
                assert(math.abs(tonumber(documents[f[2]][at+ch]))~=math.huge,'Float32 overflow')
            end
        else error('Unknown preset record',0)end
    end
    assert(line>=4 and values.enabled~=nil,'Incomplete preset header')
    for _,lut in ipairs(c.luts)do assert(declared[lut.name],'Missing LUT');for row=1,lut.height do assert(seen[lut.name..'_r'..row],'Missing row')
        if version==2 then for col=1,lut.width do assert(float_seen[lut.name..':'..row..':'..col],'Missing float cell')end end
    end end
    return values,version==2 and documents or nil,version
end
function P.filename(name)
    assert(type(name)=='string' and #name>=5 and #name<=80 and name:match('^[%w_-]+%.dbflut$'),'Use a simple filename ending in .dbflut');return name
end
function P.export(folder,c,h,documents)
    local bytes=P.encode(c,h,documents);local prefix=folder..'/'..kind(c)..'-'..item(c)..'-'..os.date('%Y%m%d-%H%M%S')
    for n=1,999 do local path=prefix..'-'..n..'.dbflut';local exists=io.open(path,'rb')
        if exists then exists:close()else local f=assert(io.open(path..'.pending','wb'));assert(f:write(bytes));assert(f:close());assert(os.rename(path..'.pending',path));return path end
    end
    error('Export filename limit reached')
end
function P.read(folder,name,c)
    local f=assert(io.open(folder..'/'..P.filename(name),'rb'),'Preset file not found');local bytes=f:read(P.MAX_BYTES+1);f:close();return P.decode(bytes,c)
end
return P
