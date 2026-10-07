# Epic LUT R4 RC1

Release candidate; still alpha and work in progress. No Python installation or MCM integration. Requires BSL v15+; RAR requires 7-Zip.

Includes the standalone editor, floating Quick Scratch with ten session-only swatches, exact-cell RGB editing with Undo/Redo, grouped target previews with Show All LUTs, editable row presets, separate read-only palette/live previews, remembered window size and footer scale controls. Save LUT to Palette overwrites the editor; Apply LUT sends the selected file to checked targets. Editor changes preview immediately only when targets are checked. Blank editors can copy the selected applied Live LUT.

The original-game worker indexes resource metadata, matches current local Armor/Helmet bindings and captures matching tables. Lifetime checks are throttled and driven by an editor heartbeat. Worker failures cannot retire the menu. Preserve Original Emissives defaults Off and uses exact original values, including zeros. Native target row counts are retained when the import contains sufficient rows.

Offline editor checks, real-game metadata indexing, requested-only capture, reference-value comparisons and heartbeat-expiry shutdown pass. These results do not certify live startup reliability, snapshot matching, emissive behavior, restart persistence or final UI acceptance. The 3D Player Preview is not included.

No game textures, user settings, presets or logs are included. Creating this candidate does not change installed game files or publish a GitHub release.
