---
id: visual-verification
level: 1
flavors: [claude]
---

## Visual Verification (Screenshot)

The validator catches schema errors, not clipped labels, wrapped titles or controls squeezed out of view. After validating, render the document and look at the image:

- With the ActionUI MCP server connected: its `screenshot` tool (macOS and Linux).
- Otherwise ActionUIViewer: `ActionUIViewer <file.json> --screenshot out.png`, adding `--hide-window` on macOS (renders off screen: no window on the desktop, no Screen Recording permission, works with the screen locked; the Linux viewer has no such flag). Add `--screenshot-delay 5` for WebView or VideoPlayer content.

Look for truncated or wrapping text, controls clipped at the window edge, overlaps, and empty space where an element should be. Panes the app fills at run time are empty in a preview; judge layout, not colors or tint. The viewer needs a logged-in GUI session: a run that prints nothing and never exits is usually a sandbox blocking the window server.
