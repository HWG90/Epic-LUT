-- Registry schema for LUT editing. Callbacks delegate to the editor's document operations.
local C = {}
function C.new(deps)
    local self = deps.editor
    local palette = deps.palette
    local semantics = deps.semantics
    local document, note, save = deps.document, deps.note, deps.save
    local remember, change, history = deps.remember, deps.change, deps.history
    local color_columns, color_labels = deps.color_columns, deps.color_labels
    local preset_files = deps.preset_files
    local ffi = require('ffi')
    local function pages()
        local advanced = {
            { type = 'text', label = 'Material, camo and raw RGBA values. Unknown meanings stay marked unknown.' },
            {
                id = 'advanced_row',
                type = 'choice',
                label = 'Palette row',
                choices = { 'Import first' },
                default = 1,
                on_change = function(value)
                    if not self.busy then
                        assert(self.handle.set('edit_row', value))
                        self.sync()
                    end
                end,
            },
            {
                id = 'edit_column',
                type = 'choice',
                label = 'Material / camo field',
                choices = semantics.columns,
                default = 1,
                on_change = function()
                    self.sync()
                end,
            },
            {
                id = 'unlock',
                type = 'toggle',
                label = 'Enable advanced float editing',
                default = false,
                on_change = function()
                    self.sync()
                end,
            },
        }
        for _, spec in ipairs({
            { 'shader_mode', 'Shader mode', 1, 4, 0, 3 },
            { 'detail_texture', 'Bump map', 2, 1, 0, 25 },
            { 'camo_pattern', 'Camo pattern', 22, 4, -1, 5 },
        }) do
            local id, label, col, ch, lo, hi = unpack(spec)
            local choices = {}
            for v = lo, hi do
                choices[#choices + 1] = id == 'detail_texture' and semantics.bump_label(v) or tostring(v)
            end
            advanced[#advanced + 1] = {
                id = id,
                type = 'choice',
                presentation = 'combined',
                label = label,
                choices = choices,
                default = 1,
                on_change = function(value)
                    if self.busy or value > hi - lo + 1 then
                        return
                    end
                    change(col, ch, value + lo - 1)
                end,
            }
        end
        for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
            local channel = ch
            advanced[#advanced + 1] = {
                id = 'cell_' .. name,
                type = 'slider',
                raw_numeric = true,
                label = name:upper(),
                min = -1e10,
                max = 1e10,
                step = 0.001,
                default = 0,
                on_change = function(value)
                    change(self.handle.get('edit_column'), channel, value)
                end,
            }
        end
        return {
            {
                id = 'colors',
                name = '2. LUT Editor',
                require_confirmation = false,
                controls = {
                    {
                        id = 'grid_tool',
                        type = 'choice',
                        presentation = 'dropdown',
                        label = 'Grid tool',
                        choices = { 'Select', 'Draw', 'Move selection' },
                        default = 1,
                    },
                    {
                        id = 'grid_channel',
                        type = 'choice',
                        presentation = 'dropdown',
                        label = 'Channels',
                        choices = { 'RGB', 'RGBA', 'Red', 'Green', 'Blue', 'Alpha' },
                        default = 1,
                    },
                    { id = 'copy_value', type = 'button', label = 'Copy Value', on_activate = self.copy_value },
                    { id = 'paste_value', type = 'button', label = 'Paste Value', on_activate = self.paste_value },
                    { id = 'group_rows', type = 'toggle', label = 'Group by rows', default = true },
                    { id = 'value_editor_visible', type = 'toggle', label = 'Value Editor', default = true },
                    {
                        id = 'copy_selection',
                        type = 'button',
                        label = 'Copy pixels',
                        on_activate = self.copy_selection,
                    },
                    {
                        id = 'paste_selection',
                        type = 'button',
                        label = 'Paste pixels',
                        on_activate = self.paste_selection,
                    },
                    {
                        id = 'edit_row',
                        type = 'choice',
                        presentation = 'combined',
                        label = 'Palette row',
                        choices = { 'Import first' },
                        default = 1,
                        on_change = function(value)
                            if not self.busy then
                                self.open_row = value
                                self.value_scroll = 0
                                self.sync()
                            end
                        end,
                    },
                    {
                        id = 'color_field',
                        type = 'choice',
                        label = 'Color field',
                        choices = color_labels,
                        default = 1,
                        on_change = function()
                            self.sync()
                        end,
                    },
                    {
                        id = 'cell_color',
                        type = 'color',
                        label = 'Selected color',
                        default = '#FFFFFF',
                        on_change = function(hex)
                            if self.busy then
                                return
                            end
                            local d = remember()
                            local column = color_columns[self.handle.get('color_field')]
                            local i = semantics.index(self.handle.get('edit_row'), column, 1, d.width, d.height)
                            local r, g, b = palette.rgb(hex)
                            d.data[i], d.data[i + 1], d.data[i + 2] = r, g, b
                            self.sync()
                            note('Color edited. Live preview updates automatically.')
                        end,
                    },
                    {
                        id = 'reset_color',
                        type = 'button',
                        label = 'Reset selected color to imported',
                        on_activate = function()
                            local d = remember()
                            local i = semantics.index(
                                self.handle.get('edit_row'),
                                color_columns[self.handle.get('color_field')],
                                1,
                                d.width,
                                d.height
                            )
                            for ch = 0, 2 do
                                d.data[i + ch] = d.original[i + ch]
                            end
                            self.sync()
                            return note('Selected RGB restored; alpha unchanged.')
                        end,
                    },
                },
            },
            { id = 'advanced', name = '3. Material / camo', require_confirmation = false, controls = advanced },
            {
                id = 'save',
                name = 'Configuration',
                require_confirmation = false,
                controls = {
                    {
                        id = 'show_alpha',
                        type = 'toggle',
                        label = 'Show Alpha',
                        default = false,
                        description = 'Display swatch alpha over a checkerboard. Display only: shader alpha can control behavior instead of transparency.',
                    },
                    {
                        id = 'scratch_color',
                        type = 'color',
                        label = 'Scratch color',
                        default = '#FFFFFF',
                        on_change = function(hex)
                            local r, g, b = palette.rgb(hex)
                            self.scratch = { r * 255, g * 255, b * 255 }
                        end,
                    },
                    { id = 'scratch_copy', type = 'button', label = 'Copy HEX', on_activate = self.scratch_copy },
                    { id = 'scratch_paste', type = 'button', label = 'Paste HEX', on_activate = self.scratch_paste },
                    {
                        id = 'scratch_alpha',
                        type = 'slider',
                        label = 'Scratch alpha',
                        min = 0,
                        max = 1,
                        step = 0.001,
                        default = 1,
                    },
                    {
                        id = 'paint_scratch',
                        type = 'button',
                        label = 'Paint selected RGB',
                        on_activate = function()
                            assert(semantics.is_color(23, self.handle.get('edit_column')), 'Select a color column')
                            return self.handle.set('cell_color', self.handle.get('scratch_color'))
                        end,
                    },
                    {
                        id = 'copy_row',
                        type = 'button',
                        label = 'Copy selected row',
                        on_activate = function()
                            local d = assert(document(), 'Import first')
                            self.row_clip =
                                ffi.string(d.data + (self.handle.get('edit_row') - 1) * d.width * 4, d.width * 16)
                            return note(
                                'Copied row '
                                    .. self.handle.get('edit_row')
                                    .. ', all '
                                    .. d.width
                                    .. ' columns (full RGBA)'
                            )
                        end,
                    },
                    {
                        id = 'paste_row',
                        type = 'button',
                        label = 'Paste row',
                        on_activate = function()
                            assert(self.row_clip, 'Copy a row first')
                            local d = remember()
                            ffi.copy(
                                d.data + (self.handle.get('edit_row') - 1) * d.width * 4,
                                self.row_clip,
                                #self.row_clip
                            )
                            self.sync()
                            return note(
                                'Pasted into row '
                                    .. self.handle.get('edit_row')
                                    .. ', all '
                                    .. d.width
                                    .. ' columns (full RGBA)'
                            )
                        end,
                    },
                    {
                        id = 'reset_row',
                        type = 'button',
                        label = 'Reset selected row',
                        on_activate = function()
                            return self.reset_part(true)
                        end,
                    },
                    {
                        id = 'reset_cell',
                        type = 'button',
                        label = 'Reset selected cell',
                        on_activate = function()
                            return self.reset_part(false)
                        end,
                    },
                    { id = 'row_preset', type = 'input', label = 'Row preset name', default = 'my-row' },
                    {
                        id = 'row_preset_select',
                        type = 'choice',
                        presentation = 'combined',
                        label = 'Saved row presets',
                        choices = { 'New preset...' },
                        default = 1,
                        on_change = function(index)
                            if not self.busy then
                                assert(self.handle.set('row_preset', index > 1 and self.preset_names[index - 1] or ''))
                            end
                        end,
                    },
                    {
                        id = 'save_row',
                        type = 'button',
                        label = 'Save row preset',
                        on_activate = function()
                            local d = assert(document(), 'Import first')
                            local name = self.handle.get('row_preset')
                            preset_files.save_row(name, d, self.handle.get('edit_row'))
                            self.refresh_presets()
                            return note('Row preset saved: ' .. name)
                        end,
                    },
                    {
                        id = 'load_row',
                        type = 'button',
                        label = 'Apply row preset',
                        on_activate = function()
                            local name = self.handle.get('row_preset')
                            local data = preset_files.load_row(name)
                            local d = remember()
                            ffi.copy(d.data + (self.handle.get('edit_row') - 1) * d.width * 4, data, d.width * 16)
                            self.sync()
                            return note('Row preset applied. Live preview updates automatically.')
                        end,
                    },
                    {
                        id = 'undo',
                        type = 'button',
                        label = 'Undo',
                        on_activate = function()
                            return history(self.undo, self.redo)
                        end,
                    },
                    {
                        id = 'redo',
                        type = 'button',
                        label = 'Redo',
                        on_activate = function()
                            return history(self.redo, self.undo)
                        end,
                    },
                    {
                        id = 'save_name',
                        type = 'input',
                        label = 'Export name (without extension)',
                        default = 'Epic-LUT-edited',
                    },
                    {
                        id = 'open_export',
                        type = 'button',
                        label = 'Open Export Location',
                        on_activate = function()
                            return assert(deps.open_export, 'Export folder unavailable')()
                        end,
                    },
                    {
                        id = 'export_format',
                        type = 'choice',
                        label = 'Export format',
                        choices = { 'DDS', 'Selected LUT Patch', 'Entire Palette Patch', 'All Custom LUTs (DDS)' },
                        default = 1,
                    },
                    {
                        id = 'dds_naming',
                        type = 'choice',
                        presentation = 'dropdown',
                        label = 'DDS filenames',
                        choices = { 'LUT# + HEX', 'LUT# + Decimal', 'LUT#', 'HEX', 'Decimal' },
                        default = 1,
                    },
                    {
                        id = 'export_selected',
                        type = 'button',
                        label = 'Export...',
                        on_activate = function()
                            local format = self.handle.get('export_format')
                            if format == 1 then
                                return save(self.handle.get('save_name'))
                            end
                            if format == 4 then
                                return assert(deps.save_bulk, 'Bulk DDS exporter unavailable')(
                                    self.handle.get('save_name'),
                                    self.handle.get('dds_naming')
                                )
                            end
                            return assert(deps.save_patch, 'Patch exporter unavailable')(
                                self.handle.get('save_name'),
                                format == 3
                            )
                        end,
                    },
                    {
                        id = 'save_dds',
                        type = 'button',
                        label = 'Export DDS preset to share',
                        on_activate = function()
                            return save(self.handle.get('save_name'))
                        end,
                    },
                    {
                        id = 'save_patch_all',
                        type = 'button',
                        label = 'Export Entire Palette',
                        description = 'Export all worn Armor, Helmet and Pattern LUTs into one patch ZIP, using their currently applied values.',
                        on_activate = function()
                            return assert(deps.save_patch, 'Patch exporter unavailable')(
                                self.handle.get('save_name'),
                                true
                            )
                        end,
                    },
                    {
                        id = 'save_patch',
                        type = 'button',
                        label = 'Export Patch ZIP for selected Live LUT',
                        on_activate = function()
                            return assert(deps.save_patch, 'Patch exporter unavailable')(self.handle.get('save_name'))
                        end,
                    },
                },
            },
        }
    end
    return pages
end
return C
