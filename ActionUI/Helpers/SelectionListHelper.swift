// Sources/Helpers/SelectionListHelper.swift
// Shared helpers for selectable heterogeneous lists used by List, NavigationStack, and NavigationSplitView.

import SwiftUI

@MainActor
struct SelectionListHelper {

    /// Builds bidirectional maps between child element IDs and destination view IDs.
    /// Child element IDs are used as ForEach identity / List selection values;
    /// destination view IDs are the logical targets stored in state or navigation paths.
    static func buildIDMaps(
        children: [any ActionUIElementBase],
        windowModel: WindowModel?
    ) -> (childToDestination: [Int: Int], destinationToChild: [Int: Int]) {
        var childToDestination: [Int: Int] = [:]
        var destinationToChild: [Int: Int] = [:]
        for child in children {
            if let destId = windowModel?.viewModels[child.id]?.validatedProperties["destinationViewId"] as? Int {
                childToDestination[child.id] = destId
                destinationToChild[destId] = child.id
            }
        }
        return (childToDestination, destinationToChild)
    }

    /// `.animation(_, value:)` inputs for a heterogeneous List: SwiftUI's `List` virtualizes its rows
    /// and does not pick up a row's `.transition()` from the ambient `withAnimation` alone (unlike a
    /// VStack/LazyVStack, which honor child transitions directly) - the animation must be attached at
    /// the List level, keyed by the row identity, for an inserted/removed row to play its transition.
    /// Returns (animation, rowIDs); the animation is nil (no row animation - the existing default) unless
    /// a child opts in by declaring a `transition`, so ordinary Lists are unaffected.
    static func rowTransitionAnimation(_ children: [any ActionUIElementBase]) -> (Animation?, [Int]) {
        let ids = children.map { $0.id }
        let animate = children.contains { $0.properties["transition"] != nil }
        return (animate ? .default : nil, ids)
    }

    /// Builds a `List(selection:)` with a `ForEach` over heterogeneous children.
    /// When `listModel` is non-nil, the list element's view modifiers are applied to the result.
    /// When `rowModifier` is non-nil, it is applied to each child row (e.g. for listRowBackground etc.).
    @ViewBuilder
    static func buildSelectableList(
        selection: Binding<Int?>,
        children: [any ActionUIElementBase],
        listElement: any ActionUIElementBase,
        listModel: ViewModel?,
        windowModel: WindowModel?,
        windowUUID: String,
        rowModifier: ((AnyView) -> AnyView)? = nil
    ) -> some SwiftUI.View {
        let (rowAnimation, rowIDs) = rowTransitionAnimation(children)
        let listView = SwiftUI.List(selection: selection) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    let childView = AnyView(ActionUIView(element: child, model: childModel, windowUUID: windowUUID))
                    rowModifier?(childView) ?? childView
                }
            }
        }
        .animation(rowAnimation, value: rowIDs)
        if let listModel = listModel {
            let listProps = ActionUIRegistry.shared.getValidatedProperties(element: listElement, model: listModel)
            ActionUIRegistry.shared.applyViewModifiers(to: listView, properties: listProps, element: listElement, model: listModel, windowUUID: windowUUID)
        } else {
            listView
        }
    }

    /// Creates a `Binding<Int?>` for heterogeneous list selection by child element ID.
    /// Selection is stored in `model.value` as `[String]` with the stringified child ID.
    /// Fires `actionID` on selection change with the child ID as context.
    static func makeHeterogeneousSelectionBinding(
        model: ViewModel,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) -> Binding<Int?> {
        Binding<Int?>(
            get: {
                if let selected = model.value as? [String],
                   let first = selected.first,
                   let childId = Int(first) {
                    return childId
                }
                return nil
            },
            set: { newValue in
                let newStringValue: [String] = newValue.map { [String($0)] } ?? []
                guard (model.value as? [String]) != newStringValue else { return }
                DispatchQueue.main.async {
                    model.value = newStringValue
                    if let actionID = actionID {
                        ActionUIModel.shared.actionHandler(
                            actionID,
                            windowUUID: windowUUID,
                            viewID: viewID,
                            viewPartID: 0,
                            context: newValue as Any
                        )
                    }
                }
            }
        )
    }
}
