-- Bounded, explicit action history. Capture/restore callbacks own native contracts.
local H={}
function H.new(capture,restore)
    local self={undo={},redo={},busy=false,bytes=0}
    function self.record(before,after)
        if self.busy or not before or not after or before.signature==after.signature then return end
        self.redo={};self.undo[#self.undo+1]={before=before,after=after}
        local bytes=0;for _,entry in ipairs(self.undo)do bytes=bytes+(entry.before.bytes or 0)+(entry.after.bytes or 0)end
        while #self.undo>20 or bytes>32*1024*1024 do local entry=table.remove(self.undo,1);bytes=bytes-(entry.before.bytes or 0)-(entry.after.bytes or 0)end
        self.bytes=bytes
    end
    local function move(from,to,field,expected)
        local entry=from[#from];assert(entry,'No action to '..(field=='before'and 'undo'or 'redo'))
        self.busy=true;local ok,why=pcall(restore,entry[field],entry[expected]);self.busy=false
        if not ok then error(why,0)end
        assert(why~=false,'Action restoration pending')
        table.remove(from);to[#to+1]=entry;return true
    end
    function self.undo_action()return move(self.undo,self.redo,'before','after')end
    function self.redo_action()return move(self.redo,self.undo,'after','before')end
    function self.capture()return capture()end
    return self
end
return H
