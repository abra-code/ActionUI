# ActionUIWeb

Browser renderer for ActionUI JSON: the same JSON that drives SwiftUI (Apple)
and Jetpack Compose (Android), rendered as DOM + CSS with app logic in
JavaScript.

**Status: complete and merged to `main`.** The renderer covers the full
cross-platform element and modifier surface; only a few perf/exotic items remain
deferred (see [Deferred](#deferred)). No build step, no runtime dependencies -
plain ES modules. The source layout deliberately mirrors the Swift (`ActionUI/`)
and Android (`com/abracode/actionui/`) implementations file-for-file (`Common/`,
`Helpers/`, `Views/`, one file per element type) so the three renderers stay
diffable.

## Run the demo

ES modules and `fetch` require an HTTP server (not `file://`):

```sh
cd ActionUIWeb
python3 -m http.server 8080
# open http://localhost:8080/demo/
```

The demo is a `NavigationSplitView` shell (`demo/ui.json`); each sidebar section is
a separate JSON file under `demo/sections/`, pulled in by a `LoadableView`.

## Run the tests

A development-only Node test suite (no browser; the DOM is stubbed) covers the
core, helpers, validators, and the JS API. It is the only thing in this package
that needs Node; the library and demo ship with zero runtime dependencies.

```sh
cd ActionUIWeb
npm test        # node --test test/*.test.mjs - 142 tests
```

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

## What is implemented

- **Core** (`src/Common/`): element parsing with negative-ID generation and
  `children`/`content` key routing (`ActionUIElement.js`), type registry with
  fail-graceful unknown-type placeholders (`ActionUIRegistry.js`), per-window
  model with viewID->DOM binding records instead of a virtual DOM - for both
  element values and named element states (`ActionUIModel.js`), baseline View
  modifier subset - padding, font text styles, colors, frame, cornerRadius,
  opacity, hidden, disabled, help, generic actionID, and the drag/drop reception
  modifiers `onHover` / `onDrop` / `onDropTargeted` (HTML5 DnD + pointer events;
  a dropped file's bytes ride along in a web-only `files` context field so the
  host can upload) (`ModifierResolver.js`), the element-level presentation
  modifiers - `sheet` / `fullScreenCover` (a native `<dialog>`) and `popover`
  (a top-layer panel), each opened off the carrier's own state
  (`Helpers/PresentationModifier.js`, `Helpers/PopoverPlacement.js`),
  shared stack vocabulary (`StackAxis.js`),
  console logger (`ConsoleLogger.js`), and `<key>:<platform>` override
  resolution (`PlatformFilter.js`, active token `web`, run over the JSON before
  the tree is built).
- **Elements** (`src/Views/`, one file per type): VStack, HStack, ZStack,
  Spacer, Divider, Text, Button, TextField, Toggle (switch + checkbox styles),
  Image, AsyncImage, Label, Slider, Stepper, SecureField, Picker, ProgressView,
  DatePicker, ColorPicker, ScrollView, ScrollViewReader, LazyVStack, LazyHStack,
  Grid, LazyVGrid, LazyHGrid, Form, Section, GroupBox, LabeledContent,
  DisclosureGroup, TextEditor, Gauge,
  the shape primitives Rectangle, RoundedRectangle, Capsule, Circle,
  Ellipse (shared fill/stroke resolution in `Helpers/ShapeStyleHelper.js`),
  TabView + Tab (a tab strip - or a left sidebar rail with
  `style: sidebarAdaptable` - with selection binding and badges),
  Menu (a pull-down of action items, with sections and dividers),
  List (a row collection; all three modes - heterogeneous children, homogeneous
  itemType, and the data-driven template repeater with `$1`/`$2` column
  references - with selection),
  Table (a multi-column data table driven by the rows API, with column resizing),
  NavigationStack + NavigationLink (a push/pop destination stack) and
  NavigationSplitView (a sidebar | (content) | detail layout - static panes, or a
  sidebar List whose `destinationViewId` rows switch the detail pane; both
  collapse responsively on narrow viewports), and
  LoadableView (a dynamic include - fetches a JSON sub-document by `url` /
  `filePath` / `name` and renders it inline, so a UI can be split across files),
  WebView (the web's own native `<iframe>`; `url` or inline `html`),
  VideoPlayer (a native `<video>`),
  Canvas (a native `<canvas>` driving the shared JSON `operations` draw-command
  list - fill/stroke/text/image, paths, gradients, transforms, clips, shadow/blur,
  layers - the same drawing rendering on SwiftUI and Compose),
  GeometryReader (a greedy box that fills its frame and reports its measured size to
  the host as `states["size"]`, read via `getElementState`),
  Map (a pluggable provider, the Android "link one module" model: the
  dependency-free default `src/Views/MapEmbed.js` is an OpenStreetMap embed + a
  platform-aware "Open in Maps" handoff, and importing `providers/map-maplibre.js`
  (key-free MapLibre), `providers/map-google.js` (Google Maps, `apiKey:web`), or
  `providers/map-apple.js` (Apple MapKit JS, `token:web`/`tokenURL:web`) after
  `ActionUI.js` swaps in a full map - markers + the user-pan value bridge - from the
  same JSON), and the
  structural/utility passthroughs Group (transparent, via `display:contents`),
  EmptyView, Link (a native `<a>`), ShareLink (the Web Share API), and
  ContentUnavailableView (an empty-state hero glyph + title + description).
  Each view's `validateProperties` warnings match the Swift
  contract (`ActionUI/Views/*.swift`) verbatim; deliberate omissions log console
  warnings.
- **Symbols** (`src/Helpers/MaterialSymbolResolver.js` + `Helpers/SymbolIcon.js`
  + `assets/symbols/`): a shared glyph path - `Image`, `Button`, and `Label` all
  render SF Symbols (`systemName`/`systemImage`) via the Android SF->Material map
  and Material Symbols (`materialName`) via the OFL Material Symbols web font
  (loaded by the host page; see `demo/index.html`).
- **API** (`src/ActionUI.js`): `Application` / `Window` classes mirroring
  `ActionUINodeJS/index.js` - `Window.fromURL/fromJSON`, `presentWindow`,
  `get/setString|Bool|Int|Double|Value`, `get/setState` (named element states,
  e.g. DisclosureGroup's `isExpanded`), the rows API for data-driven collections
  (`get/set/append/clearElementRows`, `getElementColumnCount` - sugar over the
  `content` state, used by Table and List's data-driven modes), the programmatic
  row-selection API for Table / data-driven List (`selectElementRow(index)`,
  `selectElementRowWithContent(text, column)`, `clearElementSelection` - silent,
  fires no actionID, like Apple), the window-level
  presentation host API (`src/Scenes/`): `presentAlert` /
  `presentConfirmationDialog` / `dismissDialog` (a native `<dialog>` from pure
  data) and `presentModal` / `dismissModal` (a JSON sub-document loaded into a
  sheet / `fullScreenCover` `<dialog>`, its controls bound into the window model),
  the file panel `openPanel(config)` (a hidden `<input type=file>`; async on web, so
  it returns a `Promise<File[]>` rather than the native synchronous path array -
  `File` objects carry their bytes for upload; `savePanel` is a deferred no-op),
  `setMenuBar` (an array-root `MainMenu.json` reinterpreted as a modern app bar -
  hamburger drawer + optional account menu - rendered by `Scenes/MenuBar.js`),
  multiple in-document `Window` surfaces from one `Application`
  (`getWindow`/`windowList`/`closeWindow`), `app.action(id, fn)`, and
  `setDefaultHandler`. Action handlers receive
  `(actionID, windowUUID, viewID, viewPartID, context)` as on all platforms.
- **Theme** (`theme.css`): tokenized CSS custom properties, macOS-flavored
  default skin, automatic dark mode via `prefers-color-scheme`.

## Layout mapping demonstrated

VStack/HStack -> flexbox (`spacing` -> `gap`, alignment -> `align-items`),
ZStack -> single-cell grid, Spacer -> `flex-grow: 1`,
`frame.maxWidth: "infinity"` -> `flex-grow` + `max-width: 100%`.

## Deferred

A short tail of perf/exotic work is intentionally left out. None of it affects
cross-platform parity for the shipped element surface.

- **`savePanel`** - no clean universal web mapping (a download needs the bytes up
  front, and the File System Access save picker is Chromium-only). `openPanel`
  ships; `savePanel` is a warn+null stub.
- **Tier 3 lazy virtualization (true windowing)** - opt-in `virtualized:web`.
  Tiers 1-2 (`content-visibility` for offscreen rows + a common-prefix row diff so
  append is O(tail)) ship for every row-bearing container; Tier 3 windowing is the
  only remaining piece, and the only path to Table laziness. Perf, not parity.
- **KeyframeAnimator / PhaseAnimator** - the `animation` modifier (an armed CSS
  transition that eases a later property mutation) ships; the multi-keyframe and
  multi-phase animators remain separate and deferred.
- **`onDrag` (drag initiation)** - excluded upstream by design; the drop-reception
  side (`onHover` / `onDrop` / `onDropTargeted`) ships.
