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
python3 -m http.server 8080 --protocol HTTP/1.1
# open http://localhost:8080/demo/
```

The `--protocol HTTP/1.1` matters off-localhost. The demo loads ~100 small ES module
files individually (no bundle, by design), and `http.server` defaults to HTTP/1.0 with
no keep-alive - so every file pays a fresh TCP handshake. On loopback that is invisible,
but over a higher-latency path (an Android emulator at `http://10.0.2.2:8080`, a phone
over Wi-Fi, a LAN IP) it dominates: a measured cold load on an emulator was ~13 s with
HTTP/1.0 vs ~1 s with HTTP/1.1 keep-alive (99 fresh connections vs 6 reused). The flag
needs Python 3.11+; with an older Python use any keep-alive server (`npx http-server`,
`npx serve`, `caddy file-server`).

For an emulator, point the browser at `http://10.0.2.2:8080/demo/` (the emulator's alias
for the host loopback - `127.0.0.1` there is the emulated device itself), or run
`adb reverse tcp:8080 tcp:8080` to keep using `http://127.0.0.1:8080/demo/`.

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
  Chart has no web renderer: it draws a "Chart Unavailable" placeholder and keeps
  the value, the rows API and the `chart` property, so Apple host code runs
  unchanged.
  Each view's `validateProperties` checks the properties the Swift renderer
  reads (`ActionUI/Core/Elements/*.swift` and `ActionUI/Views/*.swift`) and logs a console warning for one it ignores;
  deliberate omissions log console warnings too.
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

## Known layout differences from SwiftUI

SwiftUI on macOS is the reference. The layout parity fixtures (`../LayoutParity/`) record its
frames, and `ActionUITests/Views/WebLayoutParityTests.swift` checks this renderer against them.
The web renderer lays out with CSS alone, and these differences remain where CSS flexbox shares
space differently from SwiftUI's stacks:

- **A flexible view's minimum is added to its share.** SwiftUI offers each flexible child an
  even share of the stack, raises a child whose minimum is larger to that minimum, and shares
  the rest among the others. Flexbox starts each child at its minimum (`flex-basis: auto`) and
  splits what is left evenly on top of it.
  - An HStack 200 wide holding a Color and a Color with `minWidth` 150: SwiftUI gives 50 and
    150, the web 25 and 175 (`hstack-larger-minimum-first`).
  - An HStack 400 wide holding an HStack of a capped Color and a Spacer, beside a Color:
    SwiftUI gives 200 and 200, the web 204 and 196, the Spacer's minimum of 8 counted twice
    (`nested-unbounded-spacer`).
  - A VStack 60 tall holding an HStack with a Divider (which fills the height) and a Color:
    SwiftUI gives 30 and 30, the web 40 and 20 (`divider-hstack-height`).
  - `flex-basis: 0` would share like SwiftUI here, but it collapses a filling child that has
    padding (a List) to nothing in a stack sized by its content.
- **A stack offered its ideal size, or a little more, gives each child its own.** An HStack 107
  wide holding Colors with `minWidth` 38 and 31 and ideal and largest widths 51 and 44, 12 apart:
  SwiftUI offers each an even share of what is left and gives 47 and 44, centered; flexbox gives
  51 and 44 (`hstack-ideal-exact-width`, and aligned by the frame: `hstack-ideal-exact-width-leading`,
  `vstack-ideal-exact-height-top`). 110 wide, SwiftUI gives 49 and
  44 (`hstack-ideal-slightly-wider`). Offered at least 114, where the first even share covers 51
  (as a VStack 400 wide offers its width), SwiftUI gives 51 and 44 too.
- **A safe area inset is not laid out along its edge.** SwiftUI's safeAreaInset puts the inset
  view along its edge, `safeAreaSpacing` (8 by default) from the content and aligned by
  `safeAreaAlignment`, and gives the content the rest: in a VStack 200 tall, a filling Color
  takes 152 above a bar 40 tall. Here filling content is not drawn, and a bar beside fixed content
  is drawn over it at the same place (`safearea-bottom-filling`, `safearea-bottom-fixed`,
  `safearea-bottom-spacing`, `safearea-capped-content`, `safearea-capped-width-leading`,
  `safearea-fixed-filling-bar`, `safearea-hstack-share`, `safearea-inset-wider`,
  `safearea-leading-filling`, `safearea-scroll-list`, `safearea-top-aligned`,
  `safearea-unframed-bar`). A view that ignores the safe area does not reach into the inset's room
  either, where SwiftUI's background or overlay with ignoresSafeArea reaches through the room on
  the edge it ignores when it touches the frame's edge there (a Color covers the room, a view of
  fixed size aligned to that edge grows to the element's edge) (`ignoressafearea-background-under-inset`, `ignoressafearea-overlay-under-inset`,
  `ignoressafearea-other-edge`, `ignoressafearea-child-under-inset`, `ignoressafearea-fixed-at-edges`,
  `ignoressafearea-fixed-bottom`, `ignoressafearea-fixed-centered`).
- **A view's own padding is a floor under its share.** In an HStack 600 wide, a
  ContentUnavailableView beside a Color gets 316 on the web where SwiftUI shares 300 and 300
  (`contentunavailable-width-600`): flexbox never shrinks a box below its padding.
