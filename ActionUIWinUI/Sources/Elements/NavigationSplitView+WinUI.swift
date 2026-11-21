// Sources/Elements/NavigationSplitView+WinUI.swift
/*
 NavigationSplitView on WinUI, first slice: the sidebar, the content (three columns) and the detail
 side by side, each column filling the split view's height, with a 1 point divider between each pair
 that the user drags, as an HSplitView's (SplitLayout). Following the Linux renderer
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
 - states["columnVisibility"], as on Apple: "all" and "automatic" show every column, "doubleColumn"
   hides the sidebar (in two columns it shows both), "detail" shows the detail alone. A hidden
   column keeps its views (their state) for when it shows again.
 - Destinations: when the sidebar is a List whose children have destinationViewId, choosing one
   stores states["selectedDestination"] (the child's destination, else the child's id, as on Apple),
   after the List's own selection and action, and the detail shows that destination; without one it
   shows "detail". Such a List can be chosen in with or without an actionID. A host's write of the
   state switches the detail.

 Not yet: the columns' title rows (navigationTitle) and their toolbar items, the button that shows and
 hides the sidebar (valueChangeActionID), persistentToolbar; the sidebar's own background; style
 (balanced and prominentDetail look the same); collapsing into one column in a narrow window; the
 widths dragged to kept across hiding and showing a column (they start over); the detail's minimum (a
 drag can make it 0 wide); a fixed column's edge still shows the resize cursor and takes a press.
*/

import Dispatch

extension NavigationSplitView: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    /// The default range of a leading column without navigationSplitViewColumnWidth, and the share
    /// of the split view it starts at (libadwaita's sidebar, as on Linux).
    static let defaultColumnRange = (minimum: 180, maximum: 280)
    static let defaultColumnShare = 0.25

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try SplitLayout(horizontal: true)
        layout.dragsAgainstLast = true
        node.state = layout
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? SplitLayout else { return }
        let element = node.effectiveElement
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []
        // The detail: the chosen destination, else "detail".
        let selected = node.model.states["selectedDestination"] as? Int
        let detail = selected.flatMap { id in destinations.first { $0.id == id } }
            ?? element.subviews?["detail"] as? any ActionUIElementBase

        let visibility = Props.ColumnVisibility(rawValue: node.model.states["columnVisibility"] as? String ?? "all") ?? .all
        let showsSidebar = visibility == .all || visibility == .automatic || (content == nil && visibility == .doubleColumn)
        let showsContent = visibility != .detail

        // Every column's views are kept, shown or not.
        let columns = [sidebar, content, detail].compactMap { $0 }
        let children = node.syncChildren(columns)
        var panes: [SplitLayout.Pane] = []
        var ideals: [SplitLayout.Ideal?] = []
        for child in children where !child.takesNoPlace {
            guard let outer = child.outerView else { continue }
            let id = child.element.id
            let isDetail = id == detail?.id
            if id == sidebar?.id, !isDetail, !showsSidebar { continue }
            if id == content?.id, !isDetail, !showsContent { continue }
            var pane = SplitLayout.Pane(view: outer, expansion: child.expansion, cap: child.caps)
            if isDetail {
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
        layout.setPanes(panes, keepsUserSizes: true)
        if ideals != layout.ideals {
            layout.ideals = ideals
            layout.panel.invalidateLayout()
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
