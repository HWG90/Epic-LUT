-- Strict data-only, tab-separated interchange. No Lua/JSON evaluation or runtime pointers.
local P={}
local MAX_BYTES=128*1024
local function armor(c)return string.format('%08x',c.identity.armor)end
function P.encode(c,h)
    local lines={'DBF-ARMOR-LUT\t1','armor\t'..armor(c),'body\t'..c.identity.body,'enabled\t'..(h.get('enabled')and '1'or '0')}
    for _,lut in ipairs(c.luts)do
        assert(lut.name:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'))
        lines[#lines+1]=string.format('lut\t%s\t%d\t%d',lut.name,lut.width,lut.height)
        for row=1,lut.height do local id=lut.name..'_r'..row
            lines[#lines+1]=table.concat({'row',lut.name,row,h.get(id..'_on')and '1'or '0',h.get(id..'_color')},'\t')
        end
    end
    return table.concat(lines,'\n')..'\n'
end
function P.decode(text,c)
    assert(type(text)=='string' and #text<=MAX_BYTES and not text:find('[%z\1-\8\11\12\14-\31]'),'Invalid preset data')
    text=text:gsub('\r\n','\n');assert(text:sub(-1)=='\n','Preset must end in newline')
    local expected={};for _,lut in ipairs(c.luts)do expected[lut.name]=lut end
    local values,seen,declared={}, {},{};local line=0;local aid,body,enabled
    for row in text:gmatch('([^\n]*)\n')do
        line=line+1;local f={};for field in (row..'\t'):gmatch('(.-)\t')do f[#f+1]=field end
        if line==1 then assert(row=='DBF-ARMOR-LUT\t1','Unsupported preset version')
        elseif line==2 then assert(#f==2 and f[1]=='armor' and f[2]==armor(c),'Preset is for a different armor kit');aid=true
        elseif line==3 then assert(#f==2 and f[1]=='body' and f[2]==tostring(c.identity.body),'Preset body type mismatch');body=true
        elseif line==4 then assert(#f==2 and f[1]=='enabled' and (f[2]=='0'or f[2]=='1'),'Invalid enabled value');values.enabled=f[2]=='1';enabled=true
        elseif f[1]=='lut' then
            local lut=expected[f[2]];assert(#f==4 and lut and not declared[f[2]] and f[3]==tostring(lut.width) and f[4]==tostring(lut.height),'Unknown, duplicate or incompatible LUT')
            declared[f[2]]=true
        elseif f[1]=='row' then
            local lut=expected[f[2]];local n=tonumber(f[3]);assert(#f==5 and lut and declared[f[2]] and n and n%1==0 and n>=1 and n<=lut.height and f[3]==tostring(n),'Invalid row')
            local id=f[2]..'_r'..n;assert(not seen[id] and (f[4]=='0'or f[4]=='1') and f[5]:match('^#%x%x%x%x%x%x$'),'Invalid or duplicate color row')
            seen[id]=true;values[id..'_on']=f[4]=='1';values[id..'_color']=f[5]:upper()
        else error('Unknown preset record',0)end
    end
    assert(aid and body and enabled,'Incomplete preset header')
    for _,lut in ipairs(c.luts)do assert(declared[lut.name],'Missing LUT');for row=1,lut.height do assert(seen[lut.name..'_r'..row],'Missing row')end end
    return values
end
function P.filename(name)
    assert(type(name)=='string' and #name>=5 and #name<=80 and name:match('^[%w_-]+%.dbflut$'),'Use a simple filename ending in .dbflut')
    return name
end
function P.export(folder,c,h)
    local bytes=P.encode(c,h);local prefix=folder..'/armor-'..armor(c)..'-'..os.date('%Y%m%d-%H%M%S')
    for n=1,999 do local path=prefix..'-'..n..'.dbflut';local exists=io.open(path,'rb')
        if exists then exists:close()else
            local f=assert(io.open(path..'.pending','wb'));assert(f:write(bytes));assert(f:close());assert(os.rename(path..'.pending',path));return path
        end
    end
    error('Export filename limit reached')
end
function P.read(folder,name,c)
    local f=assert(io.open(folder..'/'..P.filename(name),'rb'),'Preset file not found');local bytes=f:read(MAX_BYTES+1);f:close();return P.decode(bytes,c)
end
return P
