---
name: actionui
description: >
  Generate and validate ActionUI JSON for macOS and iOS native UI. Use when the user asks to design, create, edit, fix, or verify ActionUI JSON files, or asks about ActionUI elements, properties, or layout.
version: "1.2"
---

# ActionUI Skill


## What is ActionUI

ActionUI is a Swift framework that renders native SwiftUI views from a declarative JSON tree. A JSON file describes a view hierarchy; ActionUI parses it and produces live native UI on macOS and iOS. No Swift code is needed to define the UI — only valid JSON.

## JSON Node Structure

Every node in the tree follows this shape:

```json
{
  "type": "VStack",
  "id": 1,
  "properties": { "spacing": 16, "padding": 20 },
  "children": [
    { "type": "Text", "properties": { "text": "Hello" } },
    { "type": "Button", "id": 2, "properties": { "title": "Tap", "actionID": "tap" } }
  ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `type` | string | **Required.** Element type, case-sensitive. |
| `id` | integer | Optional. Positive non-zero integer, unique across the entire file. Needed for runtime API calls. |
| `properties` | object | Element-specific properties plus inherited View modifiers. |
| container keys | array/object | Element-specific structural keys outside `properties`: `children`, `content`, `destinations`, `template`, `rows`. |

**Never put container keys (`children`, `content`, etc.) inside `properties`.**

## Core Generation Rules

1. `type` is always a string. Element type names are PascalCase and case-sensitive (`VStack`, not `vstack`).
2. `id` must be a positive non-zero integer. IDs must be unique across the entire JSON file. Omit `id` when no runtime interaction is needed.
3. Children arrays (`children`, `destinations`, `rows`) are **top-level keys** on the element node — never inside `properties`.
4. A single child view (`content`) is a JSON object, not an array.
5. Property values must match the declared type. Common mistake: `"spacing": "16"` (string) instead of `"spacing": 16` (number).
6. Do not invent property names. Only use properties defined in the element schema or the universal View base properties.



## SwiftUI Alignment

ActionUI property names and values **exactly match SwiftUI modifier names**. If you know SwiftUI, you already know ActionUI: `foregroundStyle`, `font`, `padding`, `frame`, `clipShape`, `cornerRadius`, `shadow`, `rotationEffect`, `scaleEffect`, `animation` — all spelled and valued the same way as their SwiftUI counterparts.

The JSON tree mirrors the SwiftUI view hierarchy. Container views (`VStack`, `HStack`, `List`, `NavigationStack`) correspond directly to their SwiftUI equivalents. Modifier application order follows SwiftUI conventions.

When in doubt about a property name or value, ask: "what does SwiftUI call this?" — the answer is the ActionUI property name.



## Universal View Properties

All elements inherit these `properties` keys. None are required.

### Layout

| Property | Type | Notes |
|----------|------|-------|
| `padding` | number \| `"default"` \| `{top?,leading?,bottom?,trailing?}` | |
| `frame` | `{width?,height?,alignment?}` OR `{minWidth?,idealWidth?,maxWidth?,minHeight?,idealHeight?,maxHeight?,alignment?}` | Two mutually exclusive forms. Use `"infinity"` for `.infinity`. |
| `offset` | `{x?,y?}` | Relative position in points |
| `hidden` | boolean | Invisible, non-interactive, but STILL LAID OUT - the space is reserved on every platform. No collapse semantic; see the ZStack panel switcher. In a toolbar it removes the item instead. |
| `zIndex` | number | Z-order within container |

### Appearance

| Property | Type | Notes |
|----------|------|-------|
| `foregroundStyle` | color | Text/icon color. Hex `#RRGGBB[AA]`, named (`red`, `blue`, etc.), or semantic (`primary`, `secondary`, etc.) |
| `tint` | color | Interactive control tint (buttons, toggles, sliders) |
| `background` | color | Background fill (string form). Use `background` top-level key for a view background. |
| `opacity` | number | 0.0–1.0 |
| `font` | string \| `{name?,size,weight?,design?}` | Named styles: `largeTitle title title2 title3 headline subheadline body callout footnote caption caption2`. Weight values: `ultraLight thin light regular medium semibold bold heavy black`. |
| `cornerRadius` | number | |
| `clipShape` | `"circle"` \| `"capsule"` \| `"rectangle"` \| `"ellipse"` \| `{type:"roundedRectangle",cornerRadius?}` | |
| `shadow` | `{color?,radius?,x?,y?}` | |
| `border` | `{color?,width?}` | |
| `multilineTextAlignment` | `"leading"` \| `"center"` \| `"trailing"` | Applies to Text; propagates to child Text views on containers |

