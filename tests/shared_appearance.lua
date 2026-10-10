local S = dofile('src/gear/shared_appearance.lua')
local peer = { peer_low = 12, peer_high = 0, unit = 7 }
local appearance = { body = 1, armor = 2, helmet = 3 }
local identity = { body = 1, armor = 2, helmet = 3 }
local packet, members, posted, applied, restored, cleared = 'full', {}, nil, 0, 0, false
local unit_signature, original = '7', 100
local doc = {}
local deps = {
    memory = {},
    game = 0,
    sync = {
        natives = function() end,
        session = function()
            return {
                poll = function(_, text)
                    posted = text
                    return members
                end,
                clear = function()
                    cleared = true
                end,
            }
        end,
    },
    codec = {
        encode = function()
            return packet
        end,
        decode = function(text)
            assert(text == 'full' or text == 'updated')
            return appearance
        end,
    },
    note = function() end,
    highlighting = function()
        return false
    end,
    entries = function()
        return {}
    end,
    identity = function()
        return identity
    end,
    players = function()
        return { peer }
    end,
    resolve = function()
        return identity
    end,
    targets = function()
        return { [doc] = { { original = original } } }, unit_signature
    end,
    bindings = function()
        return {
            apply = function(_, targets)
                assert(targets[1].original == 100, 'Targets captured before restore')
                applied = applied + 1
                original = 200
            end,
            restore = function()
                restored = restored + 1
                original = 100
                return true
            end,
        }
    end,
}
local service = S.new(deps)
members = { { peer_low = 12, peer_high = 0, text = 'full' } }
service.tick(2, true)
service.tick(0.1, true)
assert(applied == 1 and posted == 'full')
service.tick(2, true)
service.tick(0.1, true)
assert(applied == 1, 'Unchanged appearance reapplied')
members[1].text = 'updated'
service.tick(2, true)
service.tick(0.1, true)
assert(applied == 2 and restored == 1, 'Changed packet did not restore prior appearance')
members[1].text = 'invalid'
service.tick(2, true)
assert(next(service.peers) == nil and restored == 2, 'Malformed remote packet left appearance applied')
members[1].text = 'full'
service.tick(2, true)
service.tick(0.1, true)
service.tick(0.1, false)
assert(next(service.peers) == nil, 'Sharing off did not restore remote appearance immediately')
assert(service.close() and cleared)
peer['local'] = true
local local_only = S.new(deps)
local_only.tick(2, true)
local_only.tick(0.1, true)
assert(next(local_only.peers) == nil, 'Local player was treated as a remote target')
print(
    'PASS sharing lifecycle: exact peer ownership, packet updates, unchanged no-op, malformed restore, off and cleanup'
)

-- A receiver waits for every baseline before applying any texture; retry succeeds on readiness.
peer['local'] = false
local ready = false
local real_decode = deps.codec.decode
deps.codec.decode = function(text)
    assert(ready, 'Sharing: waiting for original LUT 1234567890abcdef')
    return appearance
end
members = { { peer_low = 12, peer_high = 0, text = 'delta' } }
local waiting = S.new(deps)
local before = applied
waiting.tick(2, true)
waiting.tick(0.1, true)
assert(applied == before and next(waiting.peers) == nil, 'Incomplete baseline packet applied partially')
assert(waiting.status:find('waiting for original LUT', 1, true))
ready = true
waiting.tick(2, true)
waiting.tick(0.1, true)
assert(applied == before + 1, 'Baseline readiness did not retry incoming delta')
assert(waiting.close())
deps.codec.decode = real_decode

