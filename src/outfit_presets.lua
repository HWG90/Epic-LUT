-- Named Armor/Helmet collections: validated manifest plus ordinary DDS files.
local O={}
function O.new(m,folder)
    local self={}
    local function name(value)assert(type(value)=='string'and #value>0 and #value<=48 and value:match('^[%w _-]+$'),'Use a preset name up to 48 letters, numbers, spaces, _ or -');return value end
    function self.names()
        local names={};for _,file in ipairs(m.windows.files(folder,'outfit-*.tsv'))do local n=file:match('^outfit%-([%w _-]+)%.tsv$');if n then names[#names+1]=n end end;return names
    end
    function self.save(label,entries)
        name(label);assert(#entries>0 and #entries<=128,'No attached LUTs to save')
        local rows={'EPIC-OUTFIT\t1'}
        for i,e in ipairs(entries)do
            assert((e.kind=='armor'or e.kind=='helmet')and e.key:match('^[%d:]+$'),'Invalid target')
            local file='outfit-'..label..'-'..e.kind..'-'..i..'.dds'
            m.dds.write(folder..'/'..file,e.document.data,e.document.width,e.document.height)
            rows[#rows+1]=e.kind..'\t'..e.key..'\t'..file
        end
        local target=folder..'/outfit-'..label..'.tsv';local f=assert(io.open(target..'.tmp','wb'));assert(f:write(table.concat(rows,'\n')));assert(f:close())
        os.remove(target);assert(os.rename(target..'.tmp',target));return true
    end
    function self.load(label)
        name(label);local f=assert(io.open(folder..'/outfit-'..label..'.tsv','rb'));local text=f:read(65537);f:close();assert(#text<=65536,'Preset manifest budget exceeded')
        local lines={};for line in text:gmatch('[^\r\n]+')do lines[#lines+1]=line end
        assert(lines[1]=='EPIC-OUTFIT\t1'and #lines>1 and #lines<=129,'Invalid outfit preset')
        local result={name=label,armor={},helmet={},entries={}};local bytes=0
        for i=2,#lines do
            local kind,key,file=lines[i]:match('^(armor)\t([%d:]+)\t(outfit%-[%w _-]+%.dds)$')
            if not kind then kind,key,file=lines[i]:match('^(helmet)\t([%d:]+)\t(outfit%-[%w _-]+%.dds)$')end
            assert(kind,'Invalid preset entry');local input=assert(io.open(folder..'/'..file,'rb'));local payload=input:read(m.dds.MAX_BYTES+1);input:close()
            local data,w,h=m.dds.decode(payload);assert(w==23,'Preset is not a material LUT');bytes=bytes+w*h*16;assert(bytes<=8*1024*1024,'Preset pixel budget exceeded')
            local document={data=data,width=w,height=h,source=label..' / '..kind}
            result.entries[#result.entries+1]={kind=kind,key=key,document=document};result[kind][#result[kind]+1]=document
        end
        return result
    end
    return self
end
return O