### Transform

| Property | Type | Notes |
|----------|------|-------|
| `rotationEffect` | number | Degrees; positive = clockwise |
| `scaleEffect` | number \| `{x?,y?,anchor?}` | |
| `animation` | string \| `{curve,duration?,delay?,speed?,value?}` | Curves: `default linear easeIn easeOut easeInOut spring bouncy smooth snappy interactiveSpring` |

### Interaction

| Property | Type | Notes |
|----------|------|-------|
| `actionID` | string | Tap/click action. On `VStack`/`HStack`/`ZStack` it makes the WHOLE container tappable - the rich-cell idiom; see 08-patterns.md |
| `valueChangeActionID` | string | Fires when observable value changes |
| `onAppearActionID` | string | |
| `onDisappearActionID` | string | |
| `onHoverActionID` | string | macOS/iPadOS with pointer |
| `onDropTypes` | string[] | UTType ids; required alongside `onDropActionID` |
| `onDropActionID` | string | Drop target handler |
| `onDropTargetedActionID` | string | Visual feedback during drag-over |
| `keyboardShortcut` | `{key, modifiers?}` | Modifiers array: `command shift option control capsLock` |
| `disabled` | boolean | |

### Control Styling

| Property | Type | Notes |
|----------|------|-------|
| `buttonStyle` | `automatic` \| `plain` \| `borderless` \| `bordered` \| `borderedProminent` | Propagates to child buttons when set on a container |
| `controlSize` | `mini` \| `small` \| `regular` \| `large` \| `extraLarge` | |
| `labelsHidden` | boolean | Hides labels on child form controls |

### Universal Subview Keys (top-level, not in `properties`)

Any element may also have these top-level keys for overlay/modal presentation:

| Key | Value | Notes |
|-----|-------|-------|
| `overlay` | element node | Rendered on top |
| `background` | element node | Rendered behind (view form) |
| `sheet` | element node | Modal sheet |
| `popover` | element node | Popover |
| `fullScreenCover` | element node | Full-screen modal |
| `toolbar` | array of ToolbarItem/ToolbarItemGroup | |



## Validation

After generating or modifying ActionUI JSON, always validate before presenting the result:

```bash
python3 Skill/scripts/validate_actionui.py <file-or-directory>
```

Fix all `[ERROR]` issues before presenting. `[WARNING]` lines are likely typos or unsupported properties — investigate and fix if possible. `[INFO]` lines are informational only.

Common errors:
- Unknown property name → typo or hallucinated property; check the element schema
- Wrong value type → e.g., `"spacing": "16"` should be `"spacing": 16`
- Duplicate `id` → change one of the conflicting IDs
- Missing required property → add the required field
- Unknown element `type` → check the spelling; types are PascalCase

Full element documentation is in `docs/Schemas/<Type>.md`. Read the relevant schema when unsure about a property name or value.



## Element Quick Reference

Element type names are PascalCase. For full property documentation read `docs/Schemas/<Type>.md`; for a ready-to-use template read `docs/Elements/<Type>.json`. See `docs/ActionUI-Elements.md` for the complete index.

### Layout Containers

| Type | Key properties | Children |
|------|---------------|----------|
| `VStack` | `spacing`, `alignment` (leading/center/trailing) | `children` array |
| `HStack` | `spacing`, `alignment` (top/center/bottom/firstTextBaseline/lastTextBaseline) | `children` array |
| `ZStack` | `alignment` (topLeading, center, bottomTrailing, etc.) | `children` array |
| `LazyVStack` | `spacing`, `alignment`, `pinnedViews` | `children` array |
| `LazyHStack` | `spacing`, `alignment` | `children` array |
| `ScrollView` | `axis` (vertical/horizontal/both), `showsIndicators` | `content` (single view) |
| `Group` | — | `children` array |
| `GroupBox` | `title` | `children` array |
| `GeometryReader` | — | `children` array |

### Grid

