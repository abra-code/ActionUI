---
name: actionui
description: >
  Generate and validate ActionUI JSON for native UI on Apple platforms, Linux, Android and the web. Use when the user asks to design, create, edit, fix, or verify ActionUI JSON files, or asks about ActionUI elements, properties, or layout.
version: "1.2"
---

# ActionUI Skill


## What is ActionUI

ActionUI renders native UI from a declarative JSON tree: SwiftUI on Apple platforms, GTK/Adwaita on Linux, Jetpack Compose on Android, and the DOM on the web. A JSON document describes a view hierarchy; no UI code is needed, only valid JSON.

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
| `type` | string | **Required.** Element type, PascalCase, case-sensitive. |
| `id` | integer | Optional. Positive, unique across the whole document. Give one to every element the app reads, updates or handles events from. |
| `properties` | object | The element's own properties plus the universal View properties. |
| structural keys | array/object | Outside `properties`: `children`, `content`, `template`, `destination(s)`, `rows`, `sidebar`/`detail`, and the subview keys (`toolbar`, `sheet`, ...). |

## Core Generation Rules

1. Structural keys (`children`, `content`, `template`, ...) are top-level keys on the node, never inside `properties`.
2. `content` is a single view (an object); `children` is an array.
3. Values must have the declared type: `"spacing": 16`, not `"spacing": "16"`.
4. Do not invent property names. An unknown property is only a validator WARNING and is ignored at run time, so a typo fails silently: read every warning.



## SwiftUI Alignment

Property names and values follow SwiftUI's modifier names: `foregroundStyle`, `font`, `padding`, `frame`, `clipShape`, `shadow`, `rotationEffect`, `animation`, `transition` are spelled and valued as in SwiftUI, and the tree mirrors the SwiftUI view hierarchy. When unsure, ask what SwiftUI calls it.

The exceptions are where an element's JSON shape cannot follow a Swift initializer: the element notes below list the ones that trip agents up. Everything else is in the element's schema.



## Universal View Properties

Every element takes the SwiftUI-named modifiers in `properties` (`padding`, `frame`, `font`, `foregroundStyle`, `background`, `opacity`, `cornerRadius`, `clipShape`, `shadow`, `border`, `offset`, `zIndex`, `rotationEffect`, `scaleEffect`, `animation`, `transition`, `disabled`, `hidden`, `tint`, `buttonStyle`, `controlSize`, `labelsHidden`, `navigationTitle`, ...). The full list and values are in `docs/Schemas/View.md`. What differs from SwiftUI or fails silently:

- **`padding`**: a number, `"default"`, or `{top, leading, bottom, trailing}`.
- **`frame`**: either `{width, height, alignment}` or `{minWidth, idealWidth, maxWidth, minHeight, idealHeight, maxHeight, alignment}`, not a mix. `"infinity"` for `.infinity`.
- **`font`**: a text style name (`title`, `headline`, `body`, `caption`, ...) or `{size, weight, design}` (`"design": "monospaced"`).
- **Colors**: a SwiftUI name (`red`, `primary`, `secondary`, `accentColor`, `background`, `background.secondary`, `fill`, `separator`, `windowBackground`, ...), hex `#RRGGBB[AA]`, or `"<color>.opacity(0.5)"`. UIKit names (`systemBackground`, `label`) do not work.
- **`hidden`**: the view is invisible but still takes its space (SwiftUI `.hidden()`), on every platform. To swap panels, stack them in a `ZStack` and show one. In a toolbar, `hidden` removes the item.
- **`keyboardShortcut`**: `{key, modifiers}`. **Omitting `modifiers` means `["command"]`**: write `"modifiers": []` for a bare Return or Escape.

### Events: which key a control fires

Handlers get `(actionID, viewID, viewPartID, context)`. Use the key the control actually fires, or nothing happens (the validator does not check this):

- `actionID`: Button, Toggle, Picker, Stepper, ColorPicker, TabView, List and Table (selection), DisclosureGroup, Menu items, and `VStack`/`HStack`/`ZStack` (a tap on the whole box).
- `valueChangeActionID`: Slider, DatePicker, TextEditor, and a Chart's selection.
- TextField: `actionID` on submit (Return), `valueChangeActionID` on every edit.
- Tab, Link and NavigationLink fire no action of their own.
- Also: `onAppearActionID`, `onDisappearActionID`, `onHoverActionID`, `doubleClickActionID` (List, Table), and drops: `onDropTypes` (UTType ids, required) with `onDropActionID`.

