---
id: patterns
level: 2
flavors: [claude, capable]
---

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