| Type | Key properties | Children |
|------|---------------|----------|
| `Grid` | `spacing`, `alignment`, `horizontalSpacing`, `verticalSpacing` | `rows` (2-D array of cell elements) |
| `LazyVGrid` | `columns` (GridItem array), `spacing` | `children` array |
| `LazyHGrid` | `rows` (GridItem array), `spacing` | `children` array |

### Navigation

| Type | Key properties | Children |
|------|---------------|----------|
| `NavigationStack` | — | `content` (single view), `destinations` array |
| `NavigationSplitView` | `style` | `sidebar`, `content`, `detail` (each single view) |
| `NavigationLink` | `title`, `destinationViewId` (Form 2), `actionID` | `content` (custom label) |
| `TabView` | `actionID` | `children` array of `Tab` nodes |
| `Tab` | `title`, `systemImage`, `actionID` | `content` (single view) |

### Lists and Forms

| Type | Key properties | Children |
|------|---------------|----------|
| `List` | `listStyle`, `actionID`, `doubleClickActionID`, `itemType` | `children` array or `template` |
| `Form` | — | `children` array |
| `Section` | `header`, `footer` | `children` array |
| `Table` | `columns` (array of column defs) | `rows` (2-D array of cell values) |
| `DisclosureGroup` | `label`, `isExpanded`, `actionID` | `children` array |

### Text and Display

| Type | Key properties | Notes |
|------|---------------|-------|
| `Text` | `text`, `markdown` | `markdown` takes precedence |
| `Image` | `systemName`, `assetName`, `resourceName`, `filePath`, `contentMode`, `resizable` | One source property required |
| `Label` | `title`, `systemImage` | SF Symbol label |
| `Divider` | — | |
| `Spacer` | `minLength` | |
| `ProgressView` | `style` (circular/linear), `value`, `total`, `title` | |
| `Gauge` | `value`, `min`, `max`, `title`, `label`, `currentValueLabel` | |
| `Canvas` | `operations` (array), `backgroundColor`, `coordinateMode` | Drawing surface |

### Input Controls

| Type | Key properties | Value type |
|------|---------------|-----------|
| `Button` | `title`, `systemImage`, `role` (destructive/cancel), `actionID` | — |
| `Toggle` | `title`, `actionID` | boolean |
| `Slider` | `range: {min,max}`, `step`, `title`, `actionID` | number |
| `Stepper` | `range: {min,max}`, `step`, `title`, `actionID` | number |
| `Picker` | `title`, `pickerStyle`, `actionID` | string (selected label) |
| `DatePicker` | `title`, `displayedComponents`, `actionID` | string (ISO 8601 date) |
| `ColorPicker` | `title`, `actionID` | string (hex color) |
| `TextField` | `title`, `actionID`, `keyboard` | string |
| `SecureField` | `title`, `actionID` | string |
| `TextEditor` | `actionID` | string |

### Overlays and Modals (top-level keys, not `properties`)

`overlay`, `background` (view), `sheet`, `popover`, `fullScreenCover`, `toolbar`

`persistentToolbar` - on `NavigationStack` / `NavigationSplitView` only: toolbar items that stay in the bar on every screen inside the container. A `toolbar` on those two types is a deprecated alias for it. Implemented on all four hosts.

### Shapes

`Circle`, `Ellipse`, `Rectangle`, `RoundedRectangle`, `Capsule` — accept View base properties (foregroundStyle, frame, etc.)

### Special

| Type | Notes |
|------|-------|
| `Link` | `url`, `title`, `actionID` |
| `ShareLink` | `item`, `subject`, `message` |
| `Menu` | `title` | `children` (button list); optional `label` top-level for a custom trigger view |
| `ControlGroup` | `style` | `children` array |
| `LabeledContent` | `label`, `value` |
| `ScrollViewReader` | Wraps a ScrollView; `actionID` for scroll-to |
| `Map` | `latitude`, `longitude`, `span` |
| `WebView` | `url` |
| `VideoPlayer` | `url` |
| `AsyncImage` | `url`, `contentMode` |
| `LoadableView` | `actionID`, `loadingView`, `errorView` | `content` (single view) |
| `ContentUnavailableView` | `title`, `systemImage`, `description` |
| `PhaseAnimator` | `phases`, `trigger` | `content` (single view) |
| `KeyframeAnimator` | `trigger` | `content` (single view) |
| `EmptyView` | — | |
| `HSplitView` / `VSplitView` | macOS split pane | `children` array |
| `ToolbarItem` | `placement` | `content` (single view) |
| `ToolbarItemGroup` | `placement` | `content` (single view) |