### Subview keys (top-level on the node, not in `properties`)

`overlay`, `background` (a view), `sheet`, `popover`, `fullScreenCover`, `toolbar`, `contextMenu` (with optional `contextMenuPreview`), `swipeActions`, `safeAreaInset`. On `NavigationStack` / `NavigationSplitView`, use `persistentToolbar` for items that stay on every screen; put a screen's own `toolbar` on that screen's view.

### Platform overrides

`"key:<platform>"` overrides one property on one platform: `"font:macos"`, `"padding:android"`. Platforms: `ios`, `macos`, `tvos`, `watchos`, `visionos`, `apple`, `android`, `web`, `linux`. In a document meant for several platforms, a property only one platform supports should carry its suffix, or the validator warns. The suffix also works on `type`: an element typed only for some platforms (`"type:apple": "Toggle"` and no `type`) is left out elsewhere, taking no space (`hidden` keeps the space); the root needs a `type` on every platform. Details: the JSON guide, "Per-Platform Property Overrides".



## Validation

After generating or modifying ActionUI JSON, always validate before presenting the result (the path is relative to this skill's folder):

```bash
python3 -B scripts/validate_actionui.py <file-or-directory>
```

Fix every `[ERROR]`. Treat every `[WARNING]` as a probable bug: an unknown property or value is only a warning, and the runtime ignores it, so the document "works" without doing what you wrote. `[INFO]` lines are informational.

Common causes: a misspelled or invented property (check the element's schema), a wrong value type (`"16"` for `16`), a duplicate `id`, a missing required property, a misspelled `type`.

The validator does not catch every mistake that matters: the element notes below list the ones it misses (event keys, `keyboardShortcut` modifiers, empty Picker tags).



## Visual Verification (Screenshot)

The validator catches schema errors, not clipped labels, wrapped titles or controls squeezed out of view. After validating, render the document and look at the image:

- With the ActionUI MCP server connected: its `screenshot` tool (macOS and Linux).
- Otherwise ActionUIViewer: `ActionUIViewer <file.json> --screenshot out.png`, adding `--hide-window` on macOS (renders off screen: no window on the desktop, no Screen Recording permission, works with the screen locked; the Linux viewer has no such flag). Add `--screenshot-delay 5` for WebView or VideoPlayer content.

Look for truncated or wrapping text, controls clipped at the window edge, overlaps, and empty space where an element should be. Panes the app fills at run time are empty in a preview; judge layout, not colors or tint. The viewer needs a logged-in GUI session: a run that prints nothing and never exits is usually a sandbox blocking the window server.



## Elements

Element types are SwiftUI's: stacks (`VStack`, `HStack`, `ZStack`, `LazyVStack`, `LazyHStack`), `ScrollView`, `Grid`/`LazyVGrid`/`LazyHGrid`, `List`, `Form`, `Section`, `Table`, `GroupBox`, `DisclosureGroup`, `NavigationStack`, `NavigationSplitView`, `TabView`/`Tab`, `HSplitView`/`VSplitView`, controls (`Button`, `Toggle`, `Picker`, `Slider`, `Stepper`, `DatePicker`, `ColorPicker`, `TextField`, `SecureField`, `TextEditor`), display (`Text`, `Label`, `Image`, `AsyncImage`, `ProgressView`, `Gauge`, `Divider`, `Spacer`, shapes, `Canvas`, `Chart`, `Map`, `WebView`, `VideoPlayer`), and `Menu`, `ControlGroup`, `LabeledContent`, `Link`, `ShareLink`, `ContentUnavailableView`, `LoadableView`. The index is `docs/ActionUI-Elements.md`; each element's properties are in `docs/Schemas/<Type>.md`.

### Where children go

- `children` (array): stacks, `Group`, `GroupBox`, `List`, `Form`, `Section`, `DisclosureGroup`, `TabView` (of `Tab`), `Menu`, `ControlGroup`, `LabeledContent`, split views, `ToolbarItemGroup`.
- `content` (one view): `ScrollView`, `ScrollViewReader`, `GeometryReader`, `Tab`, `ToolbarItem`, `NavigationStack` (plus `destinations`).
- `NavigationSplitView`: `sidebar` and `detail` are both required; `content` is only the optional middle column.
- `Grid`: `rows`, an array of rows, each an array of cell views.
- `template` (List, Section, GroupBox, DisclosureGroup, stacks): one view repeated per data row, with `"$1"`, `"$2"` reading the row's columns.

### Rows come at run time

A `Table`'s rows and a `template`'s rows are never in the document: the application sends them after the window opens. A `Table` needs `columns` (the header titles); give `minWidths` with `widths`, or columns can shrink to slivers.

### Names that differ from SwiftUI (each is a common mistake)

- `Picker`: `options` is a list of strings or `{title, tag}` objects. Its value is the `tag`; plain strings get tags `"1"`, `"2"`, ... (1-based). An option whose `title` or `tag` is empty is silently dropped: give a "none" row a sentinel tag such as `"none"`.
- `TabView`: its value and `actionID` context are the 0-based tab index.
- `Slider`: `range: {min, max}`, `step`; no title. `Stepper`: `range`, `step`, `label` or `labelFormat`. `Gauge`: `range`, `title`, `style`.
- `DisclosureGroup`, `ControlGroup`, `LabeledContent` (+ `children` for the value), `GroupBox`: `title`. `Section`: `header` only.
- `NavigationLink`: an inline `destination`, or the base property `destinationViewId` naming one of the stack's `destinations`.
- `ScrollViewReader`: `scrollTo` (an element id) and `anchor`.
- `Map`: `coordinate: {latitude, longitude}`, `annotations`, `showsUserLocation`, `interactionModes`.
- `LoadableView`: exactly one of `url`, `filePath`, `name`, plus `viewDidLoadActionID`; no inline content.
- `Menu`: `title`, items in `children`; a custom trigger view in the top-level `label`.
- `Toggle` in a `template`: `"isOn": "$1"` exactly (one column reference); the user's change is written back into that column. `disabled` and `hidden` may also be `"$N"`.

### Chart

`Chart` takes one property, `chart`: `{"columns", "data", "content", ...}` in Swift Charts' vocabulary. Apple and Linux draw it; Android and the web show a "Chart Unavailable" placeholder. Read `docs/Schemas/Chart.md` before writing one.

```json
{ "type": "Chart", "id": 10, "properties": { "frame": { "minHeight": 240 }, "chart": {
  "columns": ["day", { "name": "visits", "type": "number" }],
  "data": [["Mon", 120], ["Tue", 180]],
  "content": [{ "type": "ForEach", "content": [
    { "type": "BarMark", "x": { "label": "Day", "value": "$day" }, "y": { "label": "Visits", "value": "$visits" } }] }] } } }
```

`"$column"` reads a cell only inside `ForEach`. A selection (`chartXSelection`) becomes the chart's value and fires `valueChangeActionID`; draw it with a mark outside the `ForEach` whose value is `"$selection"`.

### Add-on elements

`RichText`, `Diff`, `CachedImage`, `QuickLook`, `Chat`, `HostSurface` exist only where the host application registered them; check before using one. Their schemas are in `Add-ons/<Name>/Documentation/Schemas/`.



## Patterns

### Window size

Put `minWidth`/`minHeight` and `idealWidth`/`idealHeight` on the root view's `frame`. A window opens at its ideal size, but on macOS and Linux no wider than 900 points unless the minimum is wider.

```json
"frame": { "minWidth": 720, "minHeight": 480, "idealWidth": 860, "idealHeight": 600 }
```

### Dialog buttons with Return and Escape

`"modifiers": []` binds the bare key; without it the shortcut is Command-Return / Command-Escape.

```json
{ "type": "HStack", "children": [
  { "type": "Spacer" },
  { "type": "Button", "properties": { "title": "Cancel", "keyboardShortcut": { "key": "escape", "modifiers": [] }, "actionID": "dialog.cancel" } },
  { "type": "Button", "properties": { "title": "Create", "buttonStyle": "borderedProminent", "keyboardShortcut": { "key": "return", "modifiers": [] }, "actionID": "dialog.confirm" } }
]}
```

### Toolbar

`toolbar` is a top-level key holding `ToolbarItem` (one view in `content`) and `ToolbarItemGroup` (views in `children`) nodes. `placement` is one of `automatic`, `principal`, `primaryAction`, `secondaryAction`, `confirmationAction`, `cancellationAction`, `destructiveAction`, `topBarLeading`, `topBarTrailing`, `bottomBar`, `keyboard`, `navigation`, `status`.

```json
"toolbar": [
  { "type": "ToolbarItem", "properties": { "placement": "primaryAction" },
    "content": { "type": "Button", "id": 100, "properties": { "systemImage": "plus", "actionID": "item.add" } } }
]
```

### Panels that replace each other

`hidden` keeps the space, so do not stack hidden panels in a VStack. Overlay them in a `ZStack`, all `"hidden": true` but one, and switch them by id at run time.

### A whole row or card as one tap target

Put `actionID` on a `VStack`/`HStack`/`ZStack` and its whole box (padding included) is tappable; a `Button` cannot be a rich cell. In a `template` row the handler gets the container's id as `viewID` and the row index as `viewPartID`. A control inside the cell keeps its own action, and the innermost action wins. Only these three types do this on every platform.

```json
{ "type": "VStack", "id": 900, "template": {
  "type": "HStack", "properties": { "actionID": "item.open", "padding": 8, "frame": { "maxWidth": "infinity" } },
  "children": [ { "type": "Image", "properties": { "systemName": "$1" } }, { "type": "Text", "properties": { "text": "$2" } } ] } }
```

### Checkbox list

A `List` with a `Toggle` template: `"isOn": "$1"`, the title from another column. The handler gets the list's id, the row index as `viewPartID`, and the new state as `context`; the row already holds the new value. Do not use `"itemType": {"viewType": "Toggle"}`.

### Sidebar width

In a `NavigationSplitView`, set `navigationSplitViewColumnWidth: {min, ideal, max}` on the sidebar's root view, not on the split view.

### Read-only log

A `TextEditor` with `"readOnly": true`, `"implementation": "native"` (macOS: the host appends output with `appendElementText` at the new text's cost, not the whole text's), `"font": {"size": 11, "design": "monospaced"}`, `"scrollContentBackground": "hidden"` and a `background`.

### Drop target

`onDropTypes` (UTType ids such as `public.file-url`) with `onDropActionID`, on any element; a `Table` still needs its `columns`.



## ActionUI MCP Server

When the `actionui` MCP server is connected you can open native windows on the user's desktop (macOS or Linux). The tool descriptions explain each tool; pick the lightest that fits: `ask_user` (a question with a few fields, no ActionUI syntax), `pick_path`, `show` (a report, image, diff, table or chart, without waiting), `notify`, and `show_document` only for a layout you write.

For `show_document`:

- Pass the document as a JSON object, never as a string. Run `validate_document` first and fix every error and warning; `screenshot` shows the layout before the user sees it.
- A dialog cannot fill a `Table` or a `template` (rows come at run time): use `mode: "window"` and `update_window` rows, static `children`, or `show` with a table.
- Refused in documents: `SecureField` (never ask for secrets: everything entered reaches you), `LoadableView` (put the content inline), `popover`, `"placement": "secondaryAction"`, `WindowGroup`; WebView `userScripts` are removed. `close_actions` may not start with `mcp.`.
- Windows close when your session ends unless shown with `keep: true`.



## Reference Documents

Full detail lives in the reference docs, not here. In this skill package they are in `docs/`; in an ActionUI checkout, in `Documentation/` (add-on elements: `Add-ons/<Name>/Documentation/Schemas/`). The ActionUI MCP server also serves them as resources `actionui://docs/guide` and `actionui://docs/elements/<Type>`.

- `docs/Schemas/<Type>.md`: every property of one element, its value and events. Read it before using an element you have not used, and whenever a property does not behave as expected.
- `docs/Elements/<Type>.json`: a ready-to-use template for one element.
- `docs/ActionUI-JSON-Guide.md`: structure, layout, platform overrides, charts.
- `docs/ActionUI-Elements.md`: the index of every element.
- `docs/ActionUI-MenuBar-JSON-Guide.md`: the menu-bar document (`MainMenu.json`), whose root is an array, not a view.



*Generated by Skill/build_skill.py - edit Skill/master/content/*.md, not this file.*
