// Helpers/SwipeActionsHelper.swift
//
// The @ViewBuilder content for a List row's `.swipeActions` modifier (View.swift
// applyModifiers). A dedicated SwiftUI View gives the action buttons a clean
// `body: some View` context, the same pattern ContextMenuHelper uses for the
// context-menu items.
//
// Why swipeActions is a subview slot, not a property:
// SwiftUI's `.swipeActions(edge:allowsFullSwipe:content:)` is a ViewBuilder of
// Buttons - the leading/trailing swipe-to-action idiom on a List row (delete,
// complete, flag). So ActionUI models it like `contextMenu`: `swipeActions` is an
// array subview of real Button elements, each carrying its own title / systemImage
// / role / tint / actionID. The button's `tint` becomes the swipe action's
// background color and `role: "destructive"` colors it red, exactly as in SwiftUI.
//
// Per-edge grouping happens in View.swift before this view is built: each Button
// may declare `edge` ("leading"/"trailing", default trailing); View.swift partitions
// the buttons by edge and calls `.swipeActions(edge:)` once per edge with that
// edge's buttons. So this view just renders one already-grouped edge's buttons.
//
// Note: SwiftUI only honors `.swipeActions` inside a List; attached elsewhere it is
// a no-op (the modifier still applies cleanly), matching the native behavior.

import SwiftUI

/// Renders one edge's swipe-action buttons - real Button child elements built
/// through `ActionUIView` exactly as the context menu builds its items, so each
/// Button becomes a native swipe action (carrying its own title / systemImage /
/// role / tint / actionID).
@MainActor
struct SwipeActionsButtons: SwiftUI.View {
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
