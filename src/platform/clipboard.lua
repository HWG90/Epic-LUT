-- One clipboard interface for editor fields, with an explicit portable host.
local C={MAX_BYTES=32768,MAX_UNITS=16384}
local function valid(text)
    if type(text)~='string' or #text>32768 then return false end
    local at,units=1,0
    while at<=#text do
        local a,b,c,d=text:byte(at,at+3)
        local size=1
        if a==0 then return false
        elseif a<128 then
        elseif a>=194 and a<=223 then
            if not b or b<128 or b>191 then return false end
            size=2
        elseif a>=224 and a<=239 then
            if not b or b<128 or b>191 or not c or c<128 or c>191
                or a==224 and b<160 or a==237 and b>159 then return false end
            size=3
        elseif a>=240 and a<=244 then
            if not b or b<128 or b>191 or not c or c<128 or c>191 or not d or d<128 or d>191
                or a==240 and b<144 or a==244 and b>143 then return false end
            size=4
        else return false end
        units=units+(size==4 and 2 or 1)
        if units>16384 then return false end
        at=at+size
    end
    return true
end
function C.new(deps)
    deps=deps or {}
    if not deps.service then
        local legacy=m and m.legacy_clipboard or require('src.platform.legacy_clipboard')
        return legacy.new(deps)
    end
    local service=deps.service
    assert(type(service)=='table' and type(service.get)=='function' and type(service.set)=='function',
        'Clipboard get/set service required')
    local self={}
    function self.get()
        local called,text,why=pcall(service.get)
        if not called then return nil,'Clipboard read failed.' end
        if text==nil then return nil,why or 'Clipboard unavailable.' end
        if not valid(text) then return nil,'Clipboard has no valid Unicode text.' end
        return text
    end
    function self.set(text)
        if not valid(text) then return false,'Clipboard text is too large or invalid.' end
        local called,ok,why=pcall(service.set,text)
        if not called then return false,'Clipboard write failed.' end
        if ok==true then return true end
        return false,why or 'Clipboard unavailable.'
    end
    return self
end
return C
