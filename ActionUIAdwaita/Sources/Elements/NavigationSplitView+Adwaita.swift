// Sources/Elements/NavigationSplitView+Adwaita.swift
/*
 NavigationSplitView on GTK: an AdwOverlaySplitView with the sidebar beside the detail, and for three
 columns a second one inside it with the content beside the detail (libadwaita's way of nesting
 split views). Every column has its own header bar, the GNOME way, titled by its element's
 navigationTitle (the detail's, when it has none, shows the window's title); libadwaita keeps the
 window's buttons at the window's edges. A split view that is the window's whole document takes
 the window's place for a header bar, as a NavigationStack does. A column that is itself a
 NavigationStack brings its own header bars, so the column shows none.

 - states["columnVisibility"], as on Apple: "all" and "automatic" show every column, "doubleColumn"
   hides the sidebar (in two columns it shows both), "detail" shows the detail alone. A toggle at
   the start of the detail's header bar shows and hides the sidebar, writes the state and fires
   valueChangeActionID, as SwiftUI's sidebar button does.
 - navigationSplitViewColumnWidth on the sidebar's and the content's root: the column is its ideal
   (or fixed) width; libadwaita's columns are not resized by dragging.
 - Destinations: when the sidebar is a List whose children have destinationViewId, choosing one
   stores states["selectedDestination"] (the child's destination, else the child's id, as on
   Apple), after the List's own selection and action, and the detail shows that destination;
   without one it shows "detail". A host's write of the state switches the detail.

 - The toolbars of the views in a column show in its header bar (ScreenBar, NodeToolbar); principal
   items take the place of the column's title. persistentToolbar (and toolbar, its deprecated alias)
   shows on the detail column, at the outer edge of its bar; a detail that is a NavigationStack
   shows it on each of its pages (detailPersistentItems).

 Not here yet: style (balanced and prominentDetail look the same), collapsing into one column in a
 narrow window (where the persistent items would show on the leading columns too).
*/

import CAdwaita
import Dispatch

/// One column: a toolbar view with a header bar above the column's element.
@MainActor
final class SplitViewColumn {
    let toolbar: WidgetPointer
    let header: WidgetPointer
    /// The title widget, owned here: the header bar lets it go when the column has no title.
    private let ownedTitle: OwnedObject
    var title: WidgetPointer { ownedTitle.widget }

    init() {
        toolbar = adw_toolbar_view_new()!
        header = adw_header_bar_new()!
        ownedTitle = OwnedObject(retaining: adw_window_title_new("", nil)!)
        adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
    }
}

/// The widgets of a NavigationSplitView, kept on its outer split view.
@MainActor
final class SplitViewParts {
    let outer: OpaquePointer
    /// The split view holding the content and the detail (three columns only).
    let inner: OpaquePointer?
    let sidebar = SplitViewColumn()
    let content: SplitViewColumn?
    let detail = SplitViewColumn()
    let sidebarToggle: WidgetPointer

    init(outer: OpaquePointer, inner: OpaquePointer?) {
        self.outer = outer
        self.inner = inner
        content = inner == nil ? nil : SplitViewColumn()
        sidebarToggle = gtk_toggle_button_new()!
        gtk_button_set_icon_name(typed(sidebarToggle), "sidebar-show-symbolic")
        setAccessibleLabel(sidebarToggle, "Sidebar")
    }
}

let splitViewPartsKey = AttachKey<SplitViewParts>("actionui-navigation-split-view")

extension NavigationSplitView: ActionUIAdwaitaRenderer {
    static var defaultExpansion: Expansion { .both }

