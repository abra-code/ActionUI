// Sources/Elements/List+WinUI.swift
/*
 List on WinUI: Windows' ListView, as greedy as SwiftUI's List (it shares a stack like a Color, as on
 Linux), in the forms the Linux renderer has:

 - Rows (Form 1): one row per content row (setElementRows) whose first column is not empty, showing
   the first column as text. Selectable: a selection the user makes becomes the value (the row's
   columns) and fires actionID (Core RowSelection); a double click (or Return) fires
   doubleClickActionID with the row's index in the content, the row becoming the value first (and
   actionID firing when that changed it), as on Linux.
 - Children (Form 2): one row per child element's box. With an actionID, selectable: the value is
   the selected child's id as text, and actionID fires with the id as its context; without one, the
   rows are not selectable and the children handle their own input.
 - Template (Form 3): one row per content row, the template element shown with the row's data ($1
   is its first column; RenderNode.templateRowNode), selected and activated as rows are. A row whose
   data or place changes is made again; the others keep their objects, as on Linux.

 The value selects its row when a host sets it; the ListView reports that selection as it reports
 the user's, and the renderer ignores the one it made (ListState.shownIndex), so actionID fires only
 for the user's.

 Not yet: itemType's Button,
 Image and AsyncImage cells (text for now); listStyle and the row styling (listRowBackground,
 listRowSeparator, listRowSeparatorTint, listRowInsets); pull to refresh (desktops have none).
*/

import CWinUI

/// What a List shows, kept in its node's state.
@MainActor final class ListState {
    enum Mode {
        case rows, children, template
    }

    var mode = Mode.rows
    /// The content as drawn (rows mode), the content index of each row shown, and each row's text.
    var drawnRows: [[String]] = []
    var shownIndices: [Int] = []
    var shownTexts: [String]?
    /// The element id of each row's child, and the boxes the rows show (children mode): a child
    /// replaced under the same id has a new node and box.
    var childIDs: [Int]?
    var shownBoxes: [WinUIObject]?
    /// Each row's template instance, in row order (template mode).
    var rowNodes: [RenderNode] = []
    /// The row the renderer last selected: a selection event reporting it is the renderer's own.
    var shownIndex: Int32 = -1
}

