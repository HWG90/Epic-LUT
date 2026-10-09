# Epic LUT R5.5 RC1

More room to paint. More ways to keep your work.

- A roomier LUT Editor, movable Tools window and independent Scratch palette. Clear active controls, plain dropdowns, window borders and synchronized UI scale.
- Ctrl+C/V for copy and paste, Ctrl+Z for undo, Ctrl+Shift+Z for redo, drag selection in the pixel grid, and clipboard hex colors in Scratch.
- One-click bulk DDS export for custom gear LUTs and complete Armory presets. Five naming formats, exact resource IDs, shared prefixes and timestamped folders.
- Improved Pattern editing, gear selectors, live color feedback and startup cleanup.
- Apply the current editor table to all Armor or all Helmet LUTs directly from the Import toolbox.
- Named bump-map choices, shown in their actual column-2 R-value order.
- Player Preview uses the Game Default render path, with wider vertical pan. The temporary mesh/material inspector has been removed.
- Organized Configuration and optional MCM settings integration.
- **Load Debug LUT** under Tools > Options, featuring the Debug LUT by **Plain Furniture**.

## A huge thank you to Scarpheon

A huge thank you to **Scarpheon** for all the time he has dedicated to helping me build a better tool for people.

His testing, bug reports, and continued assistance were vital to getting **Export to Patch** implemented correctly and working reliably. He kept trying builds, checking the results in-game, and helping me work through the problems until we got it right.

That work deserves more than a name in a credits list. Epic LUT is a better tool because of the time and care he has put into it. **Thank you, Scarpheon. Your help made this possible.**

Native adapters and foundational LUT research are by **CowboyBingus**. **Plain Furniture** created the bundled Debug LUT.

## Install

- **Epic-LUT-R5.5-RC1-LLL.zip:** Live Lua Loader / compatible MDL. Install the complete `armor_lut_editor` folder.
- **Epic-LUT-R5.5-RC1-BSL.zip:** Arsenal/HD2MM with Bingus Shared Loader v15+.

Enable one Epic LUT entrypoint. F9 opens Basic; F10 opens Advanced. MCM is optional. RAR import requires 7-Zip. Turn Match Your Colors matching off before editing the same gear.

## Candidate notes

Player Preview remains experimental; close it before switching game screens. Custom material compatibility varies. Squad appearance sharing requires compatible builds on both players and still needs full two-player confirmation. Unknown Pattern channels remain labeled unknown.
