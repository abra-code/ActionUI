// Sources/Elements/LazyStacks+WinUI.swift
/*
 LazyVStack and LazyHStack on WinUI: laid out as a VStack and an HStack, but taking all the room they
 are offered across their axis (measured on macOS 27: a LazyVStack is as wide as its column, its
 children aligned in that width; a LazyHStack as tall as its row, sharing the height with a Spacer),
 where a VStack and an HStack take their widest and tallest child's. Their children are all made at
 once, not as they scroll into view. Their spacing is the element's (Core's Props: 0 when it gives
 none).

 Their template form (one instance per content row) is lazy (LazyRows): an ItemsRepeater makes a row
 only when it comes in or near the part its ScrollView shows, and lets it go when it is far out of
 view, as SwiftUI's lazy stacks do. The form is chosen when the stack is made (a template in the
 document); the children form is laid out by StackLayout, every child made at once, as on Linux.
*/

extension LazyVStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        if let rows = try LazyStacks.makeRows(node, axis: .vertical) {
            return rows
        }
        let view = try StackViews.make(node, axis: .vertical)
        // Its children aligned in the whole width it takes, not in its widest child's.
        StackViews.stack(of: node)?.fillsAcross = true
        return view
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        LazyStacks.isLazy(node) ? .horizontal : StackViews.childrenExpansion(node).union(.horizontal)
    }

    static func compression(_ node: RenderNode) -> Expansion {
        LazyStacks.isLazy(node) ? [] : StackViews.childrenCompression(node)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .leading: alignment = .start
        case .center: alignment = .center
        case .trailing: alignment = .end
        }
        if LazyStacks.updateRows(node, spacing: props.spacing, alignment: alignment) { return }
        guard let stack = StackViews.stack(of: node) else { return }
        StackViews.configure(stack, spacing: props.spacing, alignment: alignment)
        syncStackContent(node, stack)
    }
}

extension LazyHStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        if let rows = try LazyStacks.makeRows(node, axis: .horizontal) {
            return rows
        }
        let view = try StackViews.make(node, axis: .horizontal)
        StackViews.stack(of: node)?.fillsAcross = true
        return view
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        LazyStacks.isLazy(node) ? .vertical : StackViews.childrenExpansion(node).union(.vertical)
    }

    static func compression(_ node: RenderNode) -> Expansion {
        LazyStacks.isLazy(node) ? [] : StackViews.childrenCompression(node)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .top: alignment = .start
        case .center: alignment = .center
        case .bottom: alignment = .end
        }
        if LazyStacks.updateRows(node, spacing: props.spacing, alignment: alignment) { return }
        guard let stack = StackViews.stack(of: node) else { return }
        StackViews.configure(stack, spacing: props.spacing, alignment: alignment)
        syncStackContent(node, stack)
    }
}

/// The template form both lazy stacks share.
@MainActor enum LazyStacks {
    /// Whether the stack shows its rows lazily (LazyRows). Its expansion is then only across its
    /// axis, and it cannot be made smaller: the rows made at a moment (those in view) do not decide
    /// how it is laid out.
    static func isLazy(_ node: RenderNode) -> Bool {
        node.state is LazyRows
    }

    /// The repeater of a lazy stack whose document gives it a template (its node's state is then a
    /// LazyRows); nil for one with children.
    static func makeRows(_ node: RenderNode, axis: StackLayout.Axis) throws(WinUIError) -> WinUIObject? {
        guard node.element.subviews?["template"] is any ActionUIElementBase else { return nil }
        let rows = try LazyRows(node: node, axis: axis)
        node.state = rows
        return rows.repeater
    }

    /// Shows the content rows of a lazy stack in its template form; false for one in its children
    /// form (StackLayout).
    static func updateRows(_ node: RenderNode, spacing: Double, alignment: StackSolver.Alignment) -> Bool {
        guard let rows = node.state as? LazyRows else { return false }
        guard let template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase else {
            // The template taken away at run time: no rows (the form was chosen when the stack was made).
            rows.update(template: nil, rows: [], spacing: spacing, alignment: alignment)
            return true
        }
        rows.update(template: template, rows: node.model.states["content"] as? [[String]] ?? [], spacing: spacing,
                    alignment: alignment)
        return true
    }
}
