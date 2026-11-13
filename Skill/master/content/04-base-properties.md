---
id: base-properties
level: 2
flavors: [claude, capable]
---

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
