// Sources/Elements/LazyVGrid+Adwaita.swift
/*
 LazyVGrid and LazyHGrid on GTK (LazyGridLayout): their children, or one template instance per
 content row (setElementRows; the template shown with the row's data, as on Apple), flowing into
 the declared columns (rows for LazyHGrid): a column with a numeric "minimum" is that wide, one with
 "flexible": true shares the rest. spacing is the space between rows (columns for LazyHGrid);
 alignment places the block of tracks in the grid and each child in its cell.
*/

import CAdwaita

extension LazyVGrid: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        LazyGridLayout.makeGrid(vertical: true)
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
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        LazyGridLayout.makeGrid(vertical: false)
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

    /// Applies the configuration and syncs the children or the template instances into the grid.
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
        let remove: (RenderNode) -> Void = { gtk_widget_unparent($0.outerWidget) }
        if let template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase {
            node.syncChildren([], insert: { _, _ in }, remove: remove)
            let rows = node.model.states["content"] as? [[String]] ?? []
            state.templateRows.sync(node, template: template, rows: rows, insert: { _, _ in }, remove: remove)
            state.items = state.templateRows.nodes.map(\.outerWidget)
        } else {
            state.templateRows.removeAll(remove: remove)
            var items: [WidgetPointer] = []
            node.syncChildren(node.subviews("children"), insert: { child, _ in
                items.append(child.outerWidget)
            }, remove: remove)
            state.items = items
        }
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
