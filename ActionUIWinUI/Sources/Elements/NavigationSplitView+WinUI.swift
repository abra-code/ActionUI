// Sources/Elements/NavigationSplitView+WinUI.swift
/*
 NavigationSplitView on WinUI: the sidebar, the content (three columns) and the detail side by side,
 each column filling the split view's height under a header row, with a 1 point divider between each
 pair that the user drags, as an HSplitView's (SplitLayout). Following the Linux renderer
 (NavigationSplitView+Adwaita.swift) and Apple's:

 - navigationSplitViewColumnWidth on the sidebar's and the content's root: a fixed width, not dragged;
   or a range, the column starting at its ideal width, dragged within its min and max (without them,
   the default range widened to take the ideal); without one, the default: a quarter of the split view
   within 180 to 280 points, as libadwaita's sidebars (the Linux renderer's). The detail takes the
   rest. A column whose view does not expand shows it at its own size, centered in the column.
 - Dragging a column's edge resizes that column, and the detail takes the difference (in three
   columns the content keeps its width while the sidebar's edge moves), as on Linux and Apple. The
   widths dragged to stay while the detail shows another destination, and a change of the split
   view's width goes to the detail.
 - Each column has a header row, as a NavigationStack's (NavigationStackLayout), all of one height:
   the column's navigationTitle (from any of its views, ScreenTitle) in the type ramp's Subtitle, and
   the toolbar items of the views in the column at their places (NodeToolbar). A column that is
   itself a NavigationStack brings its own header, so a sidebar or content column shows none.
 - The detail's header starts with a button that shows and hides the sidebar, as NavigationView's
   pane toggle (the three lines), writing states["columnVisibility"] and firing valueChangeActionID,
   as SwiftUI's sidebar button does. persistentToolbar (and toolbar, its deprecated alias) shows in
   the detail's header, at its outer edge.
 - states["columnVisibility"], as on Apple: "all" and "automatic" show every column, "doubleColumn"
   hides the sidebar (in two columns it shows both), "detail" shows the detail alone. A hidden
   column keeps its views (their state) for when it shows again.
 - Destinations: when the sidebar is a List whose children have destinationViewId, choosing one
   stores states["selectedDestination"] (the child's destination, else the child's id, as on Apple),
   after the List's own selection and action, and the detail shows that destination; without one it
   shows "detail". Such a List can be chosen in with or without an actionID. A host's write of the
   state switches the detail.

 Not yet: persistentToolbar on the pages of a detail that is a NavigationStack (it shows, with the
 sidebar button, in a header row of the detail's own above the stack's); a sidebar or content column
 that is a NavigationStack keeps its own header's height, not the other columns'; the window's title in the detail's header; the sidebar's
 own background; style (balanced and prominentDetail look the same); collapsing into one column in a
 narrow window; the widths dragged to kept across hiding and showing a column (they start over); the
 detail's minimum (a drag can make it 0 wide); a fixed column's edge still shows the resize cursor and
 takes a press.
*/

import CWinUI
import Dispatch

/// One column: a header row (its title and toolbar items) above the column's view.
@MainActor
final class SplitViewColumn {
    let layout: NavigationStackLayout
    /// The toolbar items of the views in the column.
    let bar: NavigationScreenBar
    /// The node the column shows.
    weak var child: RenderNode?
    var shownTitle: String?

    init(split: RenderNode) throws(WinUIError) {
        // The layout's back button is never shown: a column has no screens to go back from.
        guard let back = WinUIObject(adopting: actionUIWinUIBackButtonCreate()) else {
            throw WinUIError.last("creating a column's header")
        }
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a column's title")
        }
        // The type ramp's Subtitle, as a NavigationStack's title.
        if !actionUIWinUIElementSetFont(title.pointer, nil, 20, 600) {
            ActionUIModel.shared.logger.log("NavigationSplitView: \(WinUIError.last("setting a column title's font"))", .error)
        }
        layout = try NavigationStackLayout(back: back, title: title)
        // A header too narrow for its items is cut at the column's edge, not drawn over the next one.
        layout.clipsToBounds = true
        bar = NavigationScreenBar(stack: split)
    }
}

/// A NavigationSplitView's columns, its sidebar button and its persistent toolbar.
@MainActor
final class NavigationSplitViewState {
    let split: SplitLayout
    let sidebar: SplitViewColumn
    let content: SplitViewColumn
    let detail: SplitViewColumn
    let toggle: WinUIObject
    let persistentBar: NavigationScreenBar
    var persistentToolbar: NodeToolbar?

    init(split: SplitLayout, node: RenderNode, toggle: WinUIObject) throws(WinUIError) {
        self.split = split
        self.toggle = toggle
        sidebar = try SplitViewColumn(split: node)
        content = try SplitViewColumn(split: node)
        detail = try SplitViewColumn(split: node)
        persistentBar = NavigationScreenBar(stack: node)
    }

