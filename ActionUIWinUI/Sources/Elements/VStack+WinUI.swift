// Sources/Elements/VStack+WinUI.swift
/*
 VStack on WinUI: a StackLayout along the vertical axis, holding the element's children.
 Templates (a content row per instance) come later.
*/

extension VStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try StackViews.make(node, axis: .vertical)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let stack = StackViews.stack(of: node) else { return }
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .leading: alignment = .start
        case .center: alignment = .center
        case .trailing: alignment = .end
        }
        StackViews.configure(stack, spacing: props.spacing, alignment: alignment)
        syncStackContent(node, stack)
    }
}

/// The StackLayout a stack node keeps in its state.
@MainActor enum StackViews {
    static func make(_ node: RenderNode, axis: StackLayout.Axis) throws(WinUIError) -> WinUIObject {
        let stack = try StackLayout(axis: axis)
        node.state = stack
        return stack.panel.object
    }

    static func stack(of node: RenderNode) -> StackLayout? {
        node.state as? StackLayout
    }

    static func configure(_ stack: StackLayout, spacing: Double?, alignment: StackSolver.Alignment) {
        if stack.spacing != spacing || stack.alignment != alignment {
            stack.spacing = spacing
            stack.alignment = alignment
            stack.invalidate()
        }
    }
}
