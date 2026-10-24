// Sources/Elements/Table+Adwaita.swift
/*
 Table on GTK: a GtkColumnView (GTK's multi-column list: column headers, columns the user resizes
 by dragging, a selected row) in a GtkScrolledWindow, as greedy as the List. One row per content
 row (setElementRows), all of them shown; a column shows that column of each row (empty when the
 row is shorter) in the cell its columnTypes entry names:

 - Text: one line at the leading edge, cut short with an ellipsis, as a macOS Table cell.
 - Button: the text as its title, or an image read as dataInterpretation says when that is set,
   taking the inherited buttonStyle; a click fires the entry's actionID with the column as
   viewPartID and the context actionContext names (the title, the row's index, the column's
   index, or {"row", "column"} as the web renderer sends it). A click does not select the row.
 - Image: the text read as dataInterpretation says, as a List's Image cell shows it.
 - AsyncImage: a spinner until the image has loaded (and when it cannot be loaded), then the image
   scaled to fit the row.
 - Toggle: a checkbox (or a switch, or a toggle button, by style) showing the text as a Bool; a
   user toggle writes "true" or "false" into the cell, keeps the selection where it was, and
   fires the entry's actionID with the column as viewPartID and the row's index as context (Core
   Table.commitCellToggle); disabledColumn's text, read the same way, disables it.

 Columns: widths are the ideal widths (100 when missing); the column with the largest takes the
 room left (each of them, when several have it), as the Apple renderer's columns do. minWidths
 (default the smaller of 10 and the ideal width) is the narrowest a drag makes a column, and a
 column that does not fill is never dragged wider than its ideal width.
 columnHeadersVisibility hidden hides the header row.

 Selection: a row the user selects becomes the value (its columns) and fires actionID (Core
 RowSelection), a deselect (Ctrl+click) too; a host's value selects its row and fires nothing; a
 rows change keeps the selection on its row (Core). A double click or Return makes the row the
 value and fires doubleClickActionID with its index, after actionID when the selection changes.

 Not yet: scrollContentBackground.
*/

import CAdwaita

/// A Table's column view and rows as last shown, attached to its scrolled window.
@MainActor
final class TableState {
    /// The column layout the columns were made for: a change makes them again.
    struct Columns: Equatable {
        var titles: [String]
        var types: [Table.Props.ColumnType]
        var widths: [Int]?
        var minWidths: [Int]?
    }

    let view: WidgetPointer
    /// The column view's selection model and the list it selects from: one empty string per row
    /// (a cell reads its row's text by position).
    let selection: OpaquePointer
    let items: OpaquePointer
    var columns: Columns?
    /// The content as drawn.
    var rows: [[String]] = []
    /// The cells bound to a row now (each a GtkColumnViewCell, a GtkListItem), with their column:
    /// a rows change shows the new text in them.
    var boundCells: [UnsafeMutableRawPointer: Int] = [:]
    var buttonStyle: BaseModifiers.ButtonStyleName?
    /// Whether a selection is the user's: GTK also selects when the rows change.
    let input: UserInputWatch

    init(view: WidgetPointer, selection: OpaquePointer, items: OpaquePointer) {
        self.view = view
        self.selection = selection
        self.items = items
        input = UserInputWatch(watching: view)
    }
}

let tableStateKey = AttachKey<TableState>("actionui-table")

/// A cell's widget and how it reads its text.
@MainActor
private final class TableCell {
    let item: UnsafeMutableRawPointer
    let column: Int
    let type: Table.Props.ColumnType
    /// The text the cell shows (for an AsyncImage cell waiting for its image).
    var text = ""

    init(item: UnsafeMutableRawPointer, column: Int, type: Table.Props.ColumnType) {
        self.item = item
        self.column = column
        self.type = type
    }
}

private let tableCellKey = AttachKey<TableCell>("actionui-table-cell")

