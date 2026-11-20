// Sources/Elements/List+LazyRows.swift
/*
 List's template form on GTK, made lazily: a GtkListView in the List's GtkScrolledWindow, whose
 factory makes a row's template instance (the template with the row's data,
 RenderNode.lazyTemplateRowNode) only when GTK binds the row, as it comes in or near view, and lets
 it go when GTK unbinds it. GTK's list view virtualizes as the scrolled window's direct child: it
 estimates the rows not made, keeps the scroll position, and recycles the row widgets. It keeps
 about 200 rows bound around the view (and the cursor's row), so a List of 2000 rows opens and
 scrolls with a tenth of them made, and one of 100000 with as many, as SwiftUI's List (a table view
 that reuses its cells) makes only what it shows. GTK binds rows once the list is laid out in a
 window on screen.

 - The model is one string per content row (a GtkStringList, the strings unused) under a
   GtkSingleSelection: the selection and activation are by position, as in the eager form.
 - Rows are kept by index, as in the eager form: a row whose data changes is replaced in the model,
   which GTK binds again (its instance made again); rows are added at and removed from the end.
 - A row let go loses only transient state (keyboard focus, a text selection): its data lives in
   the content rows (a row-bound Toggle writes its row), so it shows the same when made again.
 - The grouped and insetGrouped styles keep the eager GtkListBox (List+Adwaita.swift): libadwaita
   draws its boxed-list cards for a list box only. So do the children form and the content-rows
   form.
*/

import CAdwaita

/// A List's lazy template rows: its list view, the model and the instances GTK has bound.
@MainActor
final class LazyListRows {
    let view: WidgetPointer
    let strings: OpaquePointer
    let selection: OpaquePointer
    private weak var node: RenderNode?
    private var template: (any ActionUIElementBase)?
    /// The content rows the model stands for.
    private(set) var rows: [[String]] = []
    /// The instances bound, by row index.
    private(set) var made: [Int: RenderNode] = [:]
    /// The list's environment when the rows were last updated: the rows are not child nodes.
    private var environment = Environment()

    private static let instanceKey = AttachKey<RenderNode>("actionui-list-row-instance")

    /// A list view over an empty model, with its factory; the list view holds the model and the
    /// factory, the scrolled window the list view.
    init(node: RenderNode) {
        self.node = node
        strings = gtk_string_list_new(nil)!
        // Each takes the reference of what it is given (transfer full).
        selection = gtk_single_selection_new(strings)!
        gtk_single_selection_set_autoselect(selection, 0)
        gtk_single_selection_set_can_unselect(selection, 1)
        let factory = gtk_signal_list_item_factory_new()!
        view = gtk_list_view_new(selection, factory)!
        connectObjectSignal(UnsafeMutableRawPointer(factory), "setup") { item in
            gtk_list_item_set_child(OpaquePointer(item), ListRowLayout.makeHolder())
        }
        connectObjectSignal(UnsafeMutableRawPointer(factory), "bind") { [weak self] item in
            self?.bind(item)
        }
        connectObjectSignal(UnsafeMutableRawPointer(factory), "unbind") { [weak self] item in
            self?.unbind(item)
        }
    }

    isolated deinit {
        for row in made.values {
            row.detach()
        }
    }

    // MARK: Updating

    /// Makes the model stand for `node`'s content rows: a changed row is replaced (GTK binds it
    /// again), rows are added at and removed from the end. A changed environment reaches the made
    /// rows.
    func update(_ node: RenderNode, template: any ActionUIElementBase) {
        self.node = node
        self.template = template
        if node.environment != environment {
            environment = node.environment
            for row in made.values {
                SyncScheduler.shared.markDirty(row)
            }
        }
        let newRows = node.model.states["content"] as? [[String]] ?? []
        guard newRows != rows else { return }
        let old = rows
        // The rows first: GTK may bind as soon as the model changes.
        rows = newRows
        // A run of changed rows is replaced at once: one model change, not one per row.
        let common = min(old.count, newRows.count)
        var index = 0
        while index < common {
            guard old[index] != newRows[index] else {
                index += 1
                continue
            }
            var end = index + 1
            while end < common && old[end] != newRows[end] {
                end += 1
            }
            splice(at: index, removing: end - index, adding: end - index)
            index = end
        }
        if newRows.count < old.count {
            splice(at: newRows.count, removing: old.count - newRows.count, adding: 0)
        } else if newRows.count > old.count {
            splice(at: old.count, removing: 0, adding: newRows.count - old.count)
        }
    }

    /// Replaces `removing` model items at `position` with `adding` new ones.
    private func splice(at position: Int, removing: Int, adding: Int) {
        let additions = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: adding + 1)
        defer { additions.deallocate() }
        "".withCString { empty in
            for index in 0..<adding {
                additions[index] = empty
            }
            additions[adding] = nil
            gtk_string_list_splice(strings, guint(position), guint(removing), additions)
        }
    }

    // MARK: Binding

    /// GTK shows row `item`'s position: its instance, made and synced now, in the item's holder.
    private func bind(_ item: UnsafeMutableRawPointer) {
        let listItem: OpaquePointer = OpaquePointer(item)
        let position = Int(gtk_list_item_get_position(listItem))
        guard let node, let template, rows.indices.contains(position),
              let holder = gtk_list_item_get_child(listItem) else { return }
        let instance = node.lazyTemplateRowNode(template, row: rows[position], rowIndex: position)
        gtk_widget_set_parent(instance.outerWidget, holder)
        attach(instance, to: UnsafeMutableRawPointer(holder), key: Self.instanceKey)
        if let previous = made[position], previous !== instance {
            release(previous)
        }
        made[position] = instance
        instance.sync()
    }

    /// GTK no longer shows `item`: its instance leaves the tree.
    private func unbind(_ item: UnsafeMutableRawPointer) {
        guard let holder = gtk_list_item_get_child(OpaquePointer(item)),
              let instance = attached(on: UnsafeMutableRawPointer(holder), key: Self.instanceKey) else { return }
        g_object_set_data(typed(OpaquePointer(holder)), Self.instanceKey.name, nil)
        if let index = made.first(where: { $0.value === instance })?.key {
            made[index] = nil
        }
        release(instance)
    }

    private func release(_ instance: RenderNode) {
        if gtk_widget_get_parent(instance.outerWidget) != nil {
            gtk_widget_unparent(instance.outerWidget)
        }
        instance.detach()
    }

    // MARK: Rows on screen

    /// The instance shown at `y` in the list view, for a right click on its row.
    func rowNode(atY y: Double) -> RenderNode? {
        var child = gtk_widget_get_first_child(view)
        while let row = child {
            var bounds = graphene_rect_t()
            if gtk_widget_compute_bounds(row, view, &bounds) != 0,
               Double(bounds.origin.y) <= y, y < Double(bounds.origin.y + bounds.size.height),
               let holder = gtk_widget_get_first_child(row),
               let instance = attached(on: UnsafeMutableRawPointer(holder), key: Self.instanceKey) {
                return instance
            }
            child = gtk_widget_get_next_sibling(row)
        }
        return nil
    }

    /// The selected position, nil for none.
    var selectedPosition: Int? {
        let selected = gtk_single_selection_get_selected(selection)
        return selected == GTK_INVALID_LIST_POSITION ? nil : Int(selected)
    }

    /// Shows the selection at `position` (none for nil).
    func select(_ position: Int?) {
        guard position != selectedPosition else { return }
        gtk_single_selection_set_selected(selection, position.map { guint($0) } ?? GTK_INVALID_LIST_POSITION)
    }
}
