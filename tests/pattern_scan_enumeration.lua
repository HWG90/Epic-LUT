-- Reuse the real engine/present fixture, then exercise production Pattern
-- discovery and scan against the same deterministic local material inventory.
local file=assert(io.open('tests/gear_catalog_enumeration.lua','rb'));local text=file:read('*a');file:close()
local marker='local result=catalog.refresh(owned,100)'
local at=assert(text:find(marker,1,true),'Enumeration fixture bootstrap changed')
local prefix=text:sub(1,at-1)
local checks=[=[
local Pattern=dofile('src/editor/pattern_luts.lua')
local f=assert(io.open('src/editor/direct_editor.lua','rb'));local editor=f:read('*a');f:close()
local begin=assert(editor:find('                discover = function(enumerate)',1,true))
local finish=assert(editor:find('                export = function(name, document)',begin,true))
local code=editor:sub(begin,finish-1):gsub('^%s*discover = ',''):gsub(',%s*$','')
local make=assert(loadstring('return function(m,native,memory,game,read,small,big,binding) return '..code..' end'))()
local function current(v)return bound[v.material]end
local modules={engine={PATTERN_SLOT=2,unit_materials=function(_,unit)return enumerate(unit)end},
 avatar={resolve_live=function()return{}end,units=function()return{{unit=1,type=0,slot=1},{unit=2,type=0,slot=0}}end}}
local discover=make(modules,native,{},1,nil,nil,nil,current)
local discoveries=0
local session=Binding.new({retain={cache={},records={},bytes=0},present=present,binding=current,key=key,
 create_texture=function()calls.create=calls.create+1;return{object=900}end,
 bind=function(v,value)calls.bind=calls.bind+1;bound[v.material]=value end})
for _,v in ipairs(owned)do v.slot=2 end
session.owned=owned
local pattern=Pattern.new({session=session,present=present,materials=enumerate,binding=current,key=key,
 discover=function(e)discoveries=discoveries+1;return discover(e)end,
 note=function(v)return v end,resource_id=tostring})
local result=pattern.scan(true)
assert(calls.enumerate==2 and calls.alive>=257,'Pattern owned checks and discovery must share one inventory per Unit')
assert(#result==1 and#result[1].bindings==257 and#session.owned==257 and result[1].object==100,'Pattern scan lost owned originals or destinations')
local before=calls.enumerate;pattern.scan(true)
assert(calls.enumerate==before+2,'Pattern inventory must be refreshed by each independent scan')
local count=discoveries;before=calls.enumerate
local subset=pattern.scan(true,{owned[1]})
assert(discoveries==count and#subset==1 and#subset[1].bindings==1,'An explicit Pattern subset must not expand to full discovery')
assert(calls.enumerate==before+2,'Owned-lifetime pruning must still cover all owned Units for a subset scan')
fault=true;assert(not pcall(pattern.scan,true));fault=false
assert(#pattern.scan(true)[1].bindings==257,'A failed Pattern inventory must retry without a stale failed cache')
nil_inventory=true;assert(not pcall(pattern.scan,true),'Invalid Pattern inventories must fail instead of becoming empty lists');nil_inventory=false
dead[1]=true;local alive_before=calls.alive;pattern.scan(true)
assert(calls.alive-alive_before>=257 and#session.owned==1,'Pattern lifetime checks must stay fresh for each owned destination')
dead[1]=nil
-- The session receives the original present() function, never scan's cache.
local target=owned[1];target.current=100;bound[target.material]=100
session.owned={}
local document={width=3,height=1,data=ffi.new('float[12]')}
before=calls.enumerate;assert(session.apply(document,{target})==1 and calls.enumerate>before)
pattern.scan(true)
local old=material_lists[target.mesh][1];material_lists[target.mesh][1]=old+99999
local old_binds=calls.bind;before=calls.enumerate
assert(not pcall(session.apply,document,{target})and calls.bind==old_binds and calls.enumerate>before,'Pattern apply reused a discovery inventory after material replacement')
before=calls.enumerate;assert(session.restore()and calls.bind==old_binds and calls.enumerate>before,'Pattern restore must use fresh membership checks')
print('PASS Pattern enumeration: operation-local2-Unit scans, exact subsets, failure/death retry, and uncached apply/restore retained')
]=]
assert(loadstring(prefix..'\n'..checks,'@pattern-scan-enumeration'))()
