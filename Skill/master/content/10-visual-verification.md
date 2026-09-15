---
id: visual-verification
level: 1
flavors: [claude]
---

## Visual Verification (Screenshot)

The validator catches schema errors, not clipped labels, wrapped titles, or a row that squeezes its controls out of view. After validation, render the document with ActionUIViewer and read the PNG:

```bash
ActionUIViewer <file.json> --screenshot out.png --hide-window
```

Where the viewer is: `ActionUIViewer` on PATH, or in an ActionUI checkout via `cd Apps/ActionUIViewer && swift build --product ActionUIViewer --show-bin-path`, where `Scripts/test-viewer.sh -H <Name>` also captures the sample files. A host application that embeds ActionUI may bundle its own copy of the viewer; its own skill or documentation says where.

`--hide-window` draws the window in-process, off screen: nothing appears on the user's desktop, no Screen Recording permission is needed, and it works while the screen is locked. Prefer it in agent sessions. Without it the default capture reads the window server and falls back to the same in-process rendering when the screen is locked, so an image comes back either way. Add `--screenshot-delay 5` for documents with WebView or VideoPlayer content.

Reading the image:
- The window is 800x600 points (image 1600x1256 pixels with the title bar). Look for truncated text, labels wrapping onto a second line, controls clipped at the window edge, overlaps, and empty space where an element should be.
- Panes that the app fills at runtime are empty in a preview; that is not a layout defect.
- The image has no window shadow, the selected tab of a TabView draws as a solid block, and with the screen locked controls show the inactive gray tint instead of the accent color. Judge layout, not tint.
- The viewer needs a logged-in GUI session. A run that prints nothing and never exits is a shell sandbox blocking its window-server connection; rerun it outside the sandbox.
