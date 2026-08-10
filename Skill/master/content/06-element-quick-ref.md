---
id: element-quick-ref
level: 2
flavors: [claude, capable]
---

## Element Quick Reference

Element type names are PascalCase. For full property documentation read `docs/Schemas/<Type>.md`; for a ready-to-use template read `docs/Elements/<Type>.json`. See `docs/ActionUI-Elements.md` for the complete index.

### Layout Containers

| Type | Key properties | Children |
|------|---------------|----------|
| `VStack` | `spacing`, `alignment` (leading/center/trailing) | `children` array |
| `HStack` | `spacing`, `alignment` (top/center/bottom/firstTextBaseline/lastTextBaseline) | `children` array |
| `ZStack` | `alignment` (topLeading, center, bottomTrailing, etc.) | `children` array |
| `LazyVStack` | `spacing`, `alignment`, `pinnedViews` | `children` array |
| `LazyHStack` | `spacing`, `alignment` | `children` array |
| `ScrollView` | `axis` (vertical/horizontal/both), `showsIndicators` | `content` (single view) |
| `Group` | — | `children` array |
| `GroupBox` | `title` | `children` array |
| `GeometryReader` | — | `children` array |

### Grid

| Type | Key properties | Children |
|------|---------------|----------|
| `Grid` | `spacing`, `alignment`, `horizontalSpacing`, `verticalSpacing` | `rows` (2-D array of cell elements) |
| `LazyVGrid` | `columns` (GridItem array), `spacing` | `children` array |
| `LazyHGrid` | `rows` (GridItem array), `spacing` | `children` array |

### Navigation

| Type | Key properties | Children |
|------|---------------|----------|
| `NavigationStack` | — | `content` (single view), `destinations` array |
| `NavigationSplitView` | `style` | `sidebar`, `content`, `detail` (each single view) |
| `NavigationLink` | `title`, `destinationViewId` (Form 2), `actionID` | `content` (custom label) |
| `TabView` | `actionID` | `children` array of `Tab` nodes |
| `Tab` | `title`, `systemImage`, `actionID` | `content` (single view) |

### Lists and Forms

| Type | Key properties | Children |
|------|---------------|----------|
| `List` | `listStyle`, `actionID`, `doubleClickActionID`, `itemType` | `children` array or `template` |
| `Form` | — | `children` array |
| `Section` | `header`, `footer` | `children` array |
| `Table` | `columns` (array of column defs) | `rows` (2-D array of cell values) |
| `DisclosureGroup` | `label`, `isExpanded`, `actionID` | `children` array |

### Text and Display

| Type | Key properties | Notes |
|------|---------------|-------|
| `Text` | `text`, `markdown` | `markdown` takes precedence |
| `Image` | `systemName`, `assetName`, `resourceName`, `filePath`, `contentMode`, `resizable` | One source property required |
| `Label` | `title`, `systemImage` | SF Symbol label |
| `Divider` | — | |
| `Spacer` | `minLength` | |
| `ProgressView` | `style` (circular/linear), `value`, `total`, `title` | |
| `Gauge` | `value`, `min`, `max`, `title`, `label`, `currentValueLabel` | |
| `Canvas` | `operations` (array), `backgroundColor`, `coordinateMode` | Drawing surface |

### Input Controls

| Type | Key properties | Value type |
|------|---------------|-----------|
| `Button` | `title`, `systemImage`, `role` (destructive/cancel), `actionID` | — |
| `Toggle` | `title`, `actionID` | boolean |
| `Slider` | `range: {min,max}`, `step`, `title`, `actionID` | number |
| `Stepper` | `range: {min,max}`, `step`, `title`, `actionID` | number |
| `Picker` | `title`, `pickerStyle`, `actionID` | string (selected label) |
| `DatePicker` | `title`, `displayedComponents`, `actionID` | string (ISO 8601 date) |
| `ColorPicker` | `title`, `actionID` | string (hex color) |
| `TextField` | `title`, `actionID`, `keyboard` | string |
| `SecureField` | `title`, `actionID` | string |
| `TextEditor` | `actionID` | string |

### Overlays and Modals (top-level keys, not `properties`)

`overlay`, `background` (view), `sheet`, `popover`, `fullScreenCover`, `toolbar`

`persistentToolbar` - on `NavigationStack` / `NavigationSplitView` only: toolbar items that stay in the bar on every screen inside the container. A `toolbar` on those two types is a deprecated alias for it. Apple platforms and Android; web ignores it for now.

### Shapes

`Circle`, `Ellipse`, `Rectangle`, `RoundedRectangle`, `Capsule` — accept View base properties (foregroundStyle, frame, etc.)

### Special

| Type | Notes |
|------|-------|
| `Link` | `url`, `title`, `actionID` |
| `ShareLink` | `item`, `subject`, `message` |
| `Menu` | `title` | `children` (button list); optional `label` top-level for a custom trigger view |
| `ControlGroup` | `style` | `children` array |
| `LabeledContent` | `label`, `value` |
| `ScrollViewReader` | Wraps a ScrollView; `actionID` for scroll-to |
| `Map` | `latitude`, `longitude`, `span` |
| `WebView` | `url` |
| `VideoPlayer` | `url` |
| `AsyncImage` | `url`, `contentMode` |
| `LoadableView` | `actionID`, `loadingView`, `errorView` | `content` (single view) |
| `ContentUnavailableView` | `title`, `systemImage`, `description` |
| `PhaseAnimator` | `phases`, `trigger` | `content` (single view) |
| `KeyframeAnimator` | `trigger` | `content` (single view) |
| `EmptyView` | — | |
| `HSplitView` / `VSplitView` | macOS split pane | `children` array |
| `ToolbarItem` | `placement` | `content` (single view) |
| `ToolbarItemGroup` | `placement` | `content` (single view) |