## Real-World Patterns

Patterns observed in production ActionUI apps. Use these as building blocks.

### Window sizing (macOS)

Set `minWidth`/`minHeight` + `idealWidth`/`idealHeight` on the root frame. The window opens at ideal and respects the minimum.

```json
"frame": { "minWidth": 860, "minHeight": 500, "idealWidth": 980, "idealHeight": 620 }
```

### File decomposition with LoadableView

Large apps split UI across multiple JSON files loaded on demand. Each tab or section references its own file:

```json
{
  "type": "TabView",
  "properties": { "style": "sidebarAdaptable", "frame": { "minWidth": 860, "minHeight": 500, "idealWidth": 980, "idealHeight": 620 } },
  "children": [
    { "type": "Tab", "properties": { "title": "General", "systemImage": "info.circle" },
      "content": { "type": "LoadableView", "properties": { "name": "General.json", "viewDidLoadActionID": "app.general.loaded" } } },
    { "type": "Tab", "properties": { "title": "Settings", "systemImage": "gear" },
      "content": { "type": "LoadableView", "properties": { "name": "Settings.json", "viewDidLoadActionID": "app.settings.loaded" } } }
  ]
}
```

`viewDidLoadActionID` fires when the view finishes loading so the app can populate it with data.

### Toolbar with ToolbarItem / ToolbarItemGroup

Use the `toolbar` top-level key (not inside `properties`) on any view to attach toolbar items. `ToolbarItem` holds a single `content` view; `ToolbarItemGroup` holds multiple items under `children`.