-- A publication failure is not sharingOff. The transport still returns remote
-- packets while retaining only the last successfully encoded same-kit value.
local ffi = require('ffi')
local function lifecycle_fixture()
    local state = {
        identity = { body = 1, armor = 2, helmet = 3 },
        remote_identity = { body = 1, armor = 2, helmet = 3 },
        document = { width = 23, height = 1, data = ffi.new('float[92]') },
        packet = 'same-kit-original',
        remote_packet = 'peer-1',
        encodes = 0,
        applied = 0,
        restored = 0,
        notes = {},
        reads = 0,
    }
    local entry = { key = 'armor:0:0', document = state.document }
    state.entries = { entry }
    local remote_doc = {}
    local fixture = {
        memory = {},
        game = 0,
        sync = {
            natives = function() end,
            session = function(options)
                return {
                    poll = function(_, outgoing, include_local, permissions)
                        assert(include_local == false and type(permissions.enabled) == 'boolean')
                        state.permission, state.outgoing = permissions.enabled, outgoing
                        if state.posted ~= outgoing then
                            state.posted = outgoing
                            options.note(outgoing and 'Sync: shared full LUT appearance.' or 'Sync: sharing removed.')
                        end
                        if not permissions.enabled then
                            return nil
                        end
                        state.reads = state.reads + 1
                        return {
                            { peer_low = 12, peer_high = 0, text = state.remote_packet },
                            { peer_low = 99, peer_high = 0, text = 'do-not-decode-local', ['local'] = true },
                        }
                    end,
                    clear = function()
                        return true
                    end,
                }
            end,
        },
        codec = {
            encode = function(_, entries)
                state.encodes = state.encodes + 1
                assert(not state.failure, state.failure)
                if state.need_baseline then
                    assert(
                        entries[1].original and entries[1].original.data,
                        'Sharing: waiting for original LUT 1234567890abcdef'
                    )
                end
                return state.packet
            end,
            decode = function(value)
                state.decodes = (state.decodes or 0) + 1
                assert(value:match('^peer%-'), 'Local packet was decoded as remote')
                if state.remote_wait then
                    assert(state.remote_ready, 'Sharing: waiting for original LUT 1234567890abcdef')
                end
                return state.remote_identity
            end,
        },
        note = function(value)
            state.notes[#state.notes + 1] = value
        end,
        highlighting = function()
            return state.highlighting
        end,
        entries = function()
            return state.entries
        end,
        identity = function()
            return state.identity
        end,
        players = function()
            return { { peer_low = 12, peer_high = 0, unit = 7 } }
        end,
        resolve = function()
            return state.remote_identity
        end,
        targets = function(remote, appearance)
            assert(
                remote == state.remote_identity and appearance == state.remote_identity,
                'Local identity used as remote target'
            )
            return { [remote_doc] = { { unit = 7 } } }, 'remote-unit-7'
        end,
        bindings = function()
            return {
                apply = function(document, targets)
                    assert(document == remote_doc and targets[1].unit == 7, 'Sharing wrote a local or partial target')
                    state.applied = state.applied + 1
                end,
                restore = function()
                    state.restored = state.restored + 1
                    return true
                end,
            }
        end,
    }
    state.service = S.new(fixture)
    return state
end
local failed = lifecycle_fixture()
failed.service.tick(2, true)
failed.service.tick(0.01, true)
assert(failed.outgoing == 'same-kit-original' and failed.applied == 1)
failed.failure =
    'C:/private/source/shared_lut_codec.lua:143: Full LUT appearance needs 6828 bytes; lobby budget is 3600\nstack details'
failed.document.data[0], failed.remote_packet = 0.25, 'peer-2'
failed.service.tick(2, true)
failed.service.tick(0.01, true)
assert(
    failed.permission and failed.outgoing == 'same-kit-original' and failed.applied == 2,
    'Same-kit encode failure removed advertising or stopped receiving'
)
assert(
    failed.service.status:find('needs 6828 bytes', 1, true)
        and failed.service.status:find('keeping previous shareable appearance', 1, true)
)
assert(
    not failed.service.status:find('C:/', 1, true) and not failed.service.status:find('\n', 1, true),
    'Failure UI leaked paths or stack lines'
)
local encodes, notes = failed.encodes, #failed.notes
failed.service.tick(2, true)
failed.service.tick(2, true)
assert(failed.encodes == encodes and #failed.notes == notes, 'Unchanged encode failure retried or logged every poll')

failed.identity, failed.remote_packet = { body = 9, armor = 10, helmet = 11 }, 'peer-3'
failed.service.tick(2, true)
failed.service.tick(0.01, true)
assert(
    failed.permission and failed.outgoing == nil and failed.applied == 3,
    'New-kit failure advertised mismatched old packet or stopped receiving'
)
assert(
    failed.service.status:find('needs 6828 bytes', 1, true) and failed.service.status ~= 'Sync: sharing removed.',
    'Transport removal masked the encode failure'
)
failed.identity, failed.remote_packet = nil, 'peer-4'
failed.service.tick(2, true)
failed.service.tick(0.01, true)
assert(
    failed.permission and failed.outgoing == nil and failed.applied == 4,
    'Unavailable local identity disabled safe remote receiving'
)

failed.identity, failed.failure, failed.packet = { body = 9, armor = 10, helmet = 11 }, nil, 'new-kit-success'
failed.service.tick(2, true)
assert(
    failed.outgoing == 'new-kit-success' and not failed.service.status:find('6828', 1, true),
    'Successful new-kit encode left failure status stuck'
)
failed.highlighting, failed.identity = true, { body = 1, armor = 2, helmet = 3 }
encodes = failed.encodes
failed.service.tick(2, true)
assert(
    failed.permission and failed.outgoing == nil and failed.encodes == encodes,
    'Highlight hold broadcast a different kit cached packet'
)
assert(failed.service.status:find('highlight', 1, true))
failed.service.tick(0.01, false)
assert(
    next(failed.service.peers) == nil and failed.service.status == 'Sharing: off',
    'Explicit off did not immediately restore remote appearance'
)
failed.service.tick(2, false)
assert(not failed.permission and failed.outgoing == nil and failed.service.status == 'Sharing: off')
assert(failed.service.close())

-- Readiness can change in place without changing the original resource ID.
local pending = lifecycle_fixture()
pending.need_baseline = true
pending.entries[1].original = { resource = '1234567890abcdef', width = 23, height = 1 }
pending.service.tick(2, true)
pending.service.tick(0.01, true)
assert(pending.permission and pending.outgoing == nil and pending.applied == 1)
encodes = pending.encodes
pending.service.tick(2, true)
assert(pending.encodes == encodes, 'Missing baseline triggered an unchanged encode retry')
pending.entries[1].original.data = ffi.new('float[92]')
pending.packet = 'baseline-ready'
pending.service.tick(2, true)
assert(
    pending.encodes == encodes + 1 and pending.outgoing == 'baseline-ready',
    'Baseline readiness did not retry the same resource'
)
assert(not pending.service.status:find('waiting for original', 1, true))
assert(pending.service.close())
local incoming = lifecycle_fixture()
incoming.remote_wait = true
incoming.service.tick(2, true)
incoming.service.tick(0.01, true)
assert(
    incoming.applied == 0 and incoming.service.status:find('waiting for original', 1, true),
    'Incoming baseline packet applied before readiness'
)
notes = #incoming.notes
incoming.service.tick(2, true)
assert(
    incoming.decodes == 2 and #incoming.notes == notes,
    'Incoming baseline did not retry quietly with the same packet'
)
incoming.remote_ready = true
incoming.service.tick(2, true)
incoming.service.tick(0.01, true)
assert(
    incoming.decodes == 3
        and incoming.applied == 1
        and not incoming.service.status:find('waiting for original', 1, true),
    'Incoming baseline readiness left a stale failure status'
)
assert(incoming.service.close())
print(
    'PASS sharing publication failures: same-kit cache, stale-kit removal, continued exact-peer receiving, authoritative bounded status, quiet failures, explicit off and baseline readiness'
)
