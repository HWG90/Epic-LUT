-- Resource IDs are supplied by patch records, never guessed from ordering/names.
local M={}
function M.metadata(text,names)
    assert(type(text)=='string'and #text<=16384,'Import resource metadata budget exceeded')
    local allowed,result={},{};for _,name in ipairs(names)do allowed[name]=true end
    for line in text:gmatch('[^\r\n]+')do
        local file,hash=line:match('^(lut%d%d%d%.dds)\t(%x+)$')
        assert(file and allowed[file]and #hash==16 and not result[file],'Invalid import resource metadata')
        result[file]=hash:lower()
    end
    return result
end
function M.plan(documents,groups,get_object)
    local counts={};for _,d in ipairs(documents)do if d.resource then counts[d.resource]=(counts[d.resource]or 0)+1 end end
    local by_object={};for _,g in ipairs(groups)do by_object[g.object]=g end
    local result={total=#documents,matched=0,unmatched=0,ambiguous=0,unidentified=0,plans={}}
    for _,d in ipairs(documents)do
        if not d.resource then result.unidentified=result.unidentified+1
        elseif counts[d.resource]>1 then result.ambiguous=result.ambiguous+1
        else
            local ok,object=pcall(get_object,d.resource);local g=ok and by_object[object]
            if g then result.matched=result.matched+1;result.plans[#result.plans+1]={document=d,targets=g.bindings,resource=d.resource}
            else result.unmatched=result.unmatched+1 end
        end
    end
    return result
end
return M
