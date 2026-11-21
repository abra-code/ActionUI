// Sources/Elements/List+WinUI.swift
/*
 List on WinUI: Windows' ListView, as greedy as SwiftUI's List (it shares a stack like a Color, as on
 Linux), in the forms the Linux renderer has:

 - Rows (Form 1): one row per content row (setElementRows) whose first column is not empty, showing
   the first column in the cell itemType.viewType names, as on Linux: a Text; a Button at its
   natural width at the leading edge, whose click fires itemType.actionID with the text (or with the
   row's index in the content for actionContext rowIndex); an Image reading the text as
   itemType.dataInterpretation says, a symbol at Image's medium size or a file at its own size.
   Selectable: a selection the user makes becomes the value (the row's columns) and fires actionID
   (Core RowSelection); a double click (or Return) fires doubleClickActionID with the row's index in
   the content, the row becoming the value first (and actionID firing when that changed it), as on
   Linux.
 - Children (Form 2): one row per child element's box. With an actionID, selectable: the value is
   the selected child's id as text, and actionID fires with the id as its context; without one, the
   rows are not selectable and the children handle their own input. As a NavigationStack's content
   with destinations, choosing a child pushes the one its destinationViewId names (after the
   selection and its action); as a NavigationSplitView's sidebar with destinations, it is selectable
   without an actionID too, and the detail shows the chosen child's destination.
 - Template (Form 3): one row per content row, the template element shown with the row's data ($1
   is its first column; RenderNode.templateRowNode), selected and activated as rows are. A row whose
   data or place changes is made again; the others keep their objects, as on Linux.

 Rows are made as they come into view: the ListView makes containers only for the rows in or near
 view, and the rows that are elements (Button and Image cells, template instances) come from an
 element source (the shim's ListView element source): an element is made when the ListView shows its
 row and let go when it recycles the row, so a List of thousands of rows makes tens. A row let go loses
 only transient state (keyboard focus); its data is in the content rows. A source row is named for
 accessibility tools by its label, made or not: a cell's text (an Image cell's file by its name), or a
 template row's columns joined. Text rows are the ListView's own items (plain text, which it shows in
 view only); the children form adds every child's box.

 The value selects its row when a host sets it; the ListView reports that selection as it reports
 the user's, and the renderer ignores the one it made (ListState.shownIndex), so actionID fires only
 for the user's.

 Not yet: itemType's AsyncImage cell (text for now); the inherited buttonStyle on Button cells; listStyle and the row styling (listRowBackground, listRowSeparator,
 listRowSeparatorTint, listRowInsets); pull to refresh (desktops have none). A change of any text row
 makes every text row again; an Image cell reads its file when its row is made (a file rewritten
 under the same name shows the old picture until the row is made again). A template row's name for
 accessibility tools includes an Image's symbol name as written, where VoiceOver reads the symbol's own
 description.
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
    /// The cell the rows show (rows mode), as last made.
    var shownCell: RowCell?
    /// The element id of each row's child, and the boxes the rows show (children mode): a child
    /// replaced under the same id has a new node and box.
    var childIDs: [Int]?
    var shownBoxes: [WinUIObject]?
    /// What the element source's rows are (nil: the ListView shows its own items), the rows as given
    /// to it (a cell row's text, or a template row's columns), and the template.
    var sourceKind: SourceKind?
    var sourceRows: [[String]] = []
    var template: (any ActionUIElementBase)?
    /// The source's rows made (in or near view): each one's element, and its template instance.
    var made: [(element: WinUIObject, instance: RenderNode?)] = []
    /// The row the renderer last selected: a selection event reporting it is the renderer's own.
    var shownIndex: Int32 = -1

    /// The rows an element source shows: element cells (Button or Image) of the content's texts, or
    /// the template's instances of the content rows. Text rows and children are the ListView's own items.
    enum SourceKind: Equatable {
        case cells(RowCell)
        case template
    }

    /// A rows-mode cell: its type, how an Image cell reads its text, and an Image symbol's side (its
    /// font's), each 0 or the default when the type does not use it.
    struct RowCell: Equatable {
        var type = List.Props.ViewType.text
        var interpretation = List.Props.DataInterpretation.systemName
        var symbolSide = 0.0
    }
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
        let box = ListSourceBox()
        box.node = node
        if !actionUIWinUIListSetElementSource(list.pointer, makeListRow, recycleListRow, Unmanaged.passRetained(box).toOpaque(),
                                              releaseListSourceBox) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("registering the rows' source"))", .error)
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
            // A split view's sidebar of destinations can be chosen in without an actionID, as on Apple.
            setSelectable(view, state, props.actionID != nil || NavigationSplitView.isDestinationSidebar(node))
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
            break
        }
        leaveSource(view, node, state)
        state.shownIndex = -1
        if !actionUIWinUIListClear(view.pointer) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("clearing the rows"))", .error)
        }
        state.drawnRows = []
        state.shownIndices = []
        state.shownTexts = nil
        state.shownCell = nil
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
        let cell = rowCell(node)
        if cell.type == .button || cell.type == .image {
            // Element cells, made as their rows come into view.
            state.shownTexts = nil
            state.shownCell = cell
            showSourceRows(view, node, state, kind: .cells(cell), rows: texts.map { [$0] })
        } else {
            // Text rows: the ListView's own items, which it shows in view only (plain text costs little).
            leaveSource(view, node, state)
            if texts != state.shownTexts || cell != state.shownCell {
                state.shownTexts = texts
                state.shownCell = cell
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
        }
        let position = RowSelection.selectedIndex(value: node.model.value, in: items).flatMap { shown.firstIndex(of: $0) }
        select(view, state, position)
    }

    /// The cell itemType names. Tracked reads of the properties (and of the font, for a symbol's side).
    private static func rowCell(_ node: RenderNode) -> ListState.RowCell {
        let props = Props(node.properties)
        switch props.viewType {
        case .image:
            return ListState.RowCell(type: .image, interpretation: props.dataInterpretation,
                                     symbolSide: ImageLayout.symbolSide(node, scale: nil))
        case .button:
            return ListState.RowCell(type: .button)
        case .text, .asyncImage:
            return ListState.RowCell(type: .text)
        }
    }

    /// A Button cell titled `text`; its click fires itemType.actionID.
    private static func buttonCell(_ text: String, _ node: RenderNode, _ state: ListState, position: Int) -> WinUIObject? {
        guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()),
              actionUIWinUIButtonSetTitle(button.pointer, text) else {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("making a Button cell"))", .error)
            return nil
        }
        // A row whose text changes is made again, so the position stays this button's.
        WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a List's Button cell") { [weak node, weak state] in
            guard let node, let state, node.isAttached else { return }
            buttonClicked(node, state, position: position)
        }
        return button
    }

    /// An Image cell: the text read as itemType.dataInterpretation says (ImageSource, as SwiftUI's cell
    /// reads it), shown as Image shows it unresized: a symbol at the font's medium symbol size, in the
    /// color WinUI gives the row's content (as a text row's); a file at its own size. Nil when the shim has no symbol for the name.
    static func imageCell(_ text: String, _ cell: ListState.RowCell) -> WinUIObject? {
        // As Image reads its value: the "mixed" rules take a path by its "/"; a Windows path has
        // backslashes ("C:\pics\a.png").
        let interpretation = cell.interpretation == .mixed && text.contains("\\") ? "path" : cell.interpretation.rawValue
        let content = Image.content(ImageSource.resolve(text, interpretation: interpretation, lookup: Image.lookup))
        guard let child = Image.makeChild(content) else { return nil }
        let shown: Bool
        switch content {
        case .file(let path):
            shown = actionUIWinUIImageSetFile(child.pointer, path) && actionUIWinUIImageSetStretch(child.pointer, ActionUIWinUIImageStretchNone)
        case .symbol:
            shown = actionUIWinUISymbolSetSize(child.pointer, cell.symbolSide)
        }
        if !shown {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("showing an Image cell \(text)"))", .error)
        }
        return child
    }

    /// A Button cell's click: itemType.actionID fires with the row's text, or its index in the content
    /// when actionContext is rowIndex, as SwiftUI's cell fires it.
    private static func buttonClicked(_ node: RenderNode, _ state: ListState, position: Int) {
        let props = Props(node.properties)
        guard let actionID = props.itemActionID, state.shownIndices.indices.contains(position) else { return }
        let index = state.shownIndices[position]
        let context: Any = props.actionContext == .rowIndex ? index : state.drawnRows[index][0]
        ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id,
                                           viewPartID: 0, context: context)
    }

    // MARK: Children

    private static func updateChildren(_ view: WinUIObject, _ node: RenderNode, _ state: ListState, _ elements: [any ActionUIElementBase]) {
        leaveSource(view, node, state)
        // A child with no object (its placeholder failed too) has no row: the ids stay in step with the rows.
        // An EmptyView has none either, as in SwiftUI (measured on macOS 27).
        let childNodes = node.syncChildren(elements).filter { $0.outerView != nil && !$0.takesNoPlace }
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
        state.template = template
        // One instance per row, made as the row comes into view (its index and data in the instance's
        // TemplateContext, the ones its actions report).
        showSourceRows(view, node, state, kind: .template, rows: rows)
        // A row not shown (it could not be added) takes no selection.
        let position = RowSelection.selectedIndex(value: node.model.value, in: rows).flatMap { $0 < state.sourceRows.count ? $0 : nil }
        select(view, state, position)
    }

    // MARK: Rows made as they come into view

    /// Makes the element source show `rows` as `kind`: a row whose data changes is made again, rows
    /// are added at and removed from the end, as the eager template form keeps its instances; a new
    /// kind starts over.
    private static func showSourceRows(_ view: WinUIObject, _ node: RenderNode, _ state: ListState,
                                       kind: ListState.SourceKind, rows: [[String]]) {
        if state.sourceKind != kind {
            leaveSource(view, node, state)
            // Clearing the own items drops their selection, reported at once: the renderer's change.
            state.shownIndex = -1
            guard actionUIWinUIListUseElementSource(view.pointer, true) else {
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("showing rows as they come into view"))", .error)
                return
            }
            state.sourceKind = kind
            state.sourceRows = []
        }
        let old = state.sourceRows
        // The rows first: the ListView may ask for an element as soon as they change.
        state.sourceRows = rows
        for index in 0..<min(old.count, rows.count) where old[index] != rows[index] {
            // Replacing the selected row drops its selection: the renderer's change, not the user's.
            state.shownIndex = -1
            if !actionUIWinUIListSourceReplace(view.pointer, Int32(index), rowLabel(rows[index], kind)) {
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("changing a row"))", .error)
            }
        }
        if rows.count < old.count {
            state.shownIndex = -1
            if !actionUIWinUIListSourceTruncate(view.pointer, Int32(rows.count)) {
                ActionUIModel.shared.logger.log("List: \(WinUIError.last("removing rows"))", .error)
            }
        } else if rows.count > old.count {
            for row in rows[old.count...] {
                if !actionUIWinUIListSourceAppend(view.pointer, rowLabel(row, kind)) {
                    ActionUIModel.shared.logger.log("List: \(WinUIError.last("adding rows"))", .error)
                    // The rows the ListView has: the next update adds the others.
                    state.sourceRows = Array(rows.prefix(max(Int(actionUIWinUIListSourceCount(view.pointer)), 0)))
                    break
                }
            }
        }
    }

    /// What accessibility tools name a source row by, made or not: a cell's text (an Image cell's file by
    /// its name, without its folder), or a template row's columns in order (the template's $0), as
    /// VoiceOver reads a row's parts one after another.
    private static func rowLabel(_ row: [String], _ kind: ListState.SourceKind) -> String {
        if case .cells(let cell) = kind, cell.type == .image, let text = row.first,
           let slash = text.lastIndex(where: { $0 == "/" || $0 == "\\" }), text.index(after: slash) < text.endIndex {
            return String(text[text.index(after: slash)...])
        }
        return row.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The ListView shows its own items again (empty); the rows made are let go.
    private static func leaveSource(_ view: WinUIObject, _ node: RenderNode, _ state: ListState) {
        guard state.sourceKind != nil else { return }
        // Leaving the source drops its selection, reported at once: the renderer's change, not the user's.
        state.shownIndex = -1
        if !actionUIWinUIListUseElementSource(view.pointer, false) {
            ActionUIModel.shared.logger.log("List: \(WinUIError.last("leaving the rows' source"))", .error)
        }
        for row in state.made {
            if let instance = row.instance {
                node.releaseTemplateNode(instance)
            }
        }
        state.made = []
        state.sourceKind = nil
        state.sourceRows = []
        state.shownTexts = nil
        state.shownBoxes = nil
    }

    /// The ListView shows row `index`: its element (a cell, or the template's instance, made and synced
    /// now: a layout pass is under way), placed at the row's leading edge. Nil when it cannot be made
    /// (an image the shim has no symbol for shows nothing, as Image does).
    fileprivate static func makeRow(_ node: RenderNode, _ index: Int) -> OpaquePointer? {
        guard node.isAttached, let state = node.state as? ListState, let kind = state.sourceKind,
              state.sourceRows.indices.contains(index) else { return nil }
        let row = state.sourceRows[index]
        let element: WinUIObject?
        var instance: RenderNode?
        switch kind {
        case .cells(let cell):
            let text = row.first ?? ""
            element = cell.type == .button ? buttonCell(text, node, state, position: index) : imageCell(text, cell)
        case .template:
            guard let template = state.template else { return nil }
            let made = node.templateRowNode(template, row: row, rowIndex: index)
            made.sync()
            instance = made
            element = made.outerView
        }
        guard let element else {
            if let instance {
                node.releaseTemplateNode(instance)
            }
            return nil
        }
        placeInRow(element)
        state.made.append((element, instance))
        return element.pointer
    }

    /// The ListView recycled a row's container: its element is let go (a template instance leaves the tree).
    fileprivate static func recycleRow(_ node: RenderNode, _ element: OpaquePointer) {
        guard let state = node.state as? ListState,
              let position = state.made.firstIndex(where: { actionUIWinUIObjectIsSame($0.element.pointer, element) }) else { return }
        let row = state.made.remove(at: position)
        if let instance = row.instance {
            node.releaseTemplateNode(instance)
        }
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
            // The content of a NavigationStack with destinations pushes the chosen child's; the sidebar
            // of a NavigationSplitView with destinations shows it in the detail.
            NavigationStack.contentListChose(node, childID: childID)
            NavigationSplitView.sidebarListChose(node, childID: childID)
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

/// The element source's callback context: a box with a weak reference to the List's node, so the
/// ListView (which holds the box) does not keep it alive.
@MainActor private final class ListSourceBox {
    weak var node: RenderNode?
}

private func listSourceBox(_ context: UnsafeMutableRawPointer?) -> ListSourceBox? {
    context.map { Unmanaged<ListSourceBox>.fromOpaque($0).takeUnretainedValue() }
}

// The element's address crosses the main actor's closure as a number (a pointer is not Sendable).
private let makeListRow: ActionUIWinUIRepeaterMake = { context, index in
    let box = listSourceBox(context)
    let address = MainActor.assumeIsolated {
        UInt(bitPattern: box?.node.flatMap { List.makeRow($0, Int(index)) })
    }
    return OpaquePointer(bitPattern: address)
}

private let recycleListRow: ActionUIWinUIRepeaterRecycle = { context, element in
    let box = listSourceBox(context)
    let address = UInt(bitPattern: element)
    MainActor.assumeIsolated {
        guard let node = box?.node, let element = OpaquePointer(bitPattern: address) else { return }
        List.recycleRow(node, element)
    }
}

// Gives back the reference passRetained took, once the ListView lets go of the source.
private let releaseListSourceBox: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<ListSourceBox>.fromOpaque(context).release()
}
