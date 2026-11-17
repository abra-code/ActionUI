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
5. A document is plain JSON with one root view. No comments: the schema docs annotate their samples with `//` comments, which make a document invalid; copy the keys, not the comments.

## Workflow

1. **Before writing an element you have not used**, read its schema, `docs/Schemas/<Type>.md` (every property, its values and the events it fires), or start from its template, `docs/Elements/<Type>.json`. Guessing a property name from SwiftUI usually works, but when it does not, nothing fails: the property is just ignored.
2. **When changing an existing document**, read all of it first and keep every `id` and `actionID` as they are unless asked to change them: the application finds elements by `id` and handles actions by name, so a renumbered id or a renamed action breaks it without any error. Give new elements ids no other element uses.
3. **Validate** (see Validation) and fix every error and warning.
4. **Look at it** when the layout changed and you can render it: the validator does not see clipped or squeezed views.
