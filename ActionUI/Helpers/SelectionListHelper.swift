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

    /// Builds a `List(selection:)` with a `ForEach` over heterogeneous children.
    /// When `listModel` is non-nil, the list element's view modifiers are applied to the result.
    @ViewBuilder
    static func buildSelectableList(
        selection: Binding<Int?>,
        children: [any ActionUIElementBase],
        listElement: any ActionUIElementBase,
        listModel: ViewModel?,
        windowModel: WindowModel?,
        windowUUID: String
    ) -> some SwiftUI.View {
        let listView = SwiftUI.List(selection: selection) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
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
