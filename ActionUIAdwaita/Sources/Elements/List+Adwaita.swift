// Sources/Elements/List+Adwaita.swift
/*
 List on GTK: a GtkListBox in a GtkScrolledWindow, as greedy as SwiftUI's List (it shares a stack
 like a Color, measured: the list-in-hstack-shares and list-in-vstack-shares layout parity
 fixtures). Its three forms:

 - Rows (Form 1): one row per content row (setElementRows) whose first column is not empty,
   showing the first column in the cell itemType.viewType names: a Text; a Button at its natural
   width at the leading edge, taking the inherited buttonStyle, whose click fires itemType.actionID
   with the text (or with the row's index in the content for actionContext rowIndex); an Image
   reading the text as itemType.dataInterpretation says, a symbol at Image's medium size or a file
   at its own size. Selectable whether or not an actionID is set: a selection the user makes
   becomes the value (the row's columns) and fires actionID (Core RowSelection); a double click (or
   Return) fires doubleClickActionID with the row's index in the content.
 - Children (Form 2): one row per child element's box. With an actionID, selectable: the value is
   the selected child's id as text, and actionID fires with the id as its context; without one,
   the rows are not selectable and the children handle their own input.
 - Template (Form 3): one row per content row, the template element shown with the row's data
   ($1 is its first column; RenderNode.templateRowNode), selected and activated as rows are. A
   row whose data or place changes is made again; the others keep their widgets.

 The value selects its row when a host sets it; a rows change keeps the selection on its row
 (Core). Styles: automatic, inset and plain show rows separated by lines, as macOS draws them;
 sidebar uses libadwaita's navigation-sidebar; grouped and insetGrouped its boxed-list cards.

 Not yet: AsyncImage cells (shown as text: Linux has no AsyncImage yet), the row styling
 properties; logged once each.
 onRefreshActionID does nothing (pull to refresh; desktops have none). A template row whose data
 changes is made again, so a control in it loses keyboard focus after a toggle (SwiftUI keeps rows
 by index).
*/

import CAdwaita

@MainActor private var reportedViewType = false
@MainActor private var reportedRowStyling = false

/// A List's rows as last shown, attached to its scrolled window: the signal handlers map a row
/// back to its content row or child.
@MainActor
final class ListState {
    enum Mode {
        case rows, children, template
    }

    let box: WidgetPointer
    var mode = Mode.rows
    /// The content as drawn (rows mode), and the content index of each row shown.
    var drawnRows: [[String]] = []
    var shownIndices: [Int] = []
    /// The cell the rows show (rows mode), how an image cell reads its text, and each row's text as
    /// shown: a row whose text and cell are unchanged is left alone.
    var cellType = List.Props.ViewType.text
    var cellInterpretation = List.Props.DataInterpretation.systemName
    var cellTexts: [String] = []
    /// The element id of each row's child (children mode).
    var childIDs: [Int] = []
    /// Each row's template instance (template mode).
    var rowNodes: [RenderNode] = []
    /// The list's environment when the rows were last updated: the rows are not child nodes, so
    /// the list's sync does not pass a changed environment on to them.
    var rowEnvironment = Environment()
    /// True from a click in the list until the main loop runs after the click ends, and from a key
    /// press until the main loop runs after it: a selection made then is the user's. GTK also
    /// selects the row focus moves onto (the first one when the window gives the list its first
    /// focus); that one is not.
    var userInput = false
    /// Counts the presses: the end of an earlier one does not end a later one.
    var inputSerial = 0

    init(box: WidgetPointer) {
        self.box = box
    }
}

let listStateKey = AttachKey<ListState>("actionui-list")

