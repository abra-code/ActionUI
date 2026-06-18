// Helpers/SearchableHelper.swift

import SwiftUI

// Helper view that applies .searchable to its content with a locally-owned query binding.
// On each query change it fires actionID with the current query string as the action context, so
// the host can filter its data and re-push rows (e.g. via setElementRows). The search field is
// surfaced by the nearest enclosing NavigationStack / NavigationSplitView, per SwiftUI. Mirrors
// PopoverModifierView's wrapper pattern (a separate view is needed to own the @State binding, which
// the static applyModifiers function cannot hold).
@MainActor
struct SearchableModifierView: SwiftUI.View {
    let content: AnyView
    let windowUUID: String
    let elementID: Int
    let actionID: String
    let prompt: String?

    @State private var query: String = ""

    var body: some SwiftUI.View {
        searchableContent
            .onChange(of: query) { _, newValue in
                ActionUIModel.shared.actionHandler(
                    actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: newValue
                )
            }
    }

    @ViewBuilder
    private var searchableContent: some SwiftUI.View {
        if let prompt {
            content.searchable(text: $query, prompt: prompt)
        } else {
            content.searchable(text: $query)
        }
    }
}