    /// 1 for three columns (a "content" column), else 0.
    static func widgetKind(_ node: RenderNode) -> Int {
        node.effectiveElement.subviews?["content"] is any ActionUIElementBase ? 1 : 0
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let outer = adw_overlay_split_view_new()!
        // Fills what it is offered, as SwiftUI's does (a renderer sets its widget's expansion; defaultExpansion only names it). It
        // also keeps libadwaita from giving a hidden sidebar no width at all: at its natural
        // width the split view is only as wide as the detail, and the sidebar is laid out in the
        // difference, which GTK warns about when it is 0.
        gtk_widget_set_hexpand(outer, 1)
        gtk_widget_set_vexpand(outer, 1)
        let inner = node.widgetKind == 1 ? adw_overlay_split_view_new() : nil
        let parts = SplitViewParts(outer: OpaquePointer(outer), inner: inner.map { OpaquePointer($0) })
        for split in [parts.outer] + (parts.inner.map { [$0] } ?? []) {
            adw_overlay_split_view_set_sidebar_width_unit(split, ADW_LENGTH_UNIT_PX)
        }
        adw_overlay_split_view_set_sidebar(parts.outer, parts.sidebar.toolbar)
        if let inner = parts.inner, let content = parts.content {
            adw_overlay_split_view_set_sidebar(inner, content.toolbar)
            adw_overlay_split_view_set_content(inner, parts.detail.toolbar)
            adw_overlay_split_view_set_content(parts.outer, UnsafeMutablePointer(inner))
        } else {
            adw_overlay_split_view_set_content(parts.outer, parts.detail.toolbar)
        }
        adw_header_bar_pack_start(OpaquePointer(parts.detail.header), parts.sidebarToggle)
        connectUserSignal(parts.sidebarToggle, "toggled", .instanceOnly) { [weak node] in
            guard let node else { return }
            userToggledSidebar(node)
        }
        attach(parts, to: outer, key: splitViewPartsKey)
        return outer
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let parts = attached(on: widget, key: splitViewPartsKey) else { return }
        let element = node.effectiveElement
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
        // The detail: the chosen destination, else "detail".
        let selected = node.model.states["selectedDestination"] as? Int
        let detail = selected.flatMap { id in destinations.first { $0.id == id } }
            ?? element.subviews?["detail"] as? any ActionUIElementBase

        // Which columns show.
        let visibility = Props.ColumnVisibility(rawValue: node.model.states["columnVisibility"] as? String ?? "all") ?? .all
        let showsSidebar = visibility == .all || visibility == .automatic || (parts.inner == nil && visibility == .doubleColumn)
        setShowsSidebar(parts.outer, showsSidebar)
        if let inner = parts.inner {
            setShowsSidebar(inner, visibility != .detail)
        }
        if (gtk_toggle_button_get_active(typed(parts.sidebarToggle)) != 0) != showsSidebar {
            gtk_toggle_button_set_active(typed(parts.sidebarToggle), showsSidebar ? 1 : 0)
        }

        var columns: [(element: any ActionUIElementBase, column: SplitViewColumn)] = []
        if let sidebar { columns.append((sidebar, parts.sidebar)) }
        if let content, let column = parts.content { columns.append((content, column)) }
        if let detail { columns.append((detail, parts.detail)) }
        node.syncChildren(columns.map(\.element), insert: { child, index in
            let column = columns[index].column
            // A column that is a NavigationStack brings its own header bars, as the window's would.
            child.isWindowRoot = node.isWindowRoot && AdwaitaWindow.headerBarTypes.contains(child.element.type)
            // The toolbars of the views in a column show in its header bar, unless the column brings
            // its own bars; the title is set below, principal items in its place.
            if child.screenBar == nil, !AdwaitaWindow.headerBarTypes.contains(child.element.type) {
                child.screenBar = ScreenBar(header: column.header, principalChanged: { [weak node] in
                    if let node { SyncScheduler.shared.markDirty(node) }
                })
                // The persistent items show on the detail column (a detail NavigationStack shows them
                // on its pages itself), as on platforms whose columns each own a bar.
                if column === parts.detail, child.persistentToolbar == nil {
                    child.persistentToolbar = NodeToolbar.persistent(on: child, items: ToolbarHelper.persistentToolbarItems(of: element))
                }
            }
            if adw_toolbar_view_get_content(OpaquePointer(column.toolbar)) != child.outerWidget {
                adw_toolbar_view_set_content(OpaquePointer(column.toolbar), child.outerWidget)
            }
        }, remove: { child in
            for column in [parts.sidebar, parts.detail] + (parts.content.map { [$0] } ?? [])
            where adw_toolbar_view_get_content(OpaquePointer(column.toolbar)) == child.outerWidget {
                adw_toolbar_view_set_content(OpaquePointer(column.toolbar), nil)
            }
        })

        for (element, column) in columns {
            guard let child = node.childNodes[element.id] else { continue }
            let modifiers = BaseModifiers(child.properties)
            updateHeader(column, node: node, title: modifiers.navigationTitle, principal: child.screenBar?.principalWidget,
                         ownBars: AdwaitaWindow.headerBarTypes.contains(element.type), isDetail: column === parts.detail)
        }
        if let sidebar, let child = node.childNodes[sidebar.id] {
            setWidth(parts.outer, BaseModifiers(child.properties).columnWidth)
        }
        if let content, let inner = parts.inner, let child = node.childNodes[content.id] {
            setWidth(inner, BaseModifiers(child.properties).columnWidth)
        }
    }

    private static func setShowsSidebar(_ split: OpaquePointer, _ shows: Bool) {
        if (adw_overlay_split_view_get_show_sidebar(split) != 0) != shows {
            adw_overlay_split_view_set_show_sidebar(split, shows ? 1 : 0)
        }
    }