extension List: ActionUIAdwaitaRenderer {
    /// macOS's list rows: a line of body text 4 points from the row's top and bottom, 8 points
    /// in from the row's edges inside a list inset by 8. An Image cell's symbol is Image's
    /// medium size.
    static let rowRules = """
        list.actionui-list { padding: 4px 8px; }
        list.actionui-list > row { padding: 4px 8px; min-height: 16px; }
        image.actionui-list-icon { -gtk-icon-size: 1.1em; }
        """

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StyleSheet.shared.installFixedRules("actionui-list", rowRules)
        let scroller = gtk_scrolled_window_new()!
        gtk_scrolled_window_set_policy(OpaquePointer(scroller), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        gtk_widget_set_hexpand(scroller, 1)
        gtk_widget_set_vexpand(scroller, 1)
        let box = gtk_list_box_new()!
        // A double click (or Return) activates a row; a single click selects it.
        gtk_list_box_set_activate_on_single_click(OpaquePointer(box), 0)
        gtk_scrolled_window_set_child(OpaquePointer(scroller), box)
        let state = ListState(box: box)
        attach(state, to: scroller, key: listStateKey)
        watchUserInput(box, state)
        connectUserSignal(box, "row-selected", .instanceAndArgument) { [weak node] in
            guard let node else { return }
            userSelected(node, state)
        }
        connectUserSignal(box, "row-activated", .instanceAndArgument) { [weak node] in
            guard let node else { return }
            userActivated(node, state)
        }
        return scroller
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: listStateKey) else { return }
        let props = Props(node.properties)
        applyStyle(state.box, props.listStyle)
        reportGaps(node, props)