extension Table: ActionUIAdwaitaRenderer {
    /// Rows as compact as macOS's. The rules are the application's, so they win over
    /// libadwaita's.
    static let tableRules = """
        columnview.actionui-table > listview > row > cell { padding-top: 2px; padding-bottom: 2px; }
        """

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StyleSheet.shared.installFixedRules("actionui-list", List.cellRules)
        StyleSheet.shared.installFixedRules("actionui-table", tableRules)
        let scroller = gtk_scrolled_window_new()!
        gtk_scrolled_window_set_policy(OpaquePointer(scroller), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
        gtk_widget_set_hexpand(scroller, 1)
        gtk_widget_set_vexpand(scroller, 1)
        // The selection model takes the list, the column view the selection model (transfer full).
        let items = gtk_string_list_new(nil)!
        let selection = gtk_single_selection_new(items)!
        // Nothing selected until the user or the host selects, and the user can deselect.
        gtk_single_selection_set_autoselect(selection, 0)
        gtk_single_selection_set_can_unselect(selection, 1)
        let view = gtk_column_view_new(selection)!
        Gtk.Widget(view).setCSSClass("actionui-table", true)
        Gtk.Widget(view).setCSSClass("data-table", true)
        gtk_column_view_set_reorderable(OpaquePointer(view), 0)
        gtk_scrolled_window_set_child(OpaquePointer(scroller), view)
        let state = TableState(view: view, selection: selection, items: items)
        attach(state, to: scroller, key: tableStateKey)
        connectUserSignal(UnsafeMutableRawPointer(selection), "notify::selected", .instanceAndArgument) { [weak node, weak state] in
            guard let node, let state else { return }
            userSelected(node, state)
        }
        connectPosition(UnsafeMutableRawPointer(view), "activate") { [weak node, weak state] position in
            guard let node, let state, !UpdateGuard.isApplying else { return }
            userActivated(node, state, position: Int(position))
        }
        return scroller
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: tableStateKey) else { return }
        let props = Props(node.properties)
        let columns = TableState.Columns(titles: props.columns, types: props.columnTypes,
                                         widths: props.widths, minWidths: props.minWidths)
        if columns != state.columns {
            state.columns = columns
            makeColumns(state, node, columns)
        }
        setHeaderVisible(state, props.columnHeadersVisibility != .hidden)
        let buttonStyle = node.environment.buttonStyle
        let restyle = buttonStyle != state.buttonStyle
        state.buttonStyle = buttonStyle
        let rows = node.model.states["content"] as? [[String]] ?? []
        if rows != state.rows || restyle {
            setRows(state, node, rows)
        }
        select(state, position: RowSelection.selectedIndex(value: node.model.value, in: rows))
    }

    // MARK: Columns

    /// The resolved width of each column (ideal, minimum, fills), by the Apple renderer's rule. A
    /// negative width counts as 0: GTK refuses a fixed width below -1.
    static func columnWidths(_ columns: TableState.Columns) -> [(ideal: Int, minimum: Int, fills: Bool)] {
        let ideals = columns.titles.indices.map { index in
            columns.widths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? 100
        }
        let largest = ideals.max() ?? 100
        return ideals.enumerated().map { index, ideal in
            let given = columns.minWidths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? min(ideal, 10)
            let minimum = max(given, 0)
            return (max(ideal, minimum), minimum, ideal == largest)
        }
    }

    /// A width a drag gives a column, kept between its minimum and, for a column that does not
    /// fill, its ideal width (the Apple renderer gives such a column that maximum). A width GTK
    /// leaves unset (-1) stays unset.
    static func clampedWidth(_ width: Int, _ bounds: (ideal: Int, minimum: Int, fills: Bool)) -> Int {
        guard width >= 0 else { return width }
        let wider = max(width, bounds.minimum)
        return bounds.fills ? wider : min(wider, bounds.ideal)
    }

    private static func makeColumns(_ state: TableState, _ node: RenderNode, _ columns: TableState.Columns) {
        let view = OpaquePointer(state.view)
        let existing = gtk_column_view_get_columns(view)!
        while g_list_model_get_n_items(existing) > 0, let column = g_list_model_get_item(existing, 0) {
            gtk_column_view_remove_column(view, OpaquePointer(column))
            g_object_unref(column)
        }
        for (index, width) in columnWidths(columns).enumerated() {
            let factory = cellFactory(state, node, column: index, type: columns.types[index])
            let column = gtk_column_view_column_new(columns.titles[index], OpaquePointer(factory.handOver()))!
            gtk_column_view_column_set_fixed_width(column, Int32(clamping: width.ideal))
            gtk_column_view_column_set_resizable(column, 1)
            gtk_column_view_column_set_expand(column, width.fills ? 1 : 0)
            // GTK lets a drag make a column as narrow as 0 and as wide as it likes; the width it sets
            // goes back between the bounds.
            connectSignal(UnsafeMutableRawPointer(column), "notify::fixed-width", .instanceAndArgument) {
                let dragged = Int(gtk_column_view_column_get_fixed_width(column))
                let allowed = clampedWidth(dragged, width)
                if allowed != dragged {
                    gtk_column_view_column_set_fixed_width(column, Int32(clamping: allowed))
                }
            }
            gtk_column_view_append_column(view, column)
            g_object_unref(UnsafeMutableRawPointer(column))
        }
    }

    /// The column view's header row (its child whose CSS name is "header").
    static func headerRow(_ state: TableState) -> Gtk.Widget? {
        Gtk.Widget(state.view).children.first { swiftString(gtk_widget_get_css_name($0.pointer)) == "header" }
    }

    private static func setHeaderVisible(_ state: TableState, _ visible: Bool) {
        guard let header = headerRow(state), header.isVisible != visible else { return }
        gtk_widget_set_visible(header.pointer, visible ? 1 : 0)
    }

    // MARK: Cells

    /// The factory of a column's cells: each cell's widget made once (setup), shown a row's text
    /// when bound to it.
    private static func cellFactory(_ state: TableState, _ node: RenderNode, column: Int, type: Props.ColumnType) -> OwnedObject {
        let factory = OwnedObject(adopting: gtk_signal_list_item_factory_new()!)
        connectObjectSignal(factory.pointer, "setup") { [weak node, weak state] item in
            guard let node, let state else { return }
            let cell = TableCell(item: item, column: column, type: type)
            let widget = makeCellWidget(cell, node, state)
            attach(cell, to: UnsafeMutableRawPointer(widget), key: tableCellKey)
            gtk_list_item_set_child(OpaquePointer(item), widget)
        }
        connectObjectSignal(factory.pointer, "bind") { [weak node, weak state] item in
            guard let node, let state else { return }
            state.boundCells[item] = column
            UpdateGuard.applying { showRow(item, state, node) }
        }
        connectObjectSignal(factory.pointer, "unbind") { [weak state] item in
            state?.boundCells[item] = nil
        }
        connectObjectSignal(factory.pointer, "teardown") { [weak state] item in
            state?.boundCells[item] = nil
        }
        return factory
    }

    /// A new cell's widget, of its column's type.
    private static func makeCellWidget(_ cell: TableCell, _ node: RenderNode, _ state: TableState) -> WidgetPointer {
        let widget: WidgetPointer
        switch cell.type.viewType {
        case .text:
            widget = gtk_label_new(nil)!
            gtk_label_set_xalign(opaque(widget), 0)
            gtk_label_set_ellipsize(opaque(widget), PANGO_ELLIPSIZE_END)
            gtk_label_set_single_line_mode(opaque(widget), 1)
        case .button:
            widget = gtk_button_new()!
            gtk_widget_set_halign(widget, GTK_ALIGN_START)
            gtk_widget_set_valign(widget, GTK_ALIGN_CENTER)
            connectUserSignal(widget, "clicked", .instanceOnly) { [weak node, weak state, weak cell] in
                guard let node, let state, let cell else { return }
                buttonClicked(cell, node, state)
            }
        case .image, .asyncImage:
            // The image goes in when the cell is bound.
            widget = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        case .toggle:
            switch cell.type.toggleStyle {
            case .checkbox:
                widget = gtk_check_button_new()!
                connectUserSignal(widget, "toggled", .instanceOnly) { [weak node, weak state, weak cell] in
                    guard let node, let state, let cell else { return }
                    userToggled(cell, Gtk.CheckButton(widget).isActive, node, state)
                }
            case .switch:
                widget = gtk_switch_new()!
                gtk_widget_set_valign(widget, GTK_ALIGN_CENTER)
                connectUserSignal(widget, "notify::active", .instanceAndArgument) { [weak node, weak state, weak cell] in
                    guard let node, let state, let cell else { return }
                    userToggled(cell, gtk_switch_get_active(opaque(widget)) != 0, node, state)
                }
            case .button:
                widget = gtk_toggle_button_new()!
                gtk_widget_set_valign(widget, GTK_ALIGN_CENTER)
                connectUserSignal(widget, "toggled", .instanceOnly) { [weak node, weak state, weak cell] in
                    guard let node, let state, let cell else { return }
                    userToggled(cell, gtk_toggle_button_get_active(typed(widget)) != 0, node, state)
                }
            }
            gtk_widget_set_halign(widget, GTK_ALIGN_START)
        }
        return widget
    }

    /// Shows a bound cell's row (run inside UpdateGuard: setting a toggle emits its signal).
    private static func showRow(_ item: UnsafeMutableRawPointer, _ state: TableState, _ node: RenderNode) {
        guard let widget = gtk_list_item_get_child(OpaquePointer(item)),
              let cell = attached(on: UnsafeMutableRawPointer(widget), key: tableCellKey) else { return }
        let position = Int(gtk_list_item_get_position(OpaquePointer(item)))
        guard state.rows.indices.contains(position) else { return }
        let row = state.rows[position]
        let text = cell.column < row.count ? row[cell.column] : ""
        let previous = cell.text
        cell.text = text
        switch cell.type.viewType {
        case .text:
            Gtk.Label(widget).text = text
        case .button:
            if let interpretation = cell.type.dataInterpretation {
                // The image is made again only for new text: a rows change shows every bound cell
                // again.
                if text != previous || gtk_button_get_child(typed(widget)) == nil {
                    let image = List.imageCell(text, List.Props.DataInterpretation(rawValue: interpretation.rawValue) ?? .systemName)
                    gtk_widget_set_halign(image, GTK_ALIGN_CENTER)
                    gtk_button_set_child(typed(widget), image)
                }
            } else if swiftString(gtk_button_get_label(typed(widget))) != text {
                gtk_button_set_label(typed(widget), text)
            }
            Button.applyStyle(widget, state.buttonStyle, role: nil)
        case .image:
            guard text != previous || Gtk.Widget(widget).firstChild == nil else { return }
            let interpretation = List.Props.DataInterpretation(rawValue: (cell.type.dataInterpretation ?? .systemName).rawValue) ?? .systemName
            setOnlyChild(widget, List.imageCell(text, interpretation))
        case .asyncImage:
            guard text != previous || Gtk.Widget(widget).firstChild == nil else { return }
            setOnlyChild(widget, asyncImage(text, cell, widget))
        case .toggle:
            let isOn = TemplateHelper.rowBool(text) ?? false
            switch cell.type.toggleStyle {
            case .checkbox: Gtk.CheckButton(widget).isActive = isOn
            case .switch: gtk_switch_set_active(opaque(widget), isOn ? 1 : 0)
            case .button: gtk_toggle_button_set_active(typed(widget), isOn ? 1 : 0)
            }
            Gtk.Widget(widget).isSensitive = !isCellDisabled(disabledColumn: cell.type.disabledColumn, row: row)
        }
    }

    private static func setOnlyChild(_ box: WidgetPointer, _ child: WidgetPointer) {
        while let old = Gtk.Widget(box).firstChild?.pointer {
            gtk_box_remove(typed(box), old)
        }
        gtk_box_append(typed(box), child)
    }

    /// An AsyncImage cell's content: the image once RemoteImages has it, scaled to fit the row;
    /// until then a spinner, which the image replaces when it arrives if the cell still shows the
    /// same text. One that cannot be loaded keeps the spinner, as SwiftUI's cell keeps its
    /// ProgressView placeholder.
    private static func asyncImage(_ text: String, _ cell: TableCell, _ box: WidgetPointer) -> WidgetPointer {
        if let texture = RemoteImages.shared.texture(text) {
            let picture = gtk_picture_new_for_paintable(texture.pointer)!
            gtk_picture_set_content_fit(opaque(picture), GTK_CONTENT_FIT_CONTAIN)
            gtk_widget_set_hexpand(picture, 1)
            return picture
        }
        let spinner = adw_spinner_new()!
        RemoteImages.shared.load(text) { [weak cell] loaded in
            guard loaded, let cell, cell.text == text else { return }
            setOnlyChild(box, asyncImage(text, cell, box))
        }
        return spinner
    }

    /// Shows the rows: the list gets one item per row, and the cells already bound show their
    /// row's new text (GTK binds the cells of new rows itself).
    private static func setRows(_ state: TableState, _ node: RenderNode, _ rows: [[String]]) {
        let old = state.rows.count
        state.rows = rows
        if rows.count != old {
            let start = min(old, rows.count)
            "".withCString { empty in
                var additions = [UnsafePointer<CChar>?](repeating: empty, count: max(0, rows.count - old))
                additions.append(nil)
                gtk_string_list_splice(state.items, guint(start), guint(max(0, old - rows.count)), &additions)
            }
        }
        for item in state.boundCells.keys {
            showRow(item, state, node)
        }
    }

    /// A Button cell's click: the entry's actionID with the column as viewPartID and the context
    /// actionContext names.
    private static func buttonClicked(_ cell: TableCell, _ node: RenderNode, _ state: TableState) {
        let position = Int(gtk_list_item_get_position(OpaquePointer(cell.item)))
        guard state.rows.indices.contains(position) else { return }
        let context: Any
        switch cell.type.actionContext {
        case .title: context = cell.text
        case .rowIndex: context = position
        case .columnIndex: context = cell.column
        case .rowColumnIndex: context = ["row": position, "column": cell.column]
        }
        node.fire(cell.type.actionID, viewPartID: cell.column, context: context)
    }

    /// A user toggle of a Toggle cell (Core writes the cell and fires); a row that is gone shows
    /// the rows' state again.
    private static func userToggled(_ cell: TableCell, _ isOn: Bool, _ node: RenderNode, _ state: TableState) {
        let position = Int(gtk_list_item_get_position(OpaquePointer(cell.item)))
        let taken = state.rows.indices.contains(position) && commitCellToggle(
            isOn, drawnRow: state.rows[position], rowIndex: position, column: cell.column,
            actionID: cell.type.actionID, windowUUID: node.windowUUID, viewID: node.element.id)
        if !taken {
            UpdateGuard.applying { showRow(cell.item, state, node) }
        }
    }

    // MARK: Selection

    /// Shows the selection at `position` (none for nil), without firing anything (the update runs
    /// inside UpdateGuard).
    private static func select(_ state: TableState, position: Int?) {
        let wanted = position.map { guint($0) } ?? guint(GTK_INVALID_LIST_POSITION)
        guard gtk_single_selection_get_selected(state.selection) != wanted else { return }
        gtk_single_selection_set_selected(state.selection, wanted)
    }

    /// The position of the selected row, or nil.
    static func selectedPosition(_ state: TableState) -> Int? {
        let selected = gtk_single_selection_get_selected(state.selection)
        return selected == guint(GTK_INVALID_LIST_POSITION) ? nil : Int(selected)
    }

    private static func userSelected(_ node: RenderNode, _ state: TableState) {
        guard state.input.isActive else {
            // A selection GTK made, not the user's: show the model's again.
            UpdateGuard.applying { select(state, position: RowSelection.selectedIndex(value: node.model.value, in: state.rows)) }
            return
        }
        guard let clicked = RowSelection.clickedRow(index: selectedPosition(state), in: state.rows) else { return }
        RowSelection.commitRowSelection(clicked, drawnRows: state.rows, model: node.model, actionID: Props(node.properties).actionID,
                                        windowUUID: node.windowUUID, viewID: node.element.id)
    }

    /// A double click or Return on a row: as SwiftUI's primaryAction, the row becomes the value and
    /// doubleClickActionID fires with its index; actionID first when that changes the selection.
    private static func userActivated(_ node: RenderNode, _ state: TableState, position: Int) {
        let props = Props(node.properties)
        guard let actionID = props.doubleClickActionID, state.rows.indices.contains(position) else { return }
        let current = node.model.states["content"] as? [[String]] ?? []
        let row = ActionUIModel.reconciledSelection(state.rows[position], from: state.rows, to: current)
        let changed = (node.model.value as? [String] ?? []) != row
        node.model.value = row
        if changed {
            node.fire(props.actionID)
        }
        node.fire(actionID, context: position)
    }
}
