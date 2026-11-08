---
id: element-quick-ref
level: 2
flavors: [claude, capable]
---

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
