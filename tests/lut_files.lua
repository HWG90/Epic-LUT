local ffi = require('ffi')
local called
local data = ffi.new('float[184]')
data[92] = 0.75
local files = dofile('src/presets/lut_files.lua').new('folder', {
    dds = {
        MAX_BYTES = 100,
        write = function(path, pixels, w, h)
            called = { path = path, pixels = pixels, w = w, h = h }
            return path
        end,
        decode = function(bytes, w, h)
            assert(bytes == 'dds' and w == 23 and h == 1)
            return 'pixels'
        end,
    },
    read = function(path, limit)
        assert(path == 'folder/row-Example.dds' and limit == 100)
        return 'dds'
    end,
    row_names = function(folder)
        assert(folder == 'folder')
        return { 'Example' }
    end,
})
files.save_row('Example', { data = data, width = 23, height = 2 }, 2)
assert(called.path == 'folder/row-Example.dds' and called.pixels[0] == 0.75 and called.h == 1, 'Wrong row exported')
assert(files.load_row('Example') == 'pixels' and files.row_names()[1] == 'Example')
assert(
    not pcall(files.load_row, '../escape') and not pcall(files.save_row, 'Example', { height = 2 }, 3),
    'Unsafe name/row accepted'
)
files.save('Export', { data = data, width = 23, height = 2 })
assert(called.path == 'folder/Export.dds' and called.h == 2, 'Full export shape lost')
print('PASS LUT files: validated names, exact row offsets, bounded decoding and full-document export')
