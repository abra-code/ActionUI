// Sources/Elements/HSplitView+Adwaita.swift
/*
 HSplitView on GTK: its children side by side with a divider the user drags between each pair
 (SplitLayout), the first child's frame idealWidth setting the first divider, as on macOS; a
 Group's children are panes of their own, as on macOS.
 VSplitView is the same stacked, with idealHeight.
*/

import CAdwaita

extension HSplitView: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        SplitLayout.makeSplit(GTK_ORIENTATION_HORIZONTAL)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        SplitPanes.update(widget, node) { $0?.idealWidth }
    }
}

extension VSplitView: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        SplitLayout.makeSplit(GTK_ORIENTATION_VERTICAL)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        SplitPanes.update(widget, node) { $0?.idealHeight }
    }
}

@MainActor
enum SplitPanes {
    /// Syncs a split view's children into its panes; `ideal` reads the size the first child's frame
    /// asks for in the split view's axis.
    static func update(_ widget: WidgetPointer, _ node: RenderNode, ideal: (BaseModifiers.Frame?) -> Double?) {
        guard let state = attached(on: widget, key: splitStateKey) else { return }
        let children = node.subviews("children")
        var panes: [WidgetPointer] = []
        node.syncChildren(children, insert: { child, _ in
            panes.append(child.outerWidget)
        }, remove: { child in
            gtk_widget_unparent(child.outerWidget)
        })
        // A Group's children are panes of their own (SplitLayout.shownPanes).
        let paneCount = children.reduce(0) { count, child in
            count + (child.type == "Group" ? (child.subviews?["children"] as? [any ActionUIElementBase])?.count ?? 0 : 1)
        }
        state.setPanes(panes, dividerCount: paneCount - 1, in: widget)
        let first = children.first.flatMap { node.childNodes[$0.id] }
        state.firstIdeal = first.flatMap { ideal(BaseModifiers($0.properties).frame) }.map { StackSolver.length($0) }
    }
}
