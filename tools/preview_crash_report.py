"""Read a Windows minidump's exception, module and named-thread evidence.

Does not attach to or alter a process. Stack entries are address candidates, not
an unwound call stack. Write reports into dist/release review folders only.
"""
import argparse
import json
from pathlib import Path
import struct


def inspect(path):
    with path.open('rb') as file:
        size = path.stat().st_size

        def read(at, length):
            if at < 0 or length < 0 or at + length > size:
                raise ValueError('Truncated dump')
            file.seek(at)
            return file.read(length)

        header = read(0, 32)
        if header[:4] != b'MDMP':
            raise ValueError('Not a minidump')
        count, directory = struct.unpack_from('<II', header, 8)
        if count > 256:
            raise ValueError('Stream budget exceeded')
        streams = {}
        for i in range(count):
            kind, length, at = struct.unpack('<III', read(directory + i * 12, 12))
            read(at, length if length < 32 else 32)
            streams[kind] = (at, length)

        def text(at):
            length = struct.unpack('<I', read(at, 4))[0]
            if length > 32768:
                raise ValueError('String budget exceeded')
            return read(at + 4, length).decode('utf-16-le', errors='replace')

        modules = []
        if 4 in streams:
            at, _ = streams[4]
            count = struct.unpack('<I', read(at, 4))[0]
            if count > 8192:
                raise ValueError('Module budget exceeded')
            for i in range(count):
                record = read(at + 4 + i * 108, 108)
                base, length = struct.unpack_from('<QI', record)
                name_at = struct.unpack_from('<I', record, 20)[0]
                modules.append((base, length, text(name_at)))

        names = {}
        if 24 in streams:
            at, _ = streams[24]
            count = struct.unpack('<I', read(at, 4))[0]
            if count > 4096:
                raise ValueError('Thread budget exceeded')
            for i in range(count):
                thread, name_at = struct.unpack('<IQ', read(at + 4 + i * 12, 12))
                names[thread] = text(name_at)

        at, length = streams[6]
        if length < 168:
            raise ValueError('Exception stream is incomplete')
        exception = read(at, 168)
        thread, = struct.unpack_from('<I', exception)
        code, = struct.unpack_from('<I', exception, 8)
        address, = struct.unpack_from('<Q', exception, 24)
        result = {'dump': str(path), 'thread_id': thread,
                  'thread_name': names.get(thread), 'exception': hex(code),
                  'address': hex(address)}
        context_size, context_at = struct.unpack_from('<II', exception, 160)
        stack_pointer = None
        if context_size >= 256:
            context = read(context_at, 256)
            stack_pointer = struct.unpack_from('<Q', context, 152)[0]
            result['stack_pointer'] = hex(stack_pointer)
        for base, length, name in modules:
            if base <= address < base + length:
                result['module'] = name
                result['module_offset'] = hex(address - base)
                break
        if code == 0xC0000005 and struct.unpack_from('<I', exception, 32)[0] >= 2:
            operation, target = struct.unpack_from('<QQ', exception, 40)
            result['access'] = {0: 'read', 1: 'write', 8: 'execute'}.get(operation, operation)
            result['access_address'] = hex(target)
        # Raw return-address candidates only, not a symbolized/unwound stack.
        if 3 in streams:
            at, _ = streams[3]
            count = struct.unpack('<I', read(at, 4))[0]
            if count > 4096:
                raise ValueError('Thread budget exceeded')
            for i in range(count):
                record = read(at + 4 + i * 48, 48)
                if struct.unpack_from('<I', record)[0] != thread:
                    continue
                stack_start, stack_size, stack_at = struct.unpack_from('<QII', record, 24)
                skip = stack_pointer-stack_start if stack_pointer is not None else 0
                if not 0 <= skip < stack_size:
                    continue
                stack = read(stack_at+skip, min(stack_size-skip, 8192))
                candidates = []
                for offset in range(0, len(stack)-7, 8):
                    value = struct.unpack_from('<Q', stack, offset)[0]
                    for base, length, name in modules:
                        if base <= value < base + length and ('helldivers2' in name.lower() or name.lower().endswith('game.dll')):
                            candidates.append({'stack_address': hex(stack_start+skip+offset), 'module': name, 'offset': hex(value-base)})
                            break
                    if len(candidates) >= 40:
                        break
                result['stack_candidates_not_unwound'] = candidates
                break
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('dump', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = inspect(args.dump)
    report = json.dumps(result, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report + '\n', encoding='utf-8')
    print(report)