One exception: on a `NavigationStack` or `NavigationSplitView`, `toolbar` is a DEPRECATED spelling of `persistentToolbar` and logs a warning. Put a screen's toolbar on that screen's own element (the stack's `content`, or a destination); use `persistentToolbar` on the container only for items that must stay in the bar on EVERY screen inside it, such as a global status indicator. Those items cost bar space on every screen, so keep them to one or two. Implemented on all four hosts.

```json
{
  "type": "List",
  "id": 1,
  "properties": { "navigationTitle": "Inbox", "actionID": "list.selection.changed" },
  "children": [...],
  "toolbar": [
    {
      "type": "ToolbarItem",
      "id": 10,
      "properties": { "placement": "topBarLeading" },
      "content": {
        "type": "Button",
        "id": 100,
        "properties": { "title": "Edit", "actionID": "toolbar.edit" }
      }
    },
    {
      "type": "ToolbarItemGroup",
      "id": 11,
      "properties": { "placement": "topBarTrailing" },
      "children": [
        { "type": "Button", "id": 110, "properties": { "systemImage": "line.3.horizontal.decrease.circle", "actionID": "toolbar.filter" } },
        { "type": "Button", "id": 111, "properties": { "systemImage": "square.and.pencil", "actionID": "toolbar.compose" } }
      ]
    }
  ]
}
```

Common `placement` values: `topBarLeading`, `topBarTrailing`, `navigationBarLeading`, `navigationBarTrailing`, `principal`.

### Master-detail with HSplitView

Left panel: `minWidth` + `idealWidth`. Right panel: `maxWidth: "infinity"`.

```json
{
  "type": "HSplitView",
  "children": [
    {
      "type": "VStack",
      "properties": { "spacing": 0, "frame": { "minWidth": 240, "idealWidth": 300, "maxHeight": "infinity" } },
      "children": [
        { "type": "Table", "id": 1, "properties": { "columns": ["Item"], "widths": [280], "actionID": "item.selected" } }
      ]
    },
    { "type": "VStack", "properties": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity" } }, "children": [] }
  ]
}
```

### NavigationSplitView sidebar column width

Set sidebar width on the sidebar's **root view** via `navigationSplitViewColumnWidth`, not on the NavigationSplitView itself:

```json
{
  "type": "NavigationSplitView",
  "properties": { "style": "balanced", "frame": { "minWidth": 800, "minHeight": 600 } },
  "sidebar": {
    "type": "VStack",
    "properties": { "navigationSplitViewColumnWidth": { "min": 220, "ideal": 280, "max": 360 } },
    "children": [...]
  },
  "detail": { ... }
}
```

### ZStack panel switcher

Overlay multiple panels, all hidden initially. The app reveals the correct one by ID based on selection. This is the pattern for inspectors and context-sensitive detail panes.

This is the idiom *because* `hidden` reserves layout space on every platform (SwiftUI `.hidden()` semantics) - there is no collapse semantic, so hiding a panel in a VStack would leave its gap behind. Overlaying them in a ZStack means the panels share one slot and only the visible one shows. Give the ZStack the size you want the slot to have.

```json
{ "type": "ZStack", "children": [
  { "type": "VStack", "id": 500, "properties": { "hidden": true }, "children": [...] },
  { "type": "VStack", "id": 501, "properties": { "hidden": true }, "children": [...] }
]}
```

### Inspector panel: stacked GroupBoxes

Group related fields in separate `GroupBox` elements. Inside each: `VStack(alignment: leading)` → zero-height invisible `Divider` (adds visual gap at top of the Form) → `Form`.

```json
{ "type": "GroupBox", "properties": { "title": "Color" }, "children": [
  { "type": "VStack", "properties": { "alignment": "leading" }, "children": [
    { "type": "Divider", "properties": { "opacity": 0, "frame": { "height": 0 } } },
    { "type": "Form", "children": [
      { "type": "Picker", "id": 1, "properties": {
        "title": "Fill",
        "options": [{"title": "None", "tag": "none"}, {"title": "Solid", "tag": "solid"}],
        "actionID": "color.fill.changed"
      }}
    ]}
  ]}
]}
```

The invisible Divider trick adds top padding inside a Form where regular padding doesn't work well.

### Aligned label-field rows (without Form)

Fixed-width trailing-aligned `Text` label + stretching `TextField`:

```json
{ "type": "HStack", "properties": { "spacing": 8 }, "children": [
  { "type": "Text", "properties": { "text": "Bundle ID", "frame": { "width": 110, "alignment": "trailing" } } },
  { "type": "TextField", "id": 1, "properties": { "prompt": "com.example.app", "actionID": "bundleid.changed" } }
]}
```

Use consistent label widths across all rows for column alignment.

### Picker options with title + tag

Use `{title, tag}` objects when the display label should differ from the value delivered to the action handler:

```json
"options": [
  {"title": "Script File", "tag": "exe_script_file"},
  {"title": "AppleScript", "tag": "exe_applescript"},
  {"title": "Terminal", "tag": "exe_terminal"}
]
```

### Dialog OK/Cancel with keyboard shortcuts

```json
{ "type": "HStack", "children": [
  { "type": "Spacer" },
  { "type": "Button", "properties": { "title": "Cancel", "buttonStyle": "bordered",
      "keyboardShortcut": { "key": "escape" }, "actionID": "dialog.cancel" } },
  { "type": "Button", "id": 99, "properties": { "title": "Create", "buttonStyle": "borderedProminent",
      "keyboardShortcut": { "key": "return" }, "actionID": "dialog.confirm" } }
]}
```

### TextEditor as log/output view

Read-only monospaced output area with secondary background:

```json
{ "type": "TextEditor", "id": 1, "properties": {
  "font": { "size": 11, "design": "monospaced" },
  "background": "background.secondary",
  "scrollContentBackground": "hidden",
  "readOnly": true,
  "frame": { "minHeight": 200, "idealHeight": 300 }
}}
```

### Drag-and-drop on Table

```json
{ "type": "Table", "id": 1, "properties": {
  "onDropTypes": ["public.file-url", "public.folder"],
  "onDropActionID": "files.dropped"
}}
```


### Runtime value semantics (what action handlers actually receive)

Verified against the live runtime — getting these wrong produces silent
no-ops that are very hard to debug from the JSON alone:

- **Picker** (segmented, menu, …): the observable value and the action's
  trigger context are the **1-based option index** ("1", "2", …), not the
  option title. Setting the value programmatically also takes the index —
  setting it to an option's title is a silent no-op. Keep the ordered option
  list available to handlers so they can map index → name.
- **TabView**: the `actionID` delivers the **0-based tab index** as trigger
  context.
- Programmatic `options`/value updates can fire the control's
  `actionID`/`valueChangeActionID` with transitional or bogus values —
  handlers must validate what they receive.

### Whole-cell tap: a rich row that is ONE tap target

Put `actionID` on the `VStack`/`HStack`/`ZStack` itself and the whole container
becomes tappable. This is how you build a cell that is an avatar, a name and a
status line rather than a small glyph `Button` wedged inside one: `Button`
renders title + `systemImage` only, so it can never BE the rich cell.

```json
{
  "type": "VStack", "id": 900,
  "template": {
    "type": "HStack",
    "properties": { "actionID": "receiver.open", "padding": 8, "frame": { "maxWidth": "infinity" } },
    "children": [
      { "type": "Image", "properties": { "systemName": "$1" } },
      { "type": "Text",  "properties": { "text": "$2" } },
      { "type": "Spacer" },
      { "type": "Button", "properties": { "title": "Done", "actionID": "receiver.done" } }
    ]
  }
}
```

What the handler receives:

- **Inside a `template` row**: `viewID` is the owning container's id (900 here)
  and `viewPartID` is the row index, exactly as for a `Button` in the same row.
  A template instance's own id is 0 and identifies nothing, so this is the only
  way a data-driven cell can say which row was tapped.
- **Outside a template**: the element's own id, with `viewPartID` 0.

A `Button` (or any control) nested inside keeps its own tap: pressing "Done"
fires `receiver.done` and does NOT also fire `receiver.open`. The same holds for
a tappable container nested inside another one, and for a tappable cell inside a
selectable `List` row - the innermost action wins and nothing else fires.

The target covers the container's FINAL box, `padding` and `frame` included, so
give the cell a `padding` when you want the gaps around the children to be part
of the tap area. An unpadded stack hugs its content, and the space between
children is still inside the box.

Accessibility comes with it on all three hosts: the cell is announced as a
single button reading its children's labels, and it is reachable by keyboard
(Enter or Space on the web, where a plain container would otherwise be
unreachable). That is the reason to prefer this over a leading-glyph `Button` -
one focusable element with one action, instead of a small target beside inert
text.

A `disabled: true` container is inert and gets no tap target, and so is one
inside a disabled ancestor.

Web note: on the web ANY element carrying an `actionID` is clickable, not only
these three containers - that predates the pattern and still holds. Apple and
Android wire only `VStack`/`HStack`/`ZStack`, so keep the `actionID` on one of
them if the document has to behave identically everywhere.

### Table column minimum widths

Always declare `minWidths` alongside `widths` — the default per-column
minimum is 10 pt, which lets columns collapse into unreadable slivers when
the window shrinks:

```json
"widths":    [36, 190, 270],
"minWidths": [16, 160, 100]
```

### Two container-key mistakes the validator catches late

- `GroupBox` content goes in `children` (an array) — there is no `content`
  key on GroupBox.
- `NavigationSplitView` requires `sidebar` **and** `detail`; a lone
  `sidebar` + `content` pair (without `detail`) is invalid — `content` is
  only the optional middle pane of a three-column split.



## Reference Documents

This skill package includes a `docs/` folder with full per-element documentation:

- `docs/ActionUI-Elements.md` — complete element index (all types, with links)
- `docs/ActionUI-JSON-Guide.md` — JSON structure guide and layout reference
- `docs/ActionUI-MenuBar-JSON-Guide.md` — menu-bar JSON format (`MainMenu.json`): array root, `CommandMenu`/`CommandGroup` (delete via `replacing` with no children), Button/Divider children
- `docs/Schemas/<Type>.md` — full property specification for a specific element
- `docs/Elements/<Type>.json` — ready-to-use JSON template for a specific element

When a property isn't working as expected, when you need the complete property list for an element, or when your SwiftUI knowledge of a modifier may be incomplete or outdated, read the relevant `docs/Schemas/<Type>.md` file. For a starting-point JSON snippet, use `docs/Elements/<Type>.json`. To customize the application menu bar (a document with an **array** root, distinct from a view), read `docs/ActionUI-MenuBar-JSON-Guide.md`.



*Generated by Skill/build_skill.py — edit Skill/master/content/*.md, not this file.*
