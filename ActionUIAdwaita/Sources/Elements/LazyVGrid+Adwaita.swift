// Sources/Elements/LazyVGrid+Adwaita.swift
/*
 LazyVGrid and LazyHGrid on GTK (LazyGridLayout): their children, or one template instance per
 content row (setElementRows; the template shown with the row's data, as on Apple), flowing into
 the declared columns (rows for LazyHGrid): a column with a numeric "minimum" is that wide, one with
 "flexible": true shares the rest. spacing is the space between rows (columns for LazyHGrid);
 alignment places the block of tracks in the grid and each child in its cell. The template form is
 made lazily, a line of cells at a time, as lines come near the part its ScrollView shows (LazyRows);
 the children form lays every child out.
*/

import CAdwaita

extension LazyVGrid: ActionUIAdwaitaRenderer {
    /// 1 for the template form (LazyRows), 0 for the children form.
    static func widgetKind(_ node: RenderNode) -> Int {
        LazyRows.showsTemplate(node) ? 1 : 0
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        if node.widgetKind == 1 {
            return LazyRows.makeWidget(node, axis: .vertical, grid: LazyGridState(vertical: true))
        }
        return LazyGridLayout.makeGrid(vertical: true)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .leading: alignment = .start
        case .center: alignment = .center
        case .trailing: alignment = .end
        }
        LazyGridItems.update(widget, node, tracks: props.columns.map(LazyGridItems.track), alignment: alignment,
                             spacing: props.spacing)
    }
}

extension LazyHGrid: ActionUIAdwaitaRenderer {
    /// 1 for the template form (LazyRows), 0 for the children form.
    static func widgetKind(_ node: RenderNode) -> Int {
        LazyRows.showsTemplate(node) ? 1 : 0
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        if node.widgetKind == 1 {
            return LazyRows.makeWidget(node, axis: .horizontal, grid: LazyGridState(vertical: false))
        }
        return LazyGridLayout.makeGrid(vertical: false)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .top: alignment = .start
        case .center: alignment = .center
        case .bottom: alignment = .end
        }
        let tracks = props.rows.map { row -> LazyGridTrack in
            switch row {
            case .fixed(let size): return .fixed(StackSolver.length(size))
            case .flexible: return .flexible
            }
        }
        LazyGridItems.update(widget, node, tracks: tracks, alignment: alignment, spacing: props.spacing)
    }
}

@MainActor
enum LazyGridItems {
    static func track(_ column: LazyVGrid.Props.Track) -> LazyGridTrack {
        switch column {
        case .fixed(let size): return .fixed(StackSolver.length(size))
        case .flexible: return .flexible
        }
    }

    /// Applies the configuration and syncs the children into the grid, or hands the template form to
    /// its LazyRows.
    static func update(_ widget: WidgetPointer, _ node: RenderNode, tracks: [LazyGridTrack],
                       alignment: StackSolver.Alignment, spacing: Double) {
        guard let state = attached(on: widget, key: lazyGridStateKey) else { return }
        let lineSpacing = StackSolver.length(spacing)
        if tracks != state.tracks || alignment != state.alignment || lineSpacing != state.lineSpacing {
            state.tracks = tracks
            state.alignment = alignment
            state.lineSpacing = lineSpacing
            gtk_widget_queue_resize(widget)
        }
        // The template form: its rows are made lazily, a line of cells at a time.
        if let rows = attached(on: widget, key: lazyRowsKey) {
            rows.update(node, spacing: spacing, alignment: alignment)
            return
        }
        // The children form (a template makes the other widget kind).
        let remove: (RenderNode) -> Void = { gtk_widget_unparent($0.outerWidget) }
        var items: [WidgetPointer] = []
        node.syncChildren(node.subviews("children"), insert: { child, _ in
            items.append(child.outerWidget)
        }, remove: remove)
        state.items = items
        // In order, so focus moves through the cells as they are read.
        var previous: WidgetPointer?
        for item in state.items {
            if gtk_widget_get_parent(item) != widget || gtk_widget_get_prev_sibling(item) != previous {
                if gtk_widget_get_parent(item) != nil && gtk_widget_get_parent(item) != widget {
                    gtk_widget_unparent(item)
                }
                gtk_widget_insert_after(item, widget, previous)
            }
            previous = item
        }
    }
}