    /// The bar of the column `screen` (the split view's child) is shown in; nil when it shows in none.
    func bar(for screen: RenderNode) -> NavigationScreenBar? {
        [sidebar, content, detail].first { $0.child === screen }?.bar
    }
}

extension NavigationSplitView: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    /// The default range of a leading column without navigationSplitViewColumnWidth, and the share
    /// of the split view it starts at (libadwaita's sidebar, as on Linux).
    static let defaultColumnRange = (minimum: 180, maximum: 280)
    static let defaultColumnShare = 0.25
    /// The columns' header rows' height: NavigationView's pane toggle (40) and the row's insets.
    static let headerHeight = 48.0

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let split = try SplitLayout(horizontal: true)
        split.dragsAgainstLast = true
        guard let toggle = WinUIObject(adopting: actionUIWinUIPaneToggleButtonCreate()) else {
            throw WinUIError.last("creating a NavigationSplitView's sidebar button")
        }
        let state = try NavigationSplitViewState(split: split, node: node, toggle: toggle)
        node.state = state
        WinUIEvents.connect(toggle, actionUIWinUIButtonOnClick, "a NavigationSplitView's sidebar button") { [weak node] in
            guard let node, node.isAttached else { return }
            userToggledSidebar(node)
        }
        return split.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? NavigationSplitViewState else { return }
        let element = node.effectiveElement
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
        // The detail: the chosen destination, else "detail".
        let selected = node.model.states["selectedDestination"] as? Int
        let detail = selected.flatMap { id in destinations.first { $0.id == id } }
            ?? element.subviews?["detail"] as? any ActionUIElementBase

        let visibility = Props.ColumnVisibility(rawValue: node.model.states["columnVisibility"] as? String ?? "all") ?? .all
        let showsSidebar = showsSidebar(visibility, hasContent: content != nil)
        let showsContent = visibility != .detail

        // The split view's persistent toolbar (and its toolbar, the deprecated alias), in the detail's
        // header.
        let persistentItems = ToolbarHelper.persistentToolbarItems(of: element)
        if state.persistentToolbar == nil, !persistentItems.isEmpty {
            state.persistentToolbar = NodeToolbar.persistent(for: node, items: persistentItems) { [weak state] _ in state?.persistentBar }
        }
        state.persistentToolbar?.update()

        // Every column's views are kept, shown or not.
        let roles: [(element: any ActionUIElementBase, column: SplitViewColumn, shown: Bool, isDetail: Bool)] =
            [sidebar.map { ($0, state.sidebar, showsSidebar, false) },
             content.map { ($0, state.content, showsContent, false) },
             detail.map { ($0, state.detail, true, true) }].compactMap { $0 }
        let children = node.syncChildren(roles.map(\.element))
        var panes: [SplitLayout.Pane] = []
        var ideals: [SplitLayout.Ideal?] = []
        for (role, child) in zip(roles, children) {
            let column = role.column
            // Set before the children sync: their toolbars find the column's bar through it.
            column.child = child
            column.layout.page.setItems(child.takesNoPlace ? [] : child.outerView.map {
                [ZStackLayout.Item(view: $0, expansion: child.expansion, cap: child.caps)]
            } ?? [])
            showHeader(column, child: child, isDetail: role.isDetail, node: node, state: state)
            guard role.shown else { continue }
            var pane = SplitLayout.Pane(view: column.layout.panel.object, expansion: .both)
            if role.isDetail {
                pane.column = (0, nil)
                ideals.append(nil)
            } else {
                let width = columnWidth(BaseModifiers(child.properties).columnWidth)
                pane.column = width.range
                ideals.append(width.ideal)
            }
            panes.append(pane)
        }
        // The widths the user dragged to stay while the detail shows another destination.
        state.split.setPanes(panes, keepsUserSizes: true)
        if ideals != state.split.ideals {
            state.split.ideals = ideals
            state.split.panel.invalidateLayout()
        }
        // The panel is the view RenderNode enables (no Control): the button is enabled here.
        if !actionUIWinUIElementSetEnabled(state.toggle.pointer, !(node.isDisabled || node.isHidden)) {
            ActionUIModel.shared.logger.log("NavigationSplitView: \(WinUIError.last("enabling the sidebar button"))", .error)
        }
        node.applyAccessibilityHidden(to: state.toggle)
    }

    /// A column's header: its title and its views' toolbar items; the detail's starts with the sidebar
    /// button and has the persistent items at its outer edge. A sidebar or content column that is a
    /// NavigationStack shows its own header instead.
    private static func showHeader(_ column: SplitViewColumn, child: RenderNode, isDetail: Bool, node: RenderNode,
                                   state: NavigationSplitViewState) {
        let layout = column.layout
        let isStack = child.element.type == "NavigationStack"
        let ownHeader = !isDetail && isStack
        var items = NavigationBarItems()
        var title: String?
        if !ownHeader {
            let bar = column.bar
            let persistent: NavigationScreenBar? = isDetail ? state.persistentBar : nil
            items.leading = (isDetail ? [state.toggle] : []) + (persistent?.views(.leading) ?? []) + bar.views(.leading)
            items.principal = bar.views(.principal)
            if items.principal.isEmpty {
                items.principal = persistent?.views(.principal) ?? []
            }
            items.trailing = bar.views(.trailing) + (persistent?.views(.trailing) ?? [])
            items.overflow = bar.views(.overflow) + (persistent?.views(.overflow) ?? [])
            items.bottom = bar.views(.bottom) + (persistent?.views(.bottom) ?? [])
            // An empty title is none. A detail that is a NavigationStack shows its title in its own
            // header (ScreenTitle gives a stack's own navigationTitle, which the stack's root shows).
            title = isStack ? nil : ScreenTitle.find(in: child.element, windowModel: node.windowModel).flatMap { $0.isEmpty ? nil : $0 }
        }
        layout.headerMinimum = ownHeader ? 0 : headerHeight
        if let title, title != column.shownTitle {
            if actionUIWinUITextBlockSetText(layout.title.pointer, title) {
                column.shownTitle = title
                layout.panel.invalidateLayout()
            } else {
                ActionUIModel.shared.logger.log("NavigationSplitView: \(WinUIError.last("showing a column's title"))", .error)
            }
        }
        do {
            try layout.setHeader(back: false, title: title != nil, items: items)
        } catch {
            ActionUIModel.shared.logger.log("NavigationSplitView: \(error)", .error)
        }
        node.applyAccessibilityHidden(to: layout.title)
        if let overflowButton = layout.overflowButton {
            if !actionUIWinUIElementSetEnabled(overflowButton.pointer, !(node.isDisabled || node.isHidden)) {
                ActionUIModel.shared.logger.log("NavigationSplitView: \(WinUIError.last("enabling a column's overflow button"))", .error)
            }
            node.applyAccessibilityHidden(to: overflowButton)
        }
    }

    /// Whether `visibility` shows the sidebar: "all" and "automatic", and "doubleColumn" in two columns.
    private static func showsSidebar(_ visibility: Props.ColumnVisibility, hasContent: Bool) -> Bool {
        visibility == .all || visibility == .automatic || (!hasContent && visibility == .doubleColumn)
    }

    /// The sidebar button: the sidebar shows or hides (in three columns, hiding it leaves the content
    /// and the detail, or the detail alone when only it was shown), and valueChangeActionID fires.
    private static func userToggledSidebar(_ node: RenderNode) {
        let hasContent = node.effectiveElement.subviews?["content"] is any ActionUIElementBase
        // From the state now, which a host may have written since the last update.
        let current = Props.ColumnVisibility(rawValue: node.model.states["columnVisibility"] as? String ?? "all") ?? .all
        let shown = showsSidebar(current, hasContent: hasContent)
        let visibility: Props.ColumnVisibility = !shown ? .all : (!hasContent ? .detail : (current == .detail ? .detail : .doubleColumn))
        guard visibility.rawValue != node.model.states["columnVisibility"] as? String else { return }
        node.model.states["columnVisibility"] = visibility.rawValue
        if let actionID = Props(node.properties).valueChangeActionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
    }

    /// A leading column's range and the width it starts at, from its navigationSplitViewColumnWidth, as
    /// the Linux renderer takes them.
    static func columnWidth(_ width: BaseModifiers.ColumnWidth?) -> (range: (minimum: Int, maximum: Int?), ideal: SplitLayout.Ideal) {
        switch width {
        case .fixed(let fixed):
            let length = StackSolver.length(max(fixed, 0))
            return ((length, length), .length(length))
        case .range(let minimum, let ideal, let maximum):
            // Without a min or a max, the default's, widened to take the ideal; the max wins over a min
            // above it.
            let high = maximum.map { StackSolver.length(max($0, 0)) } ?? max(StackSolver.length(max(ideal, 0)), defaultColumnRange.maximum)
            let low = min(minimum.map { StackSolver.length(max($0, 0)) } ?? min(StackSolver.length(max(ideal, 0)), defaultColumnRange.minimum), high)
            return ((low, high), .length(min(max(StackSolver.length(max(ideal, 0)), low), high)))
        case nil:
            return ((defaultColumnRange.minimum, defaultColumnRange.maximum), .share(defaultColumnShare))
        }
    }

    // MARK: The sidebar's destinations

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
