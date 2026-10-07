# Epic LUT — friendly standalone import candidate

## Import and edit

1. Install one Epic LUT entry through BSL / your mod manager, then launch and press F10.
2. Import / Apply has LUT dropdowns and explanations on the left; file import and target controls on the right.
3. Import DDS / ZIP / RAR opens the Windows picker. Select a file anywhere. Imported LUT selects a color table inside that file. Live LUT # identifies a local material lookup currently used by your gear.
4. Save LUT to Palette copies the selected import into the editor. It does not apply to gear or export a file. Imported color swatches appear directly below this button.
5. Edit through the LUT Editor tab, then return to Import / Apply. Check Helmet and/or Armor and press Apply LUT. Applications are cumulative; changing source selections does not remove previously applied targets.
6. Armor and Helmet previews show separate assigned palettes, grouped by LUT and row. Their swatches represent Base, Detail, Inner, Outer, Curvature, Tint and four Camo color fields. Refresh updates the live LUT list.

## Restore and share

Restore Original LUT restores game bindings and clears saved automatic application while retaining the editor document. Restore Imported LUT resets editor changes to its original imported data; use Apply LUT to send that reset to gear.

Save applied setup stores active assignments for later launches. Save / History -> Export DDS preset to share writes the full edited LUT to `%LOCALAPPDATA%/Epic LUT/files/<name>.dds`. Share that DDS; another user can import it directly. RGB display clamping does not alter exported finite float values. Export and application are separate.

## Loading and recovery

An animated throbber shows opening, picker, reading and extraction phases plus elapsed time. Cancel import keeps the previous palette. Retry file picker closes the previous owned worker before opening another. Process exit, invalid heartbeat identity, missing startup heartbeat, stale progress and a five-minute deadline release stuck requests. Worker process handles are closed. RAR children belong to an OS job that closes on worker exit, including forced recovery.

RAR requires installed 7-Zip; ZIP/DDS do not. Windows PowerShell/.NET supplies the picker and data-only extraction. No Python, MCM integration or persistent service is included. Match Your Colors should be Off before applying.

Supported material LUTs are 23-column 2D RGBA16F/RGBA32F DDS, including validated mip chains, and standard patch resources with matching sidecars in ZIP/RAR. Required data is streamed to private temporary files; unrelated archive assets are ignored. Inputs are never installed or executed. EXR, pattern/cape layouts and original GPU pixel readback are outside this lean version.

Offline checks cover real Windows ZIP IPC, actual local RAR extraction, picker recovery, separated import/edit/apply behavior, cumulative target assignments, sharing DDS, layout rendering and animation. Live confirmation of this candidate is still pending. Nothing is deployed or published by building it.
