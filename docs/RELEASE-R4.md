# Epic LUT R4 Alpha

Standalone, Python-free editor. MCM integration and the binding adapter are omitted.

- Four top tabs, compact fonts, clickable pixel grid and independently scrolling 23-column value editor.
- Friendly Import / Apply layout: explained LUT selectors left, import actions and Helmet/Armor checkboxes right, grouped target/row color previews.
- Save LUT to Palette copies the import into the editor. Apply LUT sends the selected file LUT to checked targets. Editor edits preview immediately when Armor and/or Helmet are checked. Sharing uses separate full-float DDS preset export.
- Cumulative armor/helmet and individual LUT assignments, persisted applied setup and reversible originals.
- DDS/ZIP/RAR input. RAR requires installed 7-Zip. Patch parsing handles variable type tables and streams required sidecars without charging unrelated ZIP assets to its budget.
- Loader throbber, heartbeat/process checks, cancel/retry, timeout recovery and ownership of RAR child processes.

Offline validation covers Windows import IPC, large/mixed archives, real local RAR extraction, picker recovery, DDS sharing, cumulative target persistence and layout/input behavior. The earlier direct ZIP path was confirmed live. R4's latest import/picker/recovery UI still needs live confirmation; this remains an alpha.

Previous release artifacts remain unchanged. Source and package exclude user assets, settings, logs, embedded Python and codec binaries. The reviewed native input DLL remains.

Additional R4 updates: automatic refresh on import, last-tab reopening, identical full-value table collapsing with edit-triggered separation, and forced redraw on selection/move. Preserve Original Emissives is under Apply and defaults Off. Original game pixel readback is unavailable; enabling it currently fails safely rather than claiming to preserve guessed values. The requested meaning/reference still needs confirmation.

Row Presets now has an editable name plus saved-preset dropdown; new names create presets and existing names select/update them. Selector steppers sit together on the right. Identical imported tables are compared across all channels and collapse into ranges; edited differences reappear in the front-page previews. Selection and move invalidate retained GUI drawing. Reopening preserves the last tab.

## Original-game snapshot candidate

A background Windows PowerShell/.NET reader extracts base material LUTs directly from installed DSAR/DSAA game archives. No Python, equipment identifiers or archive decoding on the game thread. Snapshots are private under `%LOCALAPPDATA%/Epic LUT/originals/<index fingerprint>/`, never distributed in the package. Resource hashes are matched to live original texture objects; hydration is limited to 32 resource checks per update. Preserve Original Emissives stays Off by default and preserves original column 14 RGBA plus primary shader mode, including exact zero values. Missing or dimension-mismatched data blocks preservation instead of guessing.

Offline evidence: 2,312 material tables from the installed game validate; 23 historical reference files match exactly. Windows PowerShell 5 fresh-cache extraction and owner-process exit cleanup pass. Live resource matching, emissive behavior and startup remain pending for this candidate.

Equipped-only recovery candidate: initial metadata indexing identifies base LUT resources; only original textures matched to the local equipped Armor/Helmet are decoded and saved. Snapshot polling, timeout and stop failures are contained and do not retire the menu. Offline narrowed capture saved exactly two requested tables and matched their reference float data. Live verification is pending.
