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

    /// Creates a `Binding<Set<Int>>` for a data-driven list's selection (the homogeneous and the
    /// template modes), by row index into `drawnRows`, the content rows this render of the list
    /// shows: SwiftUI hands the setter an index into what it last drew, which the host may have
    /// replaced since. Single selection: the selected row's columns are stored in `model.value`
    /// as `[String]` (empty when nothing is selected). Fires `actionID` (no context) whenever the
    /// user changes the selection, clearing included, as a Table does: a host that keeps its own
    /// copy of the selection must learn that the row was deselected (Cmd-click on the selected
    /// row, a click in the empty part of the list).
    static func makeRowSelectionBinding(
        drawnRows: [[String]],
        model: ViewModel,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) -> Binding<Set<Int>> {
        mainActorBinding(
            get: {
                guard let selectedRow = model.value as? [String],
                      !selectedRow.isEmpty,
                      let selectedIndex = drawnRows.firstIndex(where: { $0 == selectedRow }) else {
                    return Set<Int>()
                }
                return Set([selectedIndex])
            },
            set: { newSet in
                // Enforce single selection (take the first if several arrive).
                let clicked: [String]
                if let newIndex = newSet.first {
                    guard drawnRows.indices.contains(newIndex) else { return }
                    clicked = drawnRows[newIndex]
                } else {
                    clicked = []
                }
                commitRowSelection(clicked, drawnRows: drawnRows, model: model,
                                   actionID: actionID, windowUUID: windowUUID, viewID: viewID)
            }
        )
    }

    /// Stores a row the user selected (`[]` for a deselect) in `model.value` and fires `actionID`
    /// (no context, `viewPartID` 0), unless nothing changes. Shared by the data-driven List and
    /// the Table. The write waits for the next main-queue turn (a binding setter runs during a
    /// view update); by then a host may have replaced the rows, so the clicked row is taken as it
    /// is in the current rows (`ActionUIModel.reconciledSelection`, from `drawnRows`).
    static func commitRowSelection(
        _ clicked: [String],
        drawnRows: [[String]],
        model: ViewModel,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) {
        guard (model.value as? [String] ?? []) != clicked else { return }
        DispatchQueue.main.async {
            let rows = model.states["content"] as? [[String]] ?? []
            let value = ActionUIModel.reconciledSelection(clicked, from: drawnRows, to: rows)
            guard (model.value as? [String] ?? []) != value else { return }
            model.value = value
            if let actionID {
                ActionUIModel.shared.actionHandler(
                    actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0
                )
            }
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
