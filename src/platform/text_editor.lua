-- Pure UTF-8 single-line editing. Positions are byte boundaries; native drawing,
-- clipboard ownership and value validation remain in the menu.
local T = {}
function T.previous(text, at)
    at = math.max(0, at - 1)
    while at > 0 and (text:byte(at + 1) or 0) >= 128 and (text:byte(at + 1) or 0) < 192 do
        at = at - 1
    end
    return at
end
function T.next(text, at)
    at = math.min(#text, at + 1)
    while at < #text and (text:byte(at + 1) or 0) >= 128 and (text:byte(at + 1) or 0) < 192 do
        at = at + 1
    end
    return at
end
function T.ensure(e)
    e.text = e.text or ''
    if e.cursor == nil or e.replace then
        e.cursor, e.anchor = #e.text, e.replace and 0 or #e.text
        e.replace = false
    end
    e.cursor = math.max(0, math.min(#e.text, e.cursor))
    e.anchor = math.max(0, math.min(#e.text, e.anchor or e.cursor))
    while e.cursor > 0 and (e.text:byte(e.cursor + 1) or 0) >= 128 and (e.text:byte(e.cursor + 1) or 0) < 192 do
        e.cursor = e.cursor - 1
    end
    while e.anchor > 0 and (e.text:byte(e.anchor + 1) or 0) >= 128 and (e.text:byte(e.anchor + 1) or 0) < 192 do
        e.anchor = e.anchor - 1
    end
    return e
end
function T.range(e)
    T.ensure(e)
    return math.min(e.cursor, e.anchor), math.max(e.cursor, e.anchor)
end
function T.selected(e)
    local a, b = T.range(e)
    return e.text:sub(a + 1, b)
end
function T.all(e)
    T.ensure(e)
    e.anchor, e.cursor = 0, #e.text
end
local function remember(e)
    e.undo = e.undo or {}
    e.undo[#e.undo + 1] = { text = e.text, cursor = e.cursor, anchor = e.anchor }
    if #e.undo > 32 then
        table.remove(e.undo, 1)
    end
    e.redo = {}
end
function T.insert(e, value, limit)
    local a, b = T.range(e)
    local room = math.max(0, (limit or 48) - (#e.text - (b - a)))
    local parts, used = {}, 0
    for glyph in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if used + #glyph > room then
            break
        end
        parts[#parts + 1] = glyph
        used = used + #glyph
    end
    value = table.concat(parts)
    local result = e.text:sub(1, a) .. value .. e.text:sub(b + 1)
    if result == e.text then
        e.cursor, e.anchor = a + #value, a + #value
        return false
    end
    remember(e)
    e.text = result
    e.cursor, e.anchor = a + #value, a + #value
    return true
end
function T.delete(e, backward)
    local a, b = T.range(e)
    if a == b then
        if backward then
            a = T.previous(e.text, a)
        else
            b = T.next(e.text, b)
        end
    end
    if a == b then
        return false
    end
    remember(e)
    e.text = e.text:sub(1, a) .. e.text:sub(b + 1)
    e.cursor, e.anchor = a, a
    return true
end
function T.move(e, code, shift, ctrl)
    local a, b = T.range(e)
    local at = e.cursor
    if code == 36 then
        at = 0
    elseif code == 35 then
        at = #e.text
    elseif code == 37 then
        at = not shift and a ~= b and a or T.previous(e.text, at)
    elseif code == 39 then
        at = not shift and a ~= b and b or T.next(e.text, at)
    else
        return false
    end
    if ctrl and (code == 37 or code == 39) then
        local function word(n)
            return e.text:sub(n + 1, T.next(e.text, n)):match('[%w_]') ~= nil
        end
        if code == 37 then
            while at > 0 and not word(at) do
                at = T.previous(e.text, at)
            end
            while at > 0 and word(T.previous(e.text, at)) do
                at = T.previous(e.text, at)
            end
        else
            while at < #e.text and word(at) do
                at = T.next(e.text, at)
            end
            while at < #e.text and not word(at) do
                at = T.next(e.text, at)
            end
        end
    end
    e.cursor = at
    if not shift then
        e.anchor = at
    end
    return true
end
function T.history(e, redo)
    T.ensure(e)
    local source, target = redo and e.redo or e.undo, redo and 'undo' or 'redo'
    if not source or #source == 0 then
        return false
    end
    e[target] = e[target] or {}
    e[target][#e[target] + 1] = { text = e.text, cursor = e.cursor, anchor = e.anchor }
    local prior = table.remove(source)
    e.text, e.cursor, e.anchor = prior.text, prior.cursor, prior.anchor
    return true
end
function T.at(e, pixels, measure)
    T.ensure(e)
    local at, prior = 0, 0
    while at < #e.text do
        local next_at = T.next(e.text, at)
        local width = measure(e.text:sub(1, next_at))
        if pixels < (prior + width) / 2 then
            return at
        end
        at, prior = next_at, width
    end
    return #e.text
end
function T.repeat_key(state, e, down, dt, emit)
    if not state or state.editor ~= e or not down(state.code) then
        return nil
    end
    state.age = state.age + math.max(0, math.min(0.1, dt or 0))
    local count = 0
    while state.age >= state.next and count < 4 do
        emit(state.code)
        state.next = state.next + 0.04
        count = count + 1
    end
    return state
end
return T