        let children = node.subviews("children")
        let template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase
        let mode: ListState.Mode = template != nil ? .template : children.isEmpty ? .rows : .children
        if mode != state.mode {
            removeAllRows(state, node)
            state.mode = mode
        }
        let box = OpaquePointer(state.box)
        switch mode {
        case .rows, .template:
            let selectable = GTK_SELECTION_SINGLE
            if gtk_list_box_get_selection_mode(box) != selectable {
                gtk_list_box_set_selection_mode(box, selectable)
            }
            if let template {
                // A kept row sees a changed environment (labelsHidden on the list); new rows
                // compute theirs when made.
                if node.environment != state.rowEnvironment {
                    state.rowEnvironment = node.environment
                    for rowNode in state.rowNodes {
                        SyncScheduler.shared.markDirty(rowNode)
                    }
                }
                updateTemplateRows(state, node, template)
            } else {
                updateRows(state, node, props)
            }
        case .children:
            let selectable = props.actionID == nil ? GTK_SELECTION_NONE : GTK_SELECTION_SINGLE
            if gtk_list_box_get_selection_mode(box) != selectable {
                gtk_list_box_set_selection_mode(box, selectable)
            }
            updateChildren(state, node, children)
        }
    }

    // MARK: Rows

    private static func updateRows(_ state: ListState, _ node: RenderNode, _ props: Props) {
        let items = node.model.states["content"] as? [[String]] ?? []
        let shown = shownRowIndices(items)
        state.drawnRows = items
        state.shownIndices = shown
        let box = OpaquePointer(state.box)
        // AsyncImage cells are text until Linux has AsyncImage.
        let cellType = props.viewType == .asyncImage ? .text : props.viewType
        if cellType != state.cellType || (cellType == .image && props.dataInterpretation != state.cellInterpretation) {
            gtk_list_box_remove_all(box)
            state.cellTexts = []
            state.cellType = cellType
            state.cellInterpretation = props.dataInterpretation
        }
        for (position, index) in shown.enumerated() {
            let text = items[index][0]
            if position < state.cellTexts.count {
                guard state.cellTexts[position] != text else { continue }
                state.cellTexts[position] = text
                if let row = gtk_list_box_get_row_at_index(box, Int32(position)) {
                    setCellText(row, text, state)
                }
            } else {
                state.cellTexts.append(text)
                gtk_list_box_append(box, makeCell(text, state, node))
            }
        }
        while let extra = gtk_list_box_get_row_at_index(box, Int32(shown.count)) {
            gtk_list_box_remove(box, typed(extra))
        }
        state.cellTexts.removeLast(max(0, state.cellTexts.count - shown.count))
        if cellType == .button {
            // The inherited buttonStyle, as SwiftUI's Button cells take it.
            var position: Int32 = 0
            while let row = gtk_list_box_get_row_at_index(box, position), let button = gtk_list_box_row_get_child(row) {
                Button.applyStyle(button, node.environment.buttonStyle, role: nil)
                position += 1
            }
        }
        let selected = RowSelection.selectedIndex(value: node.model.value, in: items).flatMap { shown.firstIndex(of: $0) }
        select(state, position: selected)
    }

    /// A new row's cell showing `text`, of the state's cell type.
    private static func makeCell(_ text: String, _ state: ListState, _ node: RenderNode) -> WidgetPointer {
        switch state.cellType {
        case .text, .asyncImage:
            return rowLabel(text)
        case .button:
            // At its natural width at the leading edge, as SwiftUI's Button cell.
            let button = gtk_button_new_with_label(text)!
            gtk_widget_set_halign(button, GTK_ALIGN_START)
            gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
            connectUserSignal(button, "clicked", .instanceOnly) { [weak node, weak state] in
                guard let node, let state else { return }
                buttonClicked(button, node, state)
            }
            return button
        case .image:
            return imageCell(text, state.cellInterpretation)
        }
    }

    /// Shows `text` in an existing row's cell.
    private static func setCellText(_ row: UnsafeMutablePointer<GtkListBoxRow>, _ text: String, _ state: ListState) {
        switch state.cellType {
        case .text, .asyncImage:
            if let label = gtk_list_box_row_get_child(row) { Gtk.Label(label).text = text }
        case .button:
            if let button = gtk_list_box_row_get_child(row) { gtk_button_set_label(typed(button), text) }
        case .image:
            // A symbol and a file are different widgets.
            gtk_list_box_row_set_child(row, imageCell(text, state.cellInterpretation))
        }
    }

    /// A row's text: wrapped, at the leading edge, as SwiftUI draws a Text in a List.
    private static func rowLabel(_ text: String) -> WidgetPointer {
        let label = gtk_label_new(text)!
        gtk_label_set_xalign(opaque(label), 0)
        gtk_label_set_wrap(opaque(label), 1)
        gtk_label_set_wrap_mode(opaque(label), PANGO_WRAP_WORD_CHAR)
        return label
    }

    /// An Image cell: the text read as itemType.dataInterpretation says (ImageSource, as SwiftUI's
    /// cell reads it), shown as Image shows it unresized: a symbol at the font's icon size, a file
    /// at its own size; at the leading edge.
    private static func imageCell(_ text: String, _ interpretation: Props.DataInterpretation) -> WidgetPointer {
        let content = Image.content(ImageSource.resolve(text, interpretation: interpretation.rawValue, lookup: Image.lookup))
        let widget: WidgetPointer
        if case .file(let path) = content {
            widget = gtk_picture_new_for_filename(path)!
            gtk_picture_set_can_shrink(opaque(widget), 0)
        } else {
            widget = gtk_image_new_from_icon_name(Image.iconName(content))!
            Gtk.Widget(widget).setCSSClass("actionui-list-icon", true)
        }
        gtk_widget_set_halign(widget, GTK_ALIGN_START)
        gtk_widget_set_valign(widget, GTK_ALIGN_CENTER)
        return widget
    }

    /// A Button cell's click: itemType.actionID fires with the row's text, or its index in the
    /// content when actionContext is rowIndex, as SwiftUI's cell fires it.
    private static func buttonClicked(_ button: WidgetPointer, _ node: RenderNode, _ state: ListState) {
        guard let row = gtk_widget_get_parent(button) else { return }
        let position = Int(gtk_list_box_row_get_index(typed(row)))
        guard state.shownIndices.indices.contains(position) else { return }
        let index = state.shownIndices[position]
        let props = Props(node.properties)
        node.fire(props.itemActionID, context: props.actionContext == .rowIndex ? index : state.drawnRows[index][0])
    }

    // MARK: Template rows

    private static func updateTemplateRows(_ state: ListState, _ node: RenderNode, _ template: any ActionUIElementBase) {
        let rows = node.model.states["content"] as? [[String]] ?? []
        state.drawnRows = rows
        state.shownIndices = Array(rows.indices)
        let box = OpaquePointer(state.box)
        for (index, row) in rows.enumerated() {
            // A row shown with the same data at the same place keeps its instance (and its widgets'
            // state); its index is in the instance's TemplateContext, the one its actions report.
            if index < state.rowNodes.count, state.rowNodes[index].model.templateContext?.row == row { continue }
            let rowNode = node.templateRowNode(template, row: row, rowIndex: index)
            if index < state.rowNodes.count {
                state.rowNodes[index].detach()
                if let old = gtk_list_box_get_row_at_index(box, Int32(index)) {
                    gtk_list_box_remove(box, typed(old))
                }
                state.rowNodes[index] = rowNode
            } else {
                state.rowNodes.append(rowNode)
            }
            insertHolder(box, rowNode.outerWidget, at: index)
        }
        while state.rowNodes.count > rows.count {
            state.rowNodes.removeLast().detach()
            if let extra = gtk_list_box_get_row_at_index(box, Int32(rows.count)) {
                gtk_list_box_remove(box, typed(extra))
            }
        }
        select(state, position: RowSelection.selectedIndex(value: node.model.value, in: rows))
    }

    /// Puts an element's box in a new row at `index`, in a holder that places it at the leading edge,
    /// as SwiftUI places a row's content; one that expands fills the row.
    private static func insertHolder(_ box: OpaquePointer, _ outer: WidgetPointer, at index: Int) {
        let holder = ListRowLayout.makeHolder()
        if gtk_widget_get_parent(outer) != nil {
            gtk_widget_unparent(outer)
        }
        gtk_widget_set_parent(outer, holder)
        gtk_list_box_insert(box, holder, Int32(index))
    }

    // MARK: Children

    private static func updateChildren(_ state: ListState, _ node: RenderNode, _ children: [any ActionUIElementBase]) {
        let box = OpaquePointer(state.box)
        node.syncChildren(children, insert: { child, index in
            let outer: WidgetPointer = child.outerWidget
            let row = Self.row(of: outer)
            if let row, gtk_list_box_row_get_index(typed(row)) == Int32(index) { return }
            if let row {
                // Moved: the node keeps the box alive while its row (and holder) goes.
                gtk_list_box_remove(box, row)
            }
            insertHolder(box, outer, at: index)
        }, remove: { child in
            if let row = Self.row(of: child.outerWidget) {
                gtk_list_box_remove(box, row)
            }
        })
        state.childIDs = children.map(\.id)
        let selected = RowSelection.selectedChildID(value: node.model.value).flatMap { state.childIDs.firstIndex(of: $0) }
        select(state, position: selected)
    }

    /// The list row holding a child's box (inside the holder that aligns it).
    private static func row(of outer: WidgetPointer) -> WidgetPointer? {
        Gtk.Widget(outer).parent?.parent?.pointer
    }

    // MARK: Selection

    /// Shows the selection at `position` among the rows (none for nil), without firing anything
    /// (the update runs inside UpdateGuard).
    private static func select(_ state: ListState, position: Int?) {
        let box = OpaquePointer(state.box)
        let current = gtk_list_box_get_selected_row(box).map { Int(gtk_list_box_row_get_index($0)) }
        guard current != position else { return }
        if let position, let row = gtk_list_box_get_row_at_index(box, Int32(position)) {
            gtk_list_box_select_row(box, row)
        } else {
            gtk_list_box_unselect_all(box)
        }
    }

    /// The position of the selected row, or nil.
    private static func selectedPosition(_ state: ListState) -> Int? {
        gtk_list_box_get_selected_row(OpaquePointer(state.box)).map { Int(gtk_list_box_row_get_index($0)) }
    }

    private static func userSelected(_ node: RenderNode, _ state: ListState) {
        guard state.userInput else {
            // GTK's selection of a focused row, not the user's: show the model's again.
            UpdateGuard.applying { select(state, position: modelPosition(node, state)) }
            return
        }
        let props = Props(node.properties)
        let position = selectedPosition(state)
        switch state.mode {
        case .rows, .template:
            let index = position.flatMap { state.shownIndices.indices.contains($0) ? state.shownIndices[$0] : nil }
            guard let clicked = RowSelection.clickedRow(index: index, in: state.drawnRows) else { return }
            RowSelection.commitRowSelection(clicked, drawnRows: state.drawnRows, model: node.model, actionID: props.actionID,
                                            windowUUID: node.windowUUID, viewID: node.element.id)
        case .children:
            let childID = position.flatMap { state.childIDs.indices.contains($0) ? state.childIDs[$0] : nil }
            RowSelection.commitChildSelection(childID, model: node.model, actionID: props.actionID,
                                              windowUUID: node.windowUUID, viewID: node.element.id)
        }
    }

    /// A double click or Return on a row: as SwiftUI's primaryAction, the row becomes the value and
    /// doubleClickActionID fires with its index in the content. When that changes the selection
    /// (Return on a row reached with Tab selects it in the same press), actionID fires first, as
    /// the first click of a double click fires it.
    private static func userActivated(_ node: RenderNode, _ state: ListState) {
        let props = Props(node.properties)
        guard state.mode != .children, let actionID = props.doubleClickActionID,
              let position = selectedPosition(state), state.shownIndices.indices.contains(position) else { return }
        let index = state.shownIndices[position]
        let current = node.model.states["content"] as? [[String]] ?? []
        let row = ActionUIModel.reconciledSelection(state.drawnRows[index], from: state.drawnRows, to: current)
        let changed = (node.model.value as? [String] ?? []) != row
        node.model.value = row
        if changed {
            node.fire(props.actionID)
        }
        node.fire(actionID, context: index)
    }

    // MARK: Style

    private static func applyStyle(_ box: WidgetPointer, _ style: Props.ListStyle?) {
        let widget = Gtk.Widget(box)
        let sidebar = style == .sidebar
        let cards = style == .grouped || style == .insetGrouped
        widget.setCSSClass("actionui-list", !sidebar && !cards)
        widget.setCSSClass("navigation-sidebar", sidebar)
        widget.setCSSClass("boxed-list", cards)
        let separators: gboolean = !sidebar && !cards ? 1 : 0
        if gtk_list_box_get_show_separators(OpaquePointer(box)) != separators {
            gtk_list_box_set_show_separators(OpaquePointer(box), separators)
        }
    }

    private static func removeAllRows(_ state: ListState, _ node: RenderNode) {
        let box = OpaquePointer(state.box)
        if state.mode == .children {
            // The child nodes go too; a later children update makes them again.
            node.syncChildren([], insert: { _, _ in }, remove: { child in
                if let row = Self.row(of: child.outerWidget) {
                    gtk_list_box_remove(box, row)
                }
            })
        }
        for rowNode in state.rowNodes {
            rowNode.detach()
        }
        state.rowNodes = []
        gtk_list_box_remove_all(box)
        state.drawnRows = []
        state.shownIndices = []
        state.cellTexts = []
        state.childIDs = []
    }

    private static func reportGaps(_ node: RenderNode, _ props: Props) {
        let logger = ActionUIModel.shared.logger
        if !reportedViewType, props.viewType == .asyncImage {
            reportedViewType = true
            logger.log("List: AsyncImage cells are shown as text on Linux for now", .warning)
        }
        if !reportedRowStyling, props.hasRowModifiers {
            reportedRowStyling = true
            logger.log("List: row styling (listRowBackground, listRowSeparator, listRowInsets) is not applied on Linux yet", .warning)
        }
    }
}

