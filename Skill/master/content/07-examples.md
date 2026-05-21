---
id: examples
level: 2
flavors: [lite]
---

## Examples

### Simple form with a button

```json
{
  "type": "VStack",
  "properties": { "spacing": 16, "padding": 20 },
  "children": [
    { "type": "Text", "properties": { "text": "Enter your name", "font": "headline" } },
    { "type": "TextField", "id": 1, "properties": { "title": "Name", "actionID": "nameChanged" } },
    { "type": "Button", "id": 2, "properties": { "title": "Submit", "actionID": "submit", "buttonStyle": "borderedProminent" } }
  ]
}
```

### Card with image and text

```json
{
  "type": "VStack",
  "properties": { "spacing": 8, "padding": 16, "cornerRadius": 12, "background": "#FFFFFF", "shadow": { "radius": 4 } },
  "children": [
    { "type": "Image", "properties": { "systemName": "star.fill", "foregroundStyle": "yellow", "font": { "size": 48 } } },
    { "type": "Text", "properties": { "text": "Featured", "font": "title2" } },
    { "type": "Text", "properties": { "text": "Tap to learn more", "font": "body", "foregroundStyle": "secondary" } }
  ]
}
```

### List with navigation

```json
{
  "type": "NavigationStack",
  "id": 10,
  "content": {
    "type": "List",
    "properties": { "actionID": "itemSelected" },
    "children": [
      { "type": "Label", "id": 1, "properties": { "title": "Settings", "systemImage": "gear", "destinationViewId": 100 } },
      { "type": "Label", "id": 2, "properties": { "title": "Profile", "systemImage": "person", "destinationViewId": 101 } }
    ]
  },
  "destinations": [
    { "type": "Text", "id": 100, "properties": { "text": "Settings View" } },
    { "type": "Text", "id": 101, "properties": { "text": "Profile View" } }
  ]
}
```
