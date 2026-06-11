# ActionUIWeb

Browser renderer for ActionUI JSON: the same JSON that drives SwiftUI (Apple)
and Jetpack Compose (Android) rendered as DOM + CSS, with app logic in
JavaScript. Background and design rationale:
`Private/ActionUI-Web-Investigation.md`; plan, structure, and porting progress:
`Private/ActionUI-Web-Design.md` and `Private/Web_Porting_Notes.md`.

**Status: Phase 0 (early).** Developed on the `ActionUIWeb` branch. No build
step, no dependencies — plain ES modules. The source layout deliberately mirrors
the Swift (`ActionUI/`) and Android (`com/abracode/actionui/`) implementations
file-for-file (`Common/`, `Helpers/`, `Views/`, one file per element type) so
the three renderers stay diffable.

## Run the demo

ES modules and `fetch` require an HTTP server (not `file://`):

```sh
cd ActionUIWeb
python3 -m http.server 8080
# open http://localhost:8080/demo/
```

## What is implemented

- **Core** (`src/Common/`): element parsing with negative-ID generation and
  `children`/`content` key routing (`ActionUIElement.js`), type registry with
  fail-graceful unknown-type placeholders (`ActionUIRegistry.js`), per-window
  model with viewID→DOM binding records instead of a virtual DOM
  (`ActionUIModel.js`), baseline View modifier subset — padding, font text
  styles, colors, frame, cornerRadius, opacity, hidden, disabled, help, generic
  actionID (`ModifierResolver.js`), shared stack vocabulary (`StackAxis.js`),
  console logger (`ConsoleLogger.js`).
- **Elements** (`src/Views/`, one file per type): VStack, HStack, ZStack,
  Spacer, Divider, Text, Button, TextField, Toggle (switch + checkbox styles).
  Property names and defaults follow `Documentation/Schemas/*.md`; deliberate
  omissions (markdown, systemImage, numeric formats, template mode, …) log
  warnings and are tracked in `Private/Web_Porting_Notes.md`.
- **API** (`src/ActionUI.js`): `Application` / `Window` classes mirroring
  `ActionUINodeJS/index.js` — `Window.fromURL/fromJSON`, `presentWindow`,
  `get/setString|Bool|Int|Double|Value`, `app.action(id, fn)`,
  `setDefaultHandler`. Action handlers receive
  `(actionID, windowUUID, viewID, viewPartID, context)` as on all platforms.
- **Theme** (`theme.css`): tokenized CSS custom properties, macOS-flavored
  default skin, automatic dark mode via `prefers-color-scheme`.

## Layout mapping demonstrated

VStack/HStack → flexbox (`spacing` → `gap`, alignment → `align-items`),
ZStack → single-cell grid, Spacer → `flex-grow: 1`,
`frame.maxWidth: "infinity"` → `flex-grow` + `max-width: 100%`.