extension List {
    /// Marks the list's clicks and key presses (seen in the capture phase, before the list handles
    /// them) as the user's: a click until the main loop runs after its gesture ends (released or
    /// canceled; "stopped" also comes while the button is down: the double-click timer, a press
    /// away from the last click, a small drag), a key press until the main loop runs after it (the
    /// list selects while handling the press; a key that moves focus out sends its release
    /// elsewhere).
    fileprivate static func watchUserInput(_ box: WidgetPointer, _ state: ListState) {
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, 0)
        gtk_event_controller_set_propagation_phase(click, GTK_PHASE_CAPTURE)
        connectSignal(UnsafeMutableRawPointer(click), "pressed", .press) { [weak state] in beginUserInput(state) }
        connectSignal(UnsafeMutableRawPointer(click), "end", .instanceAndArgument) { [weak state] in endUserInput(state) }
        gtk_widget_add_controller(box, click)
        let keys = gtk_event_controller_key_new()!
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE)
        connectKeyPressed(UnsafeMutableRawPointer(keys)) { [weak state] _ in
            beginUserInput(state)
            endUserInput(state)
            return false
        }
        gtk_widget_add_controller(box, keys)
    }

    fileprivate static func beginUserInput(_ state: ListState?) {
        guard let state else { return }
        state.userInput = true
        state.inputSerial &+= 1
    }

    /// After the event's handlers (the list selects on a click's release) have run, unless another
    /// press came first.
    fileprivate static func endUserInput(_ state: ListState?) {
        guard let serial = state?.inputSerial else { return }
        runAfter(milliseconds: 0) { [weak state] in
            guard let state, state.inputSerial == serial else { return }
            state.userInput = false
        }
    }

    /// The position among the rows of the model's selection.
    fileprivate static func modelPosition(_ node: RenderNode, _ state: ListState) -> Int? {
        switch state.mode {
        case .rows, .template:
            return RowSelection.selectedIndex(value: node.model.value, in: state.drawnRows).flatMap { state.shownIndices.firstIndex(of: $0) }
        case .children:
            return RowSelection.selectedChildID(value: node.model.value).flatMap { state.childIDs.firstIndex(of: $0) }
        }
    }
}