- **A stack holding a Text has no size limit.** A stack whose children all stop growing
  somewhere (a frame's `maxWidth`, a fixed size) stops growing there too, as in SwiftUI. A Text's
  size depends on its font and the width it wraps at, so a stack that holds one is never given a
  limit, and it grows where SwiftUI's stops (a titled LabeledContent with a child framed to
  `maxHeight` 20 is 38 tall in a 60-tall VStack, against SwiftUI's 20).
- **A Group's modifiers apply to the Group as a whole.** SwiftUI applies a Group's padding,
  frame and paint to each child, which stays in the parent stack: in an HStack, a Group padded
  10 holding two 20-wide Colors puts them at 10 and 50. The web puts them on one box around the
  Group, which then stacks its children in a column (`group-padding-per-child`,
  `group-frame-per-child`, `group-frame-ideal-hstack`). A Group with no such modifiers matches.
- **A Form is a single column.** macOS lines a Form's labels up in a trailing-aligned column with
  the content beside it; the web stretches each LabeledContent row and puts its content at the
  trailing edge. A macOS Form is also as wide as its rows and centered like a VStack, where the
  web's fills its parent's width (`form-rows-hug`, `form-sections-add-no-space`,
  `form-filling-row`). An empty control title makes a column of 0 on macOS, so every row starts 8
  points in; on the web there is no column (`form-empty-control-title`,
  `form-empty-text-field-title`), nor for the titled controls inside a stack row, which macOS lines
  up too (`form-nested-title-in-hstack`, `form-nested-titles-average`). A macOS Form row also puts
  its title on its content's first text baseline, so beside a Color the row is the title's descent
  taller (`form-title-on-content-bottom`, `form-titled-rows-on-baselines`), and a row with text
  sits 5 points below a row without, not 8 (`form-text-row-spacing`).
- **A view without text lines up by CSS's baseline.** In an HStack on `firstTextBaseline`,
  SwiftUI lines a view without text up by its bottom, also a filling view, a framed one and a stack
  holding no text; CSS gives such a box a baseline of its own, so it sits elsewhere
  (`hstack-baseline-expanding`, `hstack-baseline-frame-bottom`,
  `hstack-baseline-stack-without-text`). Plain Colors of different heights match.
- **A ScrollView sizes like a flex box.** SwiftUI's ScrollView shares space along its scroll
  axis like a Color, takes its content's size across it, and gives the content its ideal length
  along the axis (an unframed Color is 10) and the ScrollView's size across. On the web its share
  along the axis grows with its content (250 of 400 beside a Color in
  `scrollview-horizontal-in-hstack`, 175 of 300 in `scrollview-vertical-in-vstack`, where SwiftUI
  shares the space equally), the content is not offered the ScrollView's size across the axis,
  and an unframed Color in it is not drawn in a vertical ScrollView and fills the rest of a
  horizontal one, where SwiftUI makes it 10 long (`scrollview-vertical-content`,
  `scrollview-vertical-expanding-content`, `scrollview-horizontal-content`).
- **A GeometryReader sizes like a flex box.** SwiftUI's GeometryReader shares a stack like a Color
  and offers its content its whole size; on the web its share grows with its content (250 of 400
  beside a Color in `geometry-in-hstack-shares`, 175 of 300 in `geometry-in-vstack-shares`, where
  SwiftUI shares the space equally), and flexible content in it is not drawn
  (`geometry-fills-with-flexible-content`). In a ScrollView SwiftUI's reader is its ideal 10 points
  long, its content overflowing from its top leading corner; on the web it takes its content's
  length and centers it (`geometry-in-scrollview`). Fixed-size content at any alignment matches.
- **LazyVGrid and LazyHGrid lay out differently.** SwiftUI gives fixed columns (rows of a
  LazyHGrid) their width, shares the rest among flexible ones 8 points apart, makes a flexible cell
  fill its column and its row and centers each cell in its row (column of a LazyHGrid). On the
  web a cell without a width (height in a LazyHGrid), such as an unframed Color, is not drawn, the
  tracks are not 8 points apart and their block starts at the leading (top) edge, a cell sits at
  the start of its row, and the cells' `content-visibility: auto` (44 point placeholder size)
  leaves every cell of some grids undrawn (`lazyvgrid-*`, `lazyhgrid-*`).
- **A Grid's flexible cells collapse.** SwiftUI shares a Grid's width among its columns and its
  height among its rows as a stack shares its length, and a flexible cell (a Color without a
  frame) fills its column and row; a Grid with one shares its parent stack like a Color. On the
  web the Grid's tracks are sized by their content, so such a cell is not drawn, the other cells
  sit closer together, and the Grid takes only its fixed cells' size in a stack
  (`grid-flexible-cell`, `grid-flexible-lines`, `grid-in-hstack-shares`). A Spacer or a Divider
  in a Grid is such a cell (`grid-spacer-column-last`, `grid-spacer-row-last`,
  `grid-spacer-explicit-spacing`, `grid-spacer-mixed-lines`, `grid-divider-in-row`). An EmptyView
  also keeps a cell, and a row of only EmptyViews a row and its spacing, where SwiftUI gives it
  none (`grid-emptyview-takes-no-cell`, `grid-emptyview-row-takes-no-row`). Grids of fixed-size
  cells match.
- **A non-uniform scale with a rotation** scales before it rotates (CSS's order for the
  independent `rotate` and `scale` properties), where SwiftUI rotates first. Each alone, and a
  uniform scale with a rotation, match.

The first three would need the layout computed in JavaScript: measure each stack's children and
set their sizes with SwiftUI's sharing rules, as the GTK renderer's `StackSolver` does, instead of
leaving the sharing to flexbox. That is not done. It would take over the browser's layout of every
stack, add a measuring pass on every resize and content change, and the differences are a few
points in uncommon arrangements.

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
- **`onDrag` (drag initiation)** - excluded upstream by design; the drop-reception
  side (`onHover` / `onDrop` / `onDropTargeted`) ships.
