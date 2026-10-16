-- Actual engine enumeration + production present() + actual binding sessions.
-- No process attachment or game/native function invocation.
local ffi=require('ffi')
local G=dofile('src/gear/gear_catalog.lua')
local Binding=dofile('src/gear/binding_session.lua')
local Engine=dofile('vendor/engine.lua')
local file=assert(io.open('src/editor/direct_editor.lua','rb'));local source=file:read('*a');file:close()
local a=assert(source:find('local function present(',1,true))
local b=assert(source:find('local function material_key(',a,true))
local factory=assert(loadstring('return function(m,native)\n'..source:sub(a,b-1)..'\nreturn present end'))()
local mesh_lists,material_lists,bound,dead={},{},{},{}
local calls={enumerate=0,alive=0,bind=0,create=0}
local native={
 alive=function(unit)calls.alive=calls.alive+1;return dead[unit]and 0 or 1 end,
 meshes=function(unit)return#(mesh_lists[unit]or{})end,
 mesh=function(unit,index)return mesh_lists[unit][index+1]end,
 materials=function(mesh)return#material_lists[mesh]end,
 material=function(mesh,index)return material_lists[mesh][index+1]end}
local fault,nil_inventory
local function enumerate(unit)
 calls.enumerate=calls.enumerate+1
 if fault then error('inventory-error-sentinel',0)end
 if nil_inventory then return nil end
 return Engine.unit_materials(native,unit)
end
local present=factory({engine={unit_materials=function(_,unit)return enumerate(unit)end}},native)
local owned={}
for unit=1,2 do
 mesh_lists[unit]={}
 for mesh_index=0,(unit==1 and 3 or 0)do
  local mesh=unit*100+mesh_index;mesh_lists[unit][#mesh_lists[unit]+1]=mesh;material_lists[mesh]={}
  for material_index=0,(unit==1 and 63 or 0)do
   local material=mesh*100+material_index;material_lists[mesh][#material_lists[mesh]+1]=material
   bound[material]=500
   owned[#owned+1]={unit=unit,mesh=mesh,material=material,mesh_index=mesh_index,material_index=material_index,original=100,current=500}
  end
 end
end
local function key(v)return v.unit..':'..v.mesh..':'..v.material end
local catalog=G.new({identity=function()return{}end,
 units=function()return{{unit=1,slot=1},{unit=2,slot=0}}end,
 materials=enumerate,present=present,binding=function(v)return bound[v.material]end,key=key})
local result=catalog.refresh(owned,100)
assert(calls.enumerate==2 and calls.alive>=#owned,'Discovery must enumerate once per Unit while preserving every live check')
assert(#result.owned==257 and#result.groups==1 and#result.groups[1].bindings==257,'Inventory reuse lost destinations or original ownership')
local before=calls.enumerate;catalog.refresh(owned,100)
assert(calls.enumerate==before+2,'Inventories must not survive the refresh operation')
-- A failed or invalid read cannot become an empty/valid cached inventory.
fault=true;local ok,why=pcall(catalog.refresh,owned,100);assert(not ok and why=='inventory-error-sentinel')
fault=false;assert(#catalog.refresh(owned,100).owned==257,'A failed inventory must be retried by the next operation')
nil_inventory=true;assert(not pcall(catalog.refresh,owned,100),'Invalid inventory must not silently retire bindings')
nil_inventory=false
-- Death is checked for each owned destination even after its inventory filled.
dead[1]=true;local alive_before=calls.alive;local kept=catalog.refresh(owned,100)
assert(calls.alive-alive_before>=#owned and#kept.owned==1,'An earlier inventory cannot bypass per-present Unit lifetime checks')
dead[1]=nil
local target=owned[1];bound[target.material]=100;target.current=100
local session=Binding.new({retain={cache={},records={},bytes=0},present=present,binding=function(v)return bound[v.material]end,key=key,
 create_texture=function()calls.create=calls.create+1;return{object=900}end,
 bind=function(v,value)calls.bind=calls.bind+1;bound[v.material]=value end})
local document={width=1,height=1,data=ffi.new('float[4]',{.1,.2,.3,1})}
before=calls.enumerate;assert(session.apply(document,{target})==1)
assert(calls.enumerate>before and calls.bind==1,'Mutation must independently enumerate a fresh production present() inventory')
-- Replacing a material after discovery must refuse mutation and cleanup writes.
catalog.refresh(owned,100)
local previous=material_lists[target.mesh][1];material_lists[target.mesh][1]=previous+99999
local old_bind=calls.bind;before=calls.enumerate
assert(not pcall(session.apply,document,{target})and calls.bind==old_bind and calls.enumerate>before,'A discovery inventory leaked into later mutation')
before=calls.enumerate;assert(session.restore()and calls.bind==old_bind and calls.enumerate>before,'Restore must validate present membership with a fresh inventory')
material_lists[target.mesh][1]=previous
print('PASS material enumeration: 257 owned destinations / 2 Units use2 discovery scans; fresh lifetime checks, failure retry, and uncached mutation/restore retained')
