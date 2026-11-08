---
id: core
level: 1
flavors: [claude, capable, lite]
---

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