    /// The column's header bar: hidden for a column with bars of its own; its title is the column's
    /// navigationTitle (none in a leading column without one, the window's in the detail); the
    /// window's buttons only on the window's own split view. Principal toolbar items take the title's
    /// place.
    private static func updateHeader(_ column: SplitViewColumn, node: RenderNode, title: String?, principal: WidgetPointer?,
                                     ownBars: Bool, isDetail: Bool) {
        let header = OpaquePointer(column.header)
        Gtk.Widget(column.header).isVisible = !ownBars
        let windowButtons: gboolean = node.isWindowRoot ? 1 : 0
        if adw_header_bar_get_show_end_title_buttons(header) != windowButtons {
            adw_header_bar_set_show_end_title_buttons(header, windowButtons)
            adw_header_bar_set_show_start_title_buttons(header, windowButtons)
        }
        if let principal {
            if adw_header_bar_get_title_widget(header) != principal {
                adw_header_bar_set_title_widget(header, principal)
            }
            adw_header_bar_set_show_title(header, 1)
        } else if let title, !title.isEmpty {
            if swiftString(adw_window_title_get_title(OpaquePointer(column.title))) != title {
                adw_window_title_set_title(OpaquePointer(column.title), title)
            }
            if adw_header_bar_get_title_widget(header) != column.title {
                adw_header_bar_set_title_widget(header, column.title)
            }
            adw_header_bar_set_show_title(header, 1)
        } else {
            if adw_header_bar_get_title_widget(header) != nil {
                adw_header_bar_set_title_widget(header, nil)
            }
            // The detail shows the window's title (the header bar's own); a leading column none.
            let shows: gboolean = isDetail ? 1 : 0
            if adw_header_bar_get_show_title(header) != shows {
                adw_header_bar_set_show_title(header, shows)
            }
        }
    }

    /// The column at its ideal or fixed width (libadwaita's columns are not dragged).
    private static func setWidth(_ split: OpaquePointer, _ width: BaseModifiers.ColumnWidth?) {
        let pixels: Double
        switch width {
        case .fixed(let fixed): pixels = fixed
        case .range(let minimum, let ideal, let maximum): pixels = min(max(ideal, minimum ?? ideal), maximum ?? ideal)
        case nil: return
        }
        guard pixels.isFinite, pixels > 0 else { return }
        if adw_overlay_split_view_get_min_sidebar_width(split) != pixels {
            adw_overlay_split_view_set_min_sidebar_width(split, pixels)
        }
        if adw_overlay_split_view_get_max_sidebar_width(split) != pixels {
            adw_overlay_split_view_set_max_sidebar_width(split, pixels)
        }
    }

    // MARK: The user's choices

    /// The sidebar toggle: the visibility follows, and valueChangeActionID fires.
    private static func userToggledSidebar(_ node: RenderNode) {
        guard let parts = attached(on: node.widget, key: splitViewPartsKey) else { return }
        let shows = gtk_toggle_button_get_active(typed(parts.sidebarToggle)) != 0
        let current = Props.ColumnVisibility(rawValue: node.model.states["columnVisibility"] as? String ?? "all") ?? .all
        let visibility: Props.ColumnVisibility = shows ? .all : (parts.inner == nil ? .detail : (current == .detail ? .detail : .doubleColumn))
        guard visibility.rawValue != node.model.states["columnVisibility"] as? String else { return }
        node.model.states["columnVisibility"] = visibility.rawValue
        if let actionID = Props(node.properties).valueChangeActionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
    }

    /// The persistent toolbar items of the split view whose detail column `stack` (a NavigationStack)
    /// is, which the stack shows on its pages; none when it is not a split view's detail.
    static func detailPersistentItems(_ stack: RenderNode) -> [any ActionUIElementBase] {
        guard let split = stack.parent, split.element.type == "NavigationSplitView",
              let parts = attached(on: split.widget, key: splitViewPartsKey),
              adw_toolbar_view_get_content(OpaquePointer(parts.detail.toolbar)) == stack.outerWidget else { return [] }
        return ToolbarHelper.persistentToolbarItems(of: split.element)
    }

    /// Whether `list` is the sidebar of a split view with destinations: its children can be chosen
    /// with or without an actionID, as on Apple.
    static func isDestinationSidebar(_ list: RenderNode) -> Bool {
        guard let split = list.parent, split.element.type == "NavigationSplitView" else { return false }
        let element = split.effectiveElement
        return (element.subviews?["sidebar"] as? any ActionUIElementBase)?.id == list.element.id
            && !(element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []).isEmpty
    }

    /// The user chose `childID` in `list` (nil: deselected); when the list is the sidebar of a split
    /// view with destinations, the detail shows the child's destination (else the child's id, as on
    /// Apple; nil: the default detail), after the List's own selection and action (which wait one
    /// main-queue turn).
    static func sidebarListChose(_ list: RenderNode, childID: Int?) {
        guard let split = list.parent, isDestinationSidebar(list) else { return }
        let destination = childID.map { id in list.windowModel.viewModels[id].flatMap { BaseModifiers($0.properties).destinationViewId } ?? id }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard split.isAttached, split.model.states["selectedDestination"] as? Int != destination else { return }
                split.model.states["selectedDestination"] = destination
            }
        }
    }
}
