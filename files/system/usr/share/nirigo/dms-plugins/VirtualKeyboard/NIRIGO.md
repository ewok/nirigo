# nirigo focus fixes

Upstream: https://github.com/sitolam/dms-plugins

Revision: `85820f16252afcc74361117879764d735c97ef1b`

License: GPL-3.0-only. The image ships the upstream license as `LICENSE`.
The upstream plugin credits end-4/dots-hyprland for the keyboard design and
layout; see its `README.md` for those credits.

`files/scripts/install-virtualkeyboard.sh` installs the pinned plugin before
the image's files module overlays these modifications:

- `KeyboardWindow.qml`: docked panel always uses `WlrKeyboardFocus.None`.
- `FloatingKeyboardWindow.qml`: replaces the focusable toplevel with a masked,
  non-focusing full-screen layer-shell panel. Only the keyboard and its drag
  handle accept pointer/touch input. Dragging moves the card inside the panel;
  bounds and input-mask dimensions account for scaling on small screens.

Both preserve the daemon's existing show/hide and pin/unpin interface and
modifier-release behavior. Pinned mode is now a movable overlay, not a native
floating window. Escape is delivered to the application, so use the hide
button, widget toggle, or `dms ipc call virtualKeyboard close` to dismiss it.

The source manifest, daemon, settings and widget retain the `virtualKeyboard`
ID. The `Float by default` setting now opens the movable overlay.

Update the pinned revision in the build script deliberately, checking these
interfaces and repeating the README's device focus tests. The image-owned
plugin is linked by `ujust dms-keyboard-setup` and updated with the image.
