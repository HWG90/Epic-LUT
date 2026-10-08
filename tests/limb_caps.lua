local C=dofile('src/preview/limb_caps.lua')
local slots={0x204eb619,0x5637e5d3,0xa856db0d,0xac652e43,0xcaed6cd6,0x18daef8a,0xfaecf369,0x5c774481,0xf79fe864,0xaf1dc221,0x756f6fa6,0x493966e5}
local resources={};for _,slot in ipairs(slots)do resources[#resources+1]={slot=slot}end
assert(C.material(resources))
resources[#resources+1]={slot=0x7e662968};assert(not C.material(resources))
assert(C.compact({x=0,y=0,z=0},{x=.18,y=.15,z=.03}))
assert(not C.compact({x=0,y=0,z=0},{x=.18,y=.15,z=.8}),'Whole leg was classified as a cap')
print('PASS limb cap classifier: exact material signature and bounded thin geometry')
