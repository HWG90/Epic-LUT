-- Signature observed in the generic leg cut-surface material, a781f50f508ed81b.
-- Matching alone is insufficient: only compact, thin geometry on leg pieces is eligible.
local C = {}
local slots={0x204eb619,0x5637e5d3,0xa856db0d,0xac652e43,0xcaed6cd6,0x18daef8a,
    0xfaecf369,0x5c774481,0xf79fe864,0xaf1dc221,0x756f6fa6,0x493966e5}
function C.material(resources)
    local found={}
    for _,r in ipairs(resources)do found[r.slot]=true end
    for _,slot in ipairs(slots)do if not found[slot]then return false end end
    return not found[0x7e662968] and not found[0x81d4c49d]
end
function C.compact(lo,hi)
    local spans={math.abs(hi.x-lo.x),math.abs(hi.y-lo.y),math.abs(hi.z-lo.z)}
    for _,v in ipairs(spans)do if v~=v or v==math.huge then return false end end
    return math.max(unpack(spans))>.01 and math.max(unpack(spans))<=.35 and math.min(unpack(spans))<=.12
end
return C
