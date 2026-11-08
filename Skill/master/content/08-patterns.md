---
id: patterns
level: 2
flavors: [claude, capable]
---

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

A `TextEditor` with `"readOnly": true`, `"font": {"size": 11, "design": "monospaced"}`, `"scrollContentBackground": "hidden"` and a `background`.

### Drop target

`onDropTypes` (UTType ids such as `public.file-url`) with `onDropActionID`, on any element; a `Table` still needs its `columns`.
