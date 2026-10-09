-- Worker message boundary. Parsing never mutates editor state or touches native bindings.
local P = { MAX_PROGRESS = 512, MAX_RESULT = 8192, MAX_TABLES = 256 }
local phases = { starting = true, picker = true, reading = true, extracting = true }
function P.progress(text, pid, now)
    if type(text) ~= 'string' or #text > P.MAX_PROGRESS then
        return nil, 'Progress budget exceeded'
    end
    local worker, phase, beat, percent, detail = text:match('^(%d+)\t([a-z]+)\t(%d+)\t(%d+)\t([^\r\n]*)$')
    if not worker then
        worker, phase, beat, percent = text:match('^(%d+)\t([a-z]+)\t(%d+)\t(%d+)$')
    end
    if not worker then
        worker, phase, beat = text:match('^(%d+)\t([a-z]+)\t(%d+)$')
    end
    if tonumber(worker) ~= pid or not phases[phase] or not tonumber(beat) or tonumber(beat) > now + 2 then
        return nil, 'Invalid picker state'
    end
    return {
        phase = phase,
        percent = math.max(0, math.min(100, tonumber(percent) or 0)),
        detail = detail,
        last_beat = tonumber(beat),
        reported = true,
    }
end
function P.result(text)
    assert(type(text) == 'string' and #text <= P.MAX_RESULT, 'Archive result exceeds budget')
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do
        lines[#lines + 1] = line
    end
    if lines[1] == 'cancel' then
        return { canceled = true, names = {} }
    end
    if lines[1] == 'preset' then
        assert(
            #lines == 3 and lines[2] == 'preset.tsv' and #lines[3] <= 48 and lines[3]:match('^[%w _-]+$'),
            'Invalid shared preset result'
        )
        return { preset = lines[2], label = lines[3], names = {} }
    end
    assert(lines[1] == 'ok', lines[2] or 'Archive extraction failed')
    assert(#lines >= 2 and #lines <= P.MAX_TABLES + 1, 'Invalid extracted palette count')
    local names, seen = {}, {}
    for i = 2, #lines do
        local name = lines[i]
        assert(name:match('^lut%d%d%d%.dds$'), 'Invalid extracted palette filename')
        assert(not seen[name], 'Duplicate extracted palette filename')
        seen[name] = true
        names[#names + 1] = name
    end
    return { names = names }
end
function P.paths(base)
    return {
        result = base .. '.txt',
        progress = base .. '.txt.progress',
        cancel = base .. '.txt.cancel',
        resources = base .. '/resources.tsv',
        info = base .. '/import-info.txt',
    }
end
return P
