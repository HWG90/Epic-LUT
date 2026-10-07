# Epic LUT R4 Alpha

Standalone, Python-free editor. MCM integration and the binding adapter are omitted.

- Four top tabs, compact fonts, clickable pixel grid and independently scrolling 23-column value editor.
- Friendly Import / Apply layout: explained LUT selectors left, import actions and Helmet/Armor checkboxes right, grouped target/row color previews.
- Save LUT to Palette copies the import into the editor. Apply LUT sends the editor document to checked targets. Sharing uses separate full-float DDS preset export.
- Cumulative armor/helmet and individual LUT assignments, persisted applied setup and reversible originals.
- DDS/ZIP/RAR input. RAR requires installed 7-Zip. Patch parsing handles variable type tables and streams required sidecars without charging unrelated ZIP assets to its budget.
- Loader throbber, heartbeat/process checks, cancel/retry, timeout recovery and ownership of RAR child processes.

Offline validation covers Windows import IPC, large/mixed archives, real local RAR extraction, picker recovery, DDS sharing, cumulative target persistence and layout/input behavior. The earlier direct ZIP path was confirmed live. R4's latest import/picker/recovery UI still needs live confirmation; this remains an alpha.

Previous release artifacts remain unchanged. Source and package exclude user assets, settings, logs, embedded Python and codec binaries. The reviewed native input DLL remains.

Additional R4 updates: automatic refresh on import, last-tab reopening, identical full-value table collapsing with edit-triggered separation, and forced redraw on selection/move. Preserve Original Emissives is under Apply and defaults Off. Original game pixel readback is unavailable; enabling it currently fails safely rather than claiming to preserve guessed values. The requested meaning/reference still needs confirmation.

Row Presets now has an editable name plus saved-preset dropdown; new names create presets and existing names select/update them. Selector steppers sit together on the right. Identical imported tables are compared across all channels and collapse into ranges; edited differences reappear in the front-page previews. Selection and move invalidate retained GUI drawing. Reopening preserves the last tab.
