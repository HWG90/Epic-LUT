# Hardware cursor artwork and overwrite safeguards

Configuration > Appearance > Cursor mode selects Helldivers (hardware) or Windows (hardware). Helldivers is the default. Both use the existing client-space hardware pointer, so selection and movement do not depend on drawing a software pointer.

The input helper now forwards WM_SETCURSOR to the prior game window procedure when game artwork is selected; Windows mode retains its explicit arrow. It does not guess a resource name, open native menus, or change gameplay input gates. The actual stock cursor appearance still requires live verification. Closing and focus loss retain existing focus, visibility and clipping restoration with readback/retry.

The same cursor helper capability is carried into the maintained MCM, LLL and Photo input forks. Photo retains its camera Escape passthrough behavior. New content-addressed DLLs preserve old pinned helpers and historical release assets.

Configuration > Preset saves > Confirm preset overwrites defaults to enabled. Existing row presets and selected Armory presets ask before replacement. Don't show this again is persisted only after a successful save; re-enable the Configuration preference to restore warnings. Deletion confirmations remain enabled. Row confirmation retains the originally selected pixels.
