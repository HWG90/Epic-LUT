# Epic LUT R4 RC5

Release candidate with integrated Player Preview, Basic/Advanced mode switching, per-LUT imports, named Armory presets, scoped swatch painting with undo, double-click color editing, middle-click copy, tooltips, and Configuration shortcuts with readable key names.

Choose one package: Epic-LUT-R4-RC5-LLL.zip or Epic-LUT-R4-RC5-BSL.zip. Disable the separate epic_player_preview test sidecar and any older Epic LUT entrypoint before enabling RC5. Your settings and presets stay in Local AppData.

Player Preview docks beside the LUT Editor and can pop out on other pages. Use its toggle or configured shortcut (F6 by default). Left-drag pans, right-drag rotates, wheel zooms. Closing Epic LUT waits for preview cleanup before restoring game input.

Validation: editor contracts, preview lifecycle/native ownership tests, and BSL package checks pass. The earlier preview crashed entering game Armory. RC5 includes cleanup ordering and stale-world guards; the guarded Armory transition is pending live confirmation. These packages are prepared for that confirmation and are not yet a published GitHub release.
