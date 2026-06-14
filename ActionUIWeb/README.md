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

## Symbol map

`Image`'s `systemName` resolution uses the SF -> Material map at
`assets/symbols/sf_to_material.map`. It is **committed** (small, and the
GitHub-hosted demo needs it), so no setup is required after cloning. It is a
generated artifact copied from ActionUIAndroid; refresh it when the upstream
mapping changes:

```sh
cd ActionUIWeb
sh scripts/sync-symbol-map.sh           # re-copy from the sibling ActionUIAndroid
# or: sh scripts/sync-symbol-map.sh /path/to/sf_to_material.map
```

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
  model with viewID->DOM binding records instead of a virtual DOM — for both
  element values and named element states (`ActionUIModel.js`), baseline View modifier subset — padding, font text
  styles, colors, frame, cornerRadius, opacity, hidden, disabled, help, generic
  actionID (`ModifierResolver.js`), shared stack vocabulary (`StackAxis.js`),
  console logger (`ConsoleLogger.js`), and `<key>:<platform>` override
  resolution (`PlatformFilter.js`, active token `web`, run over the JSON before
  the tree is built).
- **Elements** (`src/Views/`, one file per type): VStack, HStack, ZStack,
  Spacer, Divider, Text, Button, TextField, Toggle (switch + checkbox styles),
  Image, Label, Slider, Stepper, SecureField, Picker, ProgressView, DatePicker,
  ColorPicker, ScrollView, LazyVStack, LazyHStack, Grid, LazyVGrid, LazyHGrid,
  Form, Section, GroupBox, LabeledContent, DisclosureGroup, TextEditor, Gauge,
  the shape primitives Rectangle, RoundedRectangle, Capsule, Circle,
  Ellipse (shared fill/stroke resolution in `Helpers/ShapeStyleHelper.js`),
  TabView + Tab (a tab strip — or a left sidebar rail with
  `style: sidebarAdaptable` — with selection binding and badges),
  Menu (a pull-down of action items, with sections and dividers),
  List (a row collection; all three modes — heterogeneous children, homogeneous
  itemType, and the data-driven template repeater with `$1`/`$2` column
  references — with selection),
  Table (a multi-column data table driven by the rows API), and
  NavigationSplitView (a sidebar | (content) | detail layout — static panes, or a
  sidebar List whose `destinationViewId` rows switch the detail pane).
  Each view's `validateProperties` warnings match the Swift
  contract (`ActionUI/Views/*.swift`) verbatim; deliberate omissions log warnings
  and are tracked in `Private/Web_Porting_Notes.md`.
- **Symbols** (`src/Helpers/MaterialSymbolResolver.js` + `Helpers/SymbolIcon.js`
  + `assets/symbols/`): a shared glyph path — `Image`, `Button`, and `Label` all
  render SF Symbols (`systemName`/`systemImage`) via the Android SF->Material map
  and Material Symbols (`materialName`) via the OFL Material Symbols web font
  (loaded by the host page; see `demo/index.html`).
- **API** (`src/ActionUI.js`): `Application` / `Window` classes mirroring
  `ActionUINodeJS/index.js` — `Window.fromURL/fromJSON`, `presentWindow`,
  `get/setString|Bool|Int|Double|Value`, `get/setState` (named element states,
  e.g. DisclosureGroup's `isExpanded`), the rows API for data-driven collections
  (`get/set/append/clearElementRows`, `getElementColumnCount` — sugar over the
  `content` state, used by Table and List's data-driven modes), `app.action(id, fn)`,
  `setDefaultHandler`. Action handlers receive
  `(actionID, windowUUID, viewID, viewPartID, context)` as on all platforms.
- **Theme** (`theme.css`): tokenized CSS custom properties, macOS-flavored
  default skin, automatic dark mode via `prefers-color-scheme`.

## Layout mapping demonstrated

VStack/HStack -> flexbox (`spacing` -> `gap`, alignment -> `align-items`),
ZStack -> single-cell grid, Spacer -> `flex-grow: 1`,
`frame.maxWidth: "infinity"` -> `flex-grow` + `max-width: 100%`.
