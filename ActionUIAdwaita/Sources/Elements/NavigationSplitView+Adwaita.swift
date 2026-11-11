// Sources/Elements/NavigationSplitView+Adwaita.swift
/*
 NavigationSplitView on GTK: an AdwOverlaySplitView with the sidebar beside the detail, and for three
 columns a second one inside it with the content beside the detail (libadwaita's way of nesting
 split views). Every column has its own header bar, the GNOME way, titled by its element's
 navigationTitle (the detail's, when it has none, shows the window's title); libadwaita keeps the
 window's buttons at the window's edges. A split view that is the window's whole document takes
 the window's place for a header bar, as a NavigationStack does, its sidebar's carrying the primary
 menu (the application's commands), the detail's while the sidebar is hidden. A column that is
 itself a NavigationStack brings its own header bars, so the column shows none.

 - states["columnVisibility"], as on Apple: "all" and "automatic" show every column, "doubleColumn"
   hides the sidebar (in two columns it shows both), "detail" shows the detail alone. A toggle at
   the start of the detail's header bar shows and hides the sidebar, writes the state and fires
   valueChangeActionID, as SwiftUI's sidebar button does.
 - navigationSplitViewColumnWidth on the sidebar's and the content's root: the column starts at its
   ideal (or fixed) width, without one at libadwaita's (a quarter of the split view, 180 to 280
   pixels). The user drags the column's edge to resize it, as HSplitView's dividers are dragged
   (libadwaita's split views have no handle of their own): within its min and max (without them,
   libadwaita's range, widened to take the ideal), and leaving the next column its minimum width; a
   fixed width is not dragged. A press counts within 4 pixels of the edge, where the pointer shows
   the resize cursor. The dragged width stays when the window is resized, and the document's later
   updates keep it within the column's range.
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
    /// The window's primary menu buttons at the end of the sidebar's and the detail's header bars:
    /// the sidebar's shown when the split view carries the menu (RenderNode.showsPrimaryMenu),
    /// where GNOME apps show it, the detail's instead while the sidebar is hidden, so the menu
    /// stays within reach.
    let primaryMenu: WidgetPointer
    let detailMenu: WidgetPointer
    /// The drags on the sidebar's edge, and on the content's (three columns only).
    let sidebarResizer: SidebarResizer
    let contentResizer: SidebarResizer?

    init(outer: OpaquePointer, inner: OpaquePointer?) {
        self.outer = outer
        self.inner = inner
        sidebarResizer = SidebarResizer(split: outer)
        contentResizer = inner.map { SidebarResizer(split: $0) }
        content = inner == nil ? nil : SplitViewColumn()
        // Packed before the column's toolbar items, so it stays outermost.
        primaryMenu = AppCommands.shared.makeMenuButton()
        gtk_widget_set_visible(primaryMenu, 0)
        adw_header_bar_pack_end(OpaquePointer(sidebar.header), primaryMenu)
        detailMenu = AppCommands.shared.makeMenuButton()
        gtk_widget_set_visible(detailMenu, 0)
        adw_header_bar_pack_end(OpaquePointer(detail.header), detailMenu)
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
        parts.sidebarResizer.watchDrags()
        parts.contentResizer?.watchDrags()
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
            // A column with header bars of its own carries the primary menu itself: the sidebar, or
            // the detail while the sidebar is hidden.
            let menuColumn = showsSidebar ? parts.sidebar : parts.detail
            child.showsPrimaryMenu = node.showsPrimaryMenu && column === menuColumn
                && AdwaitaWindow.headerBarTypes.contains(child.element.type)
            // The toolbars of the views in a column show in its header bar, unless the column brings
            // its own bars; the title is set below, principal items in its place.
            if child.screenBar == nil, !AdwaitaWindow.headerBarTypes.contains(child.element.type) {
                child.screenBar = ScreenBar(header: column.header, toolbarView: column.toolbar, principalChanged: { [weak node] in
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
            // The column's navigationTitle, from any of its views.
            let title = ScreenTitle.find(in: child.element, windowModel: node.windowModel)
            updateHeader(column, node: node, title: title, principal: child.screenBar?.principalWidget,
                         ownBars: AdwaitaWindow.headerBarTypes.contains(element.type), isDetail: column === parts.detail)
        }
        if let sidebar, let child = node.childNodes[sidebar.id] {
            parts.sidebarResizer.setColumnWidth(BaseModifiers(child.properties).columnWidth)
        }
        let carriesMenu = { (column: (any ActionUIElementBase)?) in
            node.showsPrimaryMenu && !(column.map { AdwaitaWindow.headerBarTypes.contains($0.type) } ?? true)
        }
        Gtk.Widget(parts.primaryMenu).isVisible = showsSidebar && carriesMenu(sidebar)
        Gtk.Widget(parts.detailMenu).isVisible = !showsSidebar && carriesMenu(detail)
        if let content, let resizer = parts.contentResizer, let child = node.childNodes[content.id] {
            resizer.setColumnWidth(BaseModifiers(child.properties).columnWidth)
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

// MARK: Dragging a column's edge

/// The user's drags on the edge of one split view's sidebar: the sidebar column in the outer split
/// view, the content column in the inner one. As SplitLayout's dividers: a drag gesture on the split
/// view, which sees a press before the columns do, takes it within SplitLayout.grabDistance of the
/// edge, and a motion controller shows the resize cursor there. The column's width is libadwaita's
/// minimum and maximum sidebar width, both set to it.
@MainActor
final class SidebarResizer {
    let split: OpaquePointer
    private var widget: WidgetPointer { UnsafeMutablePointer(split) }
    /// libadwaita's own range, for a column without navigationSplitViewColumnWidth.
    let defaultRange: ClosedRange<Double>
    /// The widths the user may drag the column to; nil: a fixed width, not dragged.
    private(set) var range: ClosedRange<Double>?
    /// The width the user dragged the column to; nil until then.
    private(set) var userWidth: Double?
    /// The column's width when the drag began; nil while there is no drag.
    private(set) var dragStart: Double?
    private var cursorShown = false

    init(split: OpaquePointer) {
        self.split = split
        let minimum = adw_overlay_split_view_get_min_sidebar_width(split)
        defaultRange = minimum...max(minimum, adw_overlay_split_view_get_max_sidebar_width(split))
        range = defaultRange
    }

    /// The column's width from its navigationSplitViewColumnWidth: the width the user dragged to,
    /// kept within the column's range, else the ideal (or fixed) width; without one, libadwaita's,
    /// a share of the split view's width within its range.
    func setColumnWidth(_ width: BaseModifiers.ColumnWidth?) {
        switch width {
        case .fixed(let fixed):
            range = nil
            userWidth = nil
            setLimits(fixed...fixed)
        case .range(let minimum, let ideal, let maximum):
            // Without a min or a max, libadwaita's, widened to take the ideal. The max wins over a
            // min above it, as the column's width did before it could be dragged.
            let high = maximum ?? max(ideal, defaultRange.upperBound)
            let columnRange = min(minimum ?? min(ideal, defaultRange.lowerBound), high)...high
            range = columnRange
            userWidth = userWidth.map { Self.clamp($0, columnRange) }
            let pinned = userWidth ?? Self.clamp(ideal, columnRange)
            setLimits(pinned...pinned)
        case nil:
            range = defaultRange
            userWidth = userWidth.map { Self.clamp($0, defaultRange) }
            setLimits(userWidth.map { $0...$0 } ?? defaultRange)
        }
    }

    /// The sidebar's edge in the split view's coordinates, its width, and whether it lies left of
    /// the edge; nil while the sidebar is hidden or laid over the content.
    func edge() -> (x: Double, width: Double, sidebarLeft: Bool)? {
        guard adw_overlay_split_view_get_show_sidebar(split) != 0, adw_overlay_split_view_get_collapsed(split) == 0,
              let sidebar = adw_overlay_split_view_get_sidebar(split) else { return nil }
        var bounds = graphene_rect_t()
        guard gtk_widget_compute_bounds(sidebar, widget, &bounds) != 0, bounds.size.width > 0 else { return nil }
        let leading = adw_overlay_split_view_get_sidebar_position(split) == GTK_PACK_START
        let sidebarLeft = leading == (gtk_widget_get_direction(widget) != GTK_TEXT_DIR_RTL)
        let width = Double(bounds.size.width)
        return (Double(bounds.origin.x) + (sidebarLeft ? width : 0), width, sidebarLeft)
    }

    /// Whether a press at `x` (in the split view) is on the edge of a column the user can resize.
    func grabs(_ x: Double) -> Bool {
        guard let range, range.upperBound > range.lowerBound, let edge = edge() else { return false }
        return abs(x - edge.x) <= SplitLayout.grabDistance
    }

    /// Starts a drag for a press at `x`, when it is on the edge.
    func beginDrag(at x: Double) -> Bool {
        guard grabs(x), let edge = edge() else { return false }
        dragStart = edge.width
        return true
    }

    /// Moves the edge `dx` from where the drag began: the column's width, within its range, leaving
    /// the column beside it its minimum width.
    func drag(by dx: Double) {
        guard let dragStart, let range, let edge = edge() else { return }
        let wanted = dragStart + (edge.sidebarLeft ? dx : -dx)
        let beside = adw_overlay_split_view_get_content(split).map { Gtk.Widget($0).measure(GTK_ORIENTATION_HORIZONTAL).minimum } ?? 0
        let room = Double(gtk_widget_get_width(widget) - Int32(clamping: beside))
        let width = max(range.lowerBound, min(wanted, range.upperBound, room)).rounded()
        userWidth = width
        setLimits(width...width)
    }

    func endDrag() {
        dragStart = nil
    }

    /// libadwaita's minimum and maximum sidebar width, changed only when they differ.
    private func setLimits(_ limits: ClosedRange<Double>) {
        guard limits.lowerBound.isFinite, limits.upperBound.isFinite, limits.lowerBound > 0 else { return }
        if adw_overlay_split_view_get_min_sidebar_width(split) != limits.lowerBound {
            adw_overlay_split_view_set_min_sidebar_width(split, limits.lowerBound)
        }
        if adw_overlay_split_view_get_max_sidebar_width(split) != limits.upperBound {
            adw_overlay_split_view_set_max_sidebar_width(split, limits.upperBound)
        }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Shows the resize cursor on the split view, or takes it away.
    private func showCursor(_ shown: Bool) {
        guard shown != cursorShown else { return }
        cursorShown = shown
        gtk_widget_set_cursor_from_name(widget, shown ? "col-resize" : nil)
    }

    /// The drag gesture (seen before the columns see the press) and the motion controller that shows
    /// the resize cursor near the edge.
    func watchDrags() {
        let drag = gtk_gesture_drag_new()!
        gtk_gesture_single_set_button(drag, 1)
        gtk_event_controller_set_propagation_phase(drag, GTK_PHASE_CAPTURE)
        connectPoint(UnsafeMutableRawPointer(drag), "drag-begin") { [weak self] x, _ in
            guard let self else { return }
            gtk_gesture_set_state(drag, beginDrag(at: x) ? GTK_EVENT_SEQUENCE_CLAIMED : GTK_EVENT_SEQUENCE_DENIED)
        }
        connectPoint(UnsafeMutableRawPointer(drag), "drag-update") { [weak self] dx, _ in
            self?.drag(by: dx)
        }
        connectPoint(UnsafeMutableRawPointer(drag), "drag-end") { [weak self] dx, _ in
            guard let self else { return }
            let dragging = dragStart != nil
            endDrag()
            // Released away from the edge (the column at its limit): no motion may follow to take
            // the cursor away.
            var x = 0.0
            var y = 0.0
            if dragging, gtk_gesture_drag_get_start_point(drag, &x, &y) != 0 {
                showCursor(grabs(x + dx))
            }
        }
        gtk_widget_add_controller(widget, drag)

        let motion = gtk_event_controller_motion_new()!
        connectPoint(UnsafeMutableRawPointer(motion), "motion") { [weak self] x, _ in
            guard let self else { return }
            showCursor(dragStart != nil || grabs(x))
        }
        connectSignal(UnsafeMutableRawPointer(motion), "leave", .instanceOnly) { [weak self] in
            guard let self, dragStart == nil else { return }
            showCursor(false)
        }
        gtk_widget_add_controller(widget, motion)
    }
}
