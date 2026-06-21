// Helpers/ContextMenuHelper.swift
//
// The @ViewBuilder content for a view's `.contextMenu` modifier (View.swift
// applyModifiers). A dedicated SwiftUI View gives the menu/preview rendering a clean
// `body: some View` context (the same reason `.onDrop` lives in DropModifierView).
//
// Why contextMenu is two subview slots, not a property:
// SwiftUI's `.contextMenu(menuItems:preview:)` is itself TWO ViewBuilders - a menu of
// action items, and an optional arbitrary "preview" card shown above the menu on a
// long-press (iOS; macOS right-click menus have no preview). The preview is the only
// slot where free-form layout (an HStack of items) or a big Image renders richly. So
// ActionUI models it the same way: `contextMenu` is an array subview of real menu-item
// elements (Button / Divider / Section / sub-Menu) and `contextMenuPreview` is an
// optional single arbitrary subview. Real element subtrees let a designer place any
// views, not buttons synthesized from a flat descriptor array.

import SwiftUI

/// Renders the `contextMenu` action items - real child elements (typically Buttons),
/// built through `ActionUIView` exactly as `Menu` builds its children, so a Button
/// becomes a native menu row (carrying its own title / systemImage / role / actionID).
@MainActor
struct ContextMenuMenuItems: SwiftUI.View {
    let items: [any ActionUIElementBase]
    let windowUUID: String

    var body: some SwiftUI.View {
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        SwiftUI.ForEach(items, id: \.id) { item in
            if let model = windowModel?.viewModels[item.id] {
                ActionUIView(element: item, model: model, windowUUID: windowUUID)
            }
        }
    }
}

/// Renders the optional `contextMenuPreview` - a single arbitrary view shown above the
/// menu (iOS), built through `ActionUIView` like any other subview root.
@MainActor
struct ContextMenuPreviewContent: SwiftUI.View {
    let element: any ActionUIElementBase
    let windowUUID: String

    var body: some SwiftUI.View {
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        if let model = windowModel?.viewModels[element.id] {
            ActionUIView(element: element, model: model, windowUUID: windowUUID)
        }
    }
}
