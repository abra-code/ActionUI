// Helpers/SelectionListHelper.swift
// The SwiftUI side of selectable lists (List, NavigationStack, NavigationSplitView): the selectable
// List and the selection bindings. What a selection is, and storing one, is in
// Core/Helpers/RowSelection.swift.

import SwiftUI

@MainActor
struct SelectionListHelper {

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
            let listProps = ActionUIRegistry.shared.currentProperties(element: listElement, model: listModel)
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
                RowSelection.selectedIndex(value: model.value, in: drawnRows).map { Set([$0]) } ?? Set<Int>()
            },
            set: { newSet in
                // Enforce single selection (take the first if several arrive).
                guard let clicked = RowSelection.clickedRow(index: newSet.first, in: drawnRows) else { return }
                RowSelection.commitRowSelection(clicked, drawnRows: drawnRows, model: model,
                                                actionID: actionID, windowUUID: windowUUID, viewID: viewID)
            }
        )
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
            get: { RowSelection.selectedChildID(value: model.value) },
            set: { newValue in
                RowSelection.commitChildSelection(newValue, model: model, actionID: actionID,
                                                  windowUUID: windowUUID, viewID: viewID)
            }
        )
    }
}
