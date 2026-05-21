---
id: core
level: 1
flavors: [claude, capable, lite]
---

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
