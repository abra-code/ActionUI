---
id: base-properties
level: 2
flavors: [claude, capable]
---

## Universal View Properties

All elements inherit these `properties` keys. None are required.

### Layout

| Property | Type | Notes |
|----------|------|-------|
| `padding` | number \| `"default"` \| `{top?,leading?,bottom?,trailing?}` | |
| `frame` | `{width?,height?,alignment?}` OR `{minWidth?,idealWidth?,maxWidth?,minHeight?,idealHeight?,maxHeight?,alignment?}` | Two mutually exclusive forms. Use `"infinity"` for `.infinity`. |
| `offset` | `{x?,y?}` | Relative position in points |
| `hidden` | boolean | |
| `zIndex` | number | Z-order within container |

### Appearance

| Property | Type | Notes |
|----------|------|-------|
| `foregroundStyle` | color | Text/icon color. Hex `#RRGGBB[AA]`, named (`red`, `blue`, etc.), or semantic (`primary`, `secondary`, etc.) |
| `tint` | color | Interactive control tint (buttons, toggles, sliders) |
| `background` | color | Background fill (string form). Use `background` top-level key for a view background. |
| `opacity` | number | 0.0–1.0 |
| `font` | string \| `{name?,size,weight?,design?}` | Named styles: `largeTitle title title2 title3 headline subheadline body callout footnote caption caption2`. Weight values: `ultraLight thin light regular medium semibold bold heavy black`. |
| `cornerRadius` | number | |
| `clipShape` | `"circle"` \| `"capsule"` \| `"rectangle"` \| `"ellipse"` \| `{type:"roundedRectangle",cornerRadius?}` | |
| `shadow` | `{color?,radius?,x?,y?}` | |
| `border` | `{color?,width?}` | |
| `multilineTextAlignment` | `"leading"` \| `"center"` \| `"trailing"` | Applies to Text; propagates to child Text views on containers |

### Transform

| Property | Type | Notes |
|----------|------|-------|
| `rotationEffect` | number | Degrees; positive = clockwise |
| `scaleEffect` | number \| `{x?,y?,anchor?}` | |
| `animation` | string \| `{curve,duration?,delay?,speed?,value?}` | Curves: `default linear easeIn easeOut easeInOut spring bouncy smooth snappy interactiveSpring` |

### Interaction

| Property | Type | Notes |
|----------|------|-------|
| `actionID` | string | Tap/click action |
| `valueChangeActionID` | string | Fires when observable value changes |
| `onAppearActionID` | string | |
| `onDisappearActionID` | string | |
| `onHoverActionID` | string | macOS/iPadOS with pointer |
| `onDropTypes` | string[] | UTType ids; required alongside `onDropActionID` |
| `onDropActionID` | string | Drop target handler |
| `onDropTargetedActionID` | string | Visual feedback during drag-over |
| `keyboardShortcut` | `{key, modifiers?}` | Modifiers array: `command shift option control capsLock` |
| `disabled` | boolean | |

### Control Styling

| Property | Type | Notes |
|----------|------|-------|
| `buttonStyle` | `automatic` \| `plain` \| `borderless` \| `bordered` \| `borderedProminent` | Propagates to child buttons when set on a container |
| `controlSize` | `mini` \| `small` \| `regular` \| `large` \| `extraLarge` | |
| `labelsHidden` | boolean | Hides labels on child form controls |

### Universal Subview Keys (top-level, not in `properties`)

Any element may also have these top-level keys for overlay/modal presentation:

| Key | Value | Notes |
|-----|-------|-------|
| `overlay` | element node | Rendered on top |
| `background` | element node | Rendered behind (view form) |
| `sheet` | element node | Modal sheet |
| `popover` | element node | Popover |
| `fullScreenCover` | element node | Full-screen modal |
| `toolbar` | array of ToolbarItem/ToolbarItemGroup | |
