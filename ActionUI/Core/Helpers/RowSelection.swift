// Core/Helpers/RowSelection.swift
/*
 Selection in lists, without the views: the maps between a heterogeneous list's children and the
 destinations they name, the selected row of a data-driven list (a List with rows or a template,
 a Table) as an index into the rows drawn, and storing a selection the user made.

 A data-driven list's selection is its value, the selected row's columns as [String] ([] when
 nothing is selected). A heterogeneous list's selection is its value as [String] too, holding the
 selected child's element ID as text.

 (The SwiftUI List and Binding code is in Helpers/SelectionListHelper.swift.)
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

@MainActor
enum RowSelection {

    /// Builds bidirectional maps between child element IDs and destination view IDs.
    /// Child element IDs are used as ForEach identity / List selection values;
    /// destination view IDs are the logical targets stored in state or navigation paths.
    static func buildIDMaps(
        children: [any ActionUIElementBase],
        windowModel: WindowModel?
    ) -> (childToDestination: [Int: Int], destinationToChild: [Int: Int]) {
        var childToDestination: [Int: Int] = [:]
        var destinationToChild: [Int: Int] = [:]
        // Read untracked: a change to a child's properties does not render the container again.
        for child in children {
            if let destId = UntrackedReads.perform({
                windowModel?.viewModels[child.id].flatMap { BaseModifiers($0.properties).destinationViewId }
            }) {
                childToDestination[child.id] = destId
                destinationToChild[destId] = child.id
            }
        }
        return (childToDestination, destinationToChild)
    }

    // MARK: - Data-driven lists

    /// The index in `drawnRows` of the selected row `value` (a list's value), or nil when nothing
    /// is selected or the row is not among those drawn.
    static func selectedIndex(value: Any?, in drawnRows: [[String]]) -> Int? {
        guard let selectedRow = value as? [String], !selectedRow.isEmpty else { return nil }
        return drawnRows.firstIndex(where: { $0 == selectedRow })
    }

    /// The row the user clicked, from the index the toolkit reports into `drawnRows`: `[]` for no
    /// index (a deselect), nil for an index outside the rows drawn (ignored).
    static func clickedRow(index: Int?, in drawnRows: [[String]]) -> [String]? {
        guard let index else { return [] }
        guard drawnRows.indices.contains(index) else { return nil }
        return drawnRows[index]
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

    // MARK: - Heterogeneous lists

    /// The element ID of the selected child, from a heterogeneous list's value.
    static func selectedChildID(value: Any?) -> Int? {
        guard let selected = value as? [String], let first = selected.first else { return nil }
        return Int(first)
    }

    /// Stores the child the user selected (nil for a deselect) in `model.value` as its ID in
    /// text, and fires `actionID` with the child ID as context, unless nothing changes. The write
    /// waits for the next main-queue turn, as in `commitRowSelection`.
    static func commitChildSelection(
        _ childID: Int?,
        model: ViewModel,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) {
        let newStringValue: [String] = childID.map { [String($0)] } ?? []
        guard (model.value as? [String]) != newStringValue else { return }
        DispatchQueue.main.async {
            model.value = newStringValue
            if let actionID = actionID {
                ActionUIModel.shared.actionHandler(
                    actionID,
                    windowUUID: windowUUID,
                    viewID: viewID,
                    viewPartID: 0,
                    context: childID as Any
                )
            }
        }
    }
}
