---
id: swiftui-crash-course
level: 1
flavors: [lite]
---

## Layout Fundamentals

ActionUI uses the same layout model as SwiftUI. You do not need to know Swift — just understand these concepts.

### Stacks

Stacks group views in a line. Children are placed in the `children` array.

- `VStack` — top to bottom (vertical column)
- `HStack` — left to right (horizontal row)
- `ZStack` — layered (back to front, like CSS z-index)

```json
{ "type": "VStack", "properties": { "spacing": 12 }, "children": [
  { "type": "Text", "properties": { "text": "Hello" } },
  { "type": "Text", "properties": { "text": "World" } }
]}
```

### Spacing vs Padding

These are different and both matter:
- `spacing` on a stack: gap **between** children
- `padding` on any view: inset from its **own edges** (inside)

```json
{ "type": "VStack", "properties": { "spacing": 16, "padding": 24 }, "children": [...] }
```

### Frames

Set explicit sizes with `frame`. Without a frame, a view sizes to its content.

```json
"frame": { "width": 200, "height": 50 }           // fixed size
"frame": { "maxWidth": "infinity" }                 // expands to fill available width
"frame": { "minHeight": 44 }                        // at least 44 points tall
```

### Colors

Colors can be strings (named, hex, or system):
- Named: `"red"`, `"blue"`, `"green"`, `"white"`, `"black"`, `"clear"`, `"gray"`, `"orange"`, `"purple"`, `"yellow"`, `"pink"`, `"teal"`, `"indigo"`
- Hex: `"#FF5733"`, `"#FF573380"` (with alpha)
- System adaptive (light/dark): `"systemBackground"`, `"secondarySystemBackground"`, `"label"`, `"secondaryLabel"`

### Modifiers (Universal Properties)

These apply to **any** element type. Place them in `properties`.

| Property | Value | Effect |
|----------|-------|--------|
| `foregroundStyle` | color string | Text and icon color |
| `background` | color string | Background fill |
| `cornerRadius` | number | Rounded corners |
| `opacity` | 0.0–1.0 | Transparency |
| `padding` | number or `{"top":n,"leading":n,"bottom":n,"trailing":n}` | Inset from edges |
| `frame` | object | Size constraints |
| `shadow` | `{"color":"black","radius":4,"x":0,"y":2}` | Drop shadow |
| `font` | `{"size":16,"weight":"bold"}` | Text size and weight |

### Text

Display text with `Text`. For user input use `TextField`.

```json
{ "type": "Text", "properties": { "text": "Hello" } }
{ "type": "Text", "properties": { "markdown": "**Bold** and *italic*" } }
{ "type": "TextField", "properties": { "title": "Enter name", "actionID": "nameChanged" } }
```

### Images

System icons use `systemName` (SF Symbols). Asset images use `assetName`.

```json
{ "type": "Image", "properties": { "systemName": "star.fill", "foregroundStyle": "yellow" } }
{ "type": "Image", "properties": { "assetName": "logo", "frame": { "width": 80, "height": 80 } } }
```

### Buttons and Actions

Any tappable element uses `actionID`. The app code handles the ID string.

```json
{ "type": "Button", "properties": { "title": "Save", "actionID": "savePressed" } }
```

You can also put `actionID` directly on most view types to make them tappable.

### Lists and Navigation

`List` shows a scrollable column of rows. `NavigationStack` adds navigation.

```json
{ "type": "NavigationStack", "destinations": [
  { "type": "List", "properties": {}, "children": [
    { "type": "Text", "properties": { "text": "Row 1" } }
  ]}
]}
```

### Alignment

Control how children align inside a stack:

- `VStack` alignment: `"leading"`, `"center"` (default), `"trailing"`
- `HStack` alignment: `"top"`, `"center"` (default), `"bottom"`, `"firstTextBaseline"`
- `ZStack` alignment: `"topLeading"`, `"topTrailing"`, `"bottomLeading"`, `"bottomTrailing"`, `"center"` (default)

```json
{ "type": "HStack", "properties": { "alignment": "top", "spacing": 8 }, "children": [...] }
```

### Scrollable Content

Wrap content in `ScrollView` to enable scrolling:

```json
{ "type": "ScrollView", "properties": { "axes": "vertical" }, "children": [...] }
```
