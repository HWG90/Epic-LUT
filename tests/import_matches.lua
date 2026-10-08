local M=dofile('src/import_matches.lua')
local metadata=M.metadata('lut000.dds\t1111111111111111\nlut001.dds\t2222222222222222',{'lut000.dds','lut001.dds'})
assert(metadata['lut000.dds']=='1111111111111111')
assert(not pcall(M.metadata,'../escape.dds\t1111111111111111',{'lut000.dds'}),'Unsafe resource metadata accepted')
local armor,helmet={name='armor'},{name='helmet'}
local groups={{object=100,bindings={armor}},{object=200,bindings={helmet}}}
local function get(hash)return ({['1111111111111111']=100,['2222222222222222']=200})[hash]end
local documents={{resource=metadata['lut000.dds']},{resource=metadata['lut001.dds']},{resource='3333333333333333'},{}}
local p=M.plan(documents,groups,get)
assert(p.matched==2 and p.unmatched==1 and p.unidentified==1 and p.plans[1].targets[1]==armor and p.plans[2].targets[1]==helmet,'Matching guessed targets or lost metadata')
documents[#documents+1]={resource='1111111111111111'}
p=M.plan(documents,groups,get);assert(p.matched==1 and p.ambiguous==2 and #p.plans==1,'Conflicting resource IDs were automatically applied')
print('PASS import matching: retained IDs, exact local bindings, unidentified/unmatched resources, ambiguous sources excluded')
