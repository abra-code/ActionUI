// Helpers/ToolbarHelper.swift

import SwiftUI

// Maps a JSON placement string to the SwiftUI ToolbarItemPlacement value.
// Platform-unavailable placements (e.g., "bottomBar" on macOS) fall back to .automatic.
enum ToolbarHelper {
    static func resolvePlacement(_ string: String?) -> ToolbarItemPlacement {
        switch string {
        case "automatic":
            return .automatic
        case "principal":
            return .principal
        case "confirmationAction":
            return .confirmationAction
        case "cancellationAction":
            return .cancellationAction
        case "destructiveAction":
            return .destructiveAction
        case "primaryAction":
            return .primaryAction
        case "secondaryAction":
            return .secondaryAction
        case "topBarLeading":
#if os(iOS) || os(visionOS)
            return .topBarLeading
#else
            return .automatic
#endif
        case "topBarTrailing":
#if os(iOS) || os(visionOS)
            return .topBarTrailing
#else
            return .automatic
#endif
        case "bottomBar":
#if os(iOS) || os(visionOS)
            return .bottomBar
#else
            return .automatic
#endif
        case "keyboard":
#if os(iOS) || os(visionOS)
            return .keyboard
#else
            return .automatic
#endif
        case "navigation":
#if os(macOS)
            return .navigation
#else
            return .automatic
#endif
        case "status":
#if os(macOS)
            return .status
#else
            return .automatic
#endif
        default:
            return .automatic
        }
    }
}

// Applies toolbar items declared in a view's "toolbar" subview array.
// Each item gets its own .toolbar {} call — multiple .toolbar modifiers are additive in SwiftUI
// and accumulate their items in the containing NavigationStack or NavigationSplitView.
// Using one .toolbar per item avoids @ToolbarContentBuilder ForEach overload ambiguity with
// existential arrays. ToolbarItemGroup entries use SwiftUI.ToolbarItemGroup for system-managed
// multi-item grouping; ToolbarItem entries use SwiftUI.ToolbarItem. Mirrors SheetModifierView pattern.
//
// body returns AnyView so that the for-loop imperative logic is not inside @ViewBuilder.
@MainActor
struct ToolbarModifierView<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let toolbarItems: [any ActionUIElementBase]
    let windowUUID: String

    var body: AnyView {
        var view: AnyView = AnyView(content)
        for item in toolbarItems {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            // Prefer validated placement from the ViewModel; fall back to raw property.
            let placementStr = windowModel?.viewModels[item.id]?.validatedProperties["placement"] as? String
                ?? item.properties["placement"] as? String
            let placement = ToolbarHelper.resolvePlacement(placementStr)
            let capturedItem = item
            let capturedWindowUUID = windowUUID
            if item.type == "ToolbarItemGroup" {
                view = AnyView(
                    view.toolbar {
                        SwiftUI.ToolbarItemGroup(placement: placement) {
                            ToolbarItemGroupContentView(element: capturedItem, windowUUID: capturedWindowUUID)
                        }
                    }
                )
            } else {
                view = AnyView(
                    view.toolbar {
                        SwiftUI.ToolbarItem(placement: placement) {
                            ToolbarItemContentView(element: capturedItem, windowUUID: capturedWindowUUID)
                        }
                    }
                )
            }
        }
        return view
    }
}

// Renders the single "content" element declared inside a ToolbarItem.
// ToolbarItem occupies exactly one toolbar slot; composite layouts (HStack, ZStack, etc.)
// are the caller's responsibility, not the toolbar's.
@MainActor
private struct ToolbarItemContentView: SwiftUI.View {
    let element: any ActionUIElementBase
    let windowUUID: String

    var body: some SwiftUI.View {
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        if let content = element.subviews?["content"] as? (any ActionUIElementBase),
           let contentModel = windowModel?.viewModels[content.id] {
            ActionUIView(element: content, model: contentModel, windowUUID: windowUUID)
        }
    }
}

// Renders the "children" array declared inside a ToolbarItemGroup.
// Each child is an independent toolbar item managed by the system — spacing, overflow,
// and platform-specific grouping are handled by SwiftUI, not the content view.
@MainActor
private struct ToolbarItemGroupContentView: SwiftUI.View {
    let element: any ActionUIElementBase
    let windowUUID: String

    var body: some SwiftUI.View {
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        ForEach(children, id: \.id) { child in
            if let childModel = windowModel?.viewModels[child.id] {
                ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
            }
        }
    }
}