extension List: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let list = WinUIObject(adopting: actionUIWinUIListCreate()) else {
            throw WinUIError.last("creating a List")
        }
        let state = ListState()
        node.state = state
        WinUIEvents.connect(list, actionUIWinUIListOnSelectionChanged, "a List's selection") { [weak node, weak state, weak list] in
            guard let node, let state, let list, node.isAttached else { return }
            let index = actionUIWinUIListGetSelectedIndex(list.pointer)
            guard index != state.shownIndex else { return }
            state.shownIndex = index
            userSelected(node, state, position: index >= 0 ? Int(index) : nil)
        }
        WinUIEvents.connect(list, actionUIWinUIListOnActivated, "a List's activation") { [weak node, weak state, weak list] in
            guard let node, let state, let list, node.isAttached else { return }
            let index = actionUIWinUIListGetSelectedIndex(list.pointer)
            userActivated(node, state, position: index >= 0 ? Int(index) : nil)
        }
        return list
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ListState else { return }
        let props = Props(node.properties)
        let children = node.subviews("children")
        let template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase
        let mode: ListState.Mode = template != nil ? .template : children.isEmpty ? .rows : .children
        if mode != state.mode {
            leave(view, node, state)
            state.mode = mode
        }
        switch mode {
        case .rows:
            setSelectable(view, state, true)
            updateRows(view, node, state)
        case .template:
            setSelectable(view, state, true)
            if let template {
                updateTemplateRows(view, node, state, template)
            }
        case .children:
            setSelectable(view, state, props.actionID != nil)
            updateChildren(view, node, state, children)
        }
    }

    /// Empties the list when it changes form: the child nodes or the template rows leave the tree
    /// (as on Linux); the new form makes its rows again.
    private static func leave(_ view: WinUIObject, _ node: RenderNode, _ state: ListState) {
        switch state.mode {
        case .rows:
            break
        case .children:
            _ = node.syncChildren([])
        case .template:
            for rowNode in state.rowNodes {
                node.releaseTemplateNode(rowNode)
            }
            state.rowNodes = []
        }
        state.shownIndex = -1
        if !actionUIWinUIListClear(view.pointer) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("clearing the rows"))", .error)
        }
        state.drawnRows = []
        state.shownIndices = []
        state.shownTexts = nil
        state.childIDs = nil
        state.shownBoxes = nil
    }

    private static func setSelectable(_ view: WinUIObject, _ state: ListState, _ selectable: Bool) {
        if !selectable {
            // The ListView drops its selection when made unselectable, and reports it: the
            // renderer's own change, not the user's deselect.
            state.shownIndex = -1
        }
        if !actionUIWinUIListSetSelectable(view.pointer, selectable) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("setting the selection mode"))", .error)
        }
    }

    // MARK: Rows

    private static func updateRows(_ view: WinUIObject, _ node: RenderNode, _ state: ListState) {
        let items = node.model.states["content"] as? [[String]] ?? []
        let shown = shownRowIndices(items)
        state.drawnRows = items
        state.shownIndices = shown
        let texts = shown.map { items[$0][0] }
        if texts != state.shownTexts {
            state.shownTexts = texts
            // The rows change: the selection is shown again below.
            state.shownIndex = -1
            var filled = actionUIWinUIListClear(view.pointer)
            for text in texts where filled {
                filled = actionUIWinUIListAppendText(view.pointer, text)
            }
            if !filled {
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("showing the rows"))", .error)
                state.shownTexts = nil
            }
        }
        let position = RowSelection.selectedIndex(value: node.model.value, in: items).flatMap { shown.firstIndex(of: $0) }
        select(view, state, position)
    }

    // MARK: Children

    private static func updateChildren(_ view: WinUIObject, _ node: RenderNode, _ state: ListState, _ elements: [any ActionUIElementBase]) {
        // A child with no object (its placeholder failed too) has no row: the ids stay in step with the rows.
        let childNodes = node.syncChildren(elements).filter { $0.outerView != nil }
        let ids = childNodes.map(\.element.id)
        let boxes = childNodes.map { $0.outerView! }
        state.childIDs = ids
        if state.shownBoxes.map({ !$0.elementsEqual(boxes, by: ===) }) ?? true {
            state.shownBoxes = boxes
            state.shownIndex = -1
            var filled = actionUIWinUIListClear(view.pointer)
            for box in boxes where filled {
                placeInRow(box)
                filled = actionUIWinUIListAppendElement(view.pointer, box.pointer)
            }
            if !filled {
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("showing the children"))", .error)
                state.shownBoxes = nil
            }
        }
        let position = RowSelection.selectedChildID(value: node.model.value).flatMap { ids.firstIndex(of: $0) }
        select(view, state, position)
    }

    /// At the row's leading edge, as SwiftUI's rows put their content (a box given the whole row would
    /// center it); an element that fills still spans the row.
    private static func placeInRow(_ box: WinUIObject) {
        if !actionUIWinUIElementSetAlignment(box.pointer, ActionUIWinUIAlignStart, ActionUIWinUIAlignCenter) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("placing a row"))", .error)
        }
    }

    // MARK: Template rows

    private static func updateTemplateRows(_ view: WinUIObject, _ node: RenderNode, _ state: ListState,
                                           _ template: any ActionUIElementBase) {
        let rows = node.model.states["content"] as? [[String]] ?? []
        state.drawnRows = rows
        state.shownIndices = Array(rows.indices)
        for (index, row) in rows.enumerated() {
            // A row shown with the same data at the same place keeps its instance (and its objects'
            // state); its index is in the instance's TemplateContext, the one its actions report.
            if index < state.rowNodes.count, state.rowNodes[index].model.templateContext?.row == row { continue }
            let rowNode = node.templateRowNode(template, row: row, rowIndex: index)
            // Replacing the selected row drops its selection: the renderer's change, not the user's.
            state.shownIndex = -1
            let shown: Bool
            if let box = rowNode.outerView {
                placeInRow(box)
                shown = index < state.rowNodes.count
                    ? actionUIWinUIListReplaceElement(view.pointer, Int32(index), box.pointer)
                    : actionUIWinUIListAppendElement(view.pointer, box.pointer)
            } else {
                shown = false
            }
            guard shown else {
                // The rows shown keep their instances; the next update tries again from here.
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("showing a template row"))", .error)
                node.releaseTemplateNode(rowNode)
                break
            }
            if index < state.rowNodes.count {
                node.releaseTemplateNode(state.rowNodes[index])
                state.rowNodes[index] = rowNode
            } else {
                state.rowNodes.append(rowNode)
            }
        }
        if state.rowNodes.count > rows.count {
            state.shownIndex = -1
            if actionUIWinUIListTruncate(view.pointer, Int32(rows.count)) {
                for rowNode in state.rowNodes[rows.count...] {
                    node.releaseTemplateNode(rowNode)
                }
                state.rowNodes.removeLast(state.rowNodes.count - rows.count)
            } else {
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("removing template rows"))", .error)
            }
        }
        // A row not shown (it failed above) takes no selection.
        let position = RowSelection.selectedIndex(value: node.model.value, in: rows).flatMap { $0 < state.rowNodes.count ? $0 : nil }
        select(view, state, position)
    }

    /// Shows `position` (nil: none) as the selected row, remembering it as the renderer's own.
    private static func select(_ view: WinUIObject, _ state: ListState, _ position: Int?) {
        let index = Int32(position ?? -1)
        state.shownIndex = index
        if !actionUIWinUIListSetSelectedIndex(view.pointer, index) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("selecting a row"))", .error)
        }
        // What the ListView shows (it may refuse a selection while not selectable).
        state.shownIndex = actionUIWinUIListGetSelectedIndex(view.pointer)
    }

    // MARK: Input

    /// The user selected the row at `position` (nil: a deselect).
    private static func userSelected(_ node: RenderNode, _ state: ListState, position: Int?) {
        let props = Props(node.properties)
        switch state.mode {
        case .rows, .template:
            let index = position.flatMap { state.shownIndices.indices.contains($0) ? state.shownIndices[$0] : nil }
            guard let clicked = RowSelection.clickedRow(index: index, in: state.drawnRows) else { return }
            RowSelection.commitRowSelection(clicked, drawnRows: state.drawnRows, model: node.model, actionID: props.actionID,
                                            windowUUID: node.windowModel.windowUUID, viewID: node.element.id)
        case .children:
            let ids = state.childIDs ?? []
            let childID = position.flatMap { ids.indices.contains($0) ? ids[$0] : nil }
            RowSelection.commitChildSelection(childID, model: node.model, actionID: props.actionID,
                                              windowUUID: node.windowModel.windowUUID, viewID: node.element.id)
        }
    }

    /// A double click or Return on a row: as SwiftUI's primaryAction, the row becomes the value and
    /// doubleClickActionID fires with its index in the content; when that changes the selection,
    /// actionID fires first, as the first click of a double click fires it (as on Linux).
    private static func userActivated(_ node: RenderNode, _ state: ListState, position: Int?) {
        let props = Props(node.properties)
        guard state.mode != .children, let doubleClickActionID = props.doubleClickActionID, let position,
              state.shownIndices.indices.contains(position) else { return }
        let index = state.shownIndices[position]
        let current = node.model.states["content"] as? [[String]] ?? []
        let row = ActionUIModel.reconciledSelection(state.drawnRows[index], from: state.drawnRows, to: current)
        let changed = (node.model.value as? [String] ?? []) != row
        node.model.value = row
        let windowUUID = node.windowModel.windowUUID
        if changed, let actionID = props.actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0)
        }
        ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0,
                                           context: index)
    }
}
