// Sources/Elements/VStack+WinUI.swift
/*
 VStack on WinUI: a StackLayout along the vertical axis, holding the element's children.
 Templates (a content row per instance) come later.
*/

extension VStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try StackViews.make(node, axis: .vertical)
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

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

    /// A container's expansion, as SwiftUI's stacks take it from their children: it expands in an
    /// axis when a child expands there without a frame's finite maximum (a Color, a TextField, a
    /// Spacer along its stack). A child with such a maximum does not make it expand: measured for
    /// the room it is offered, the container already asks for what that child takes. The children's
    /// nodes mark this one dirty when their expansion changes, and it is read after its update.
    static func childrenExpansion(_ node: RenderNode) -> Expansion {
        var expansion: Expansion = []
        for child in node.orderedChildren {
            if child.expansion.contains(.horizontal) && child.caps.horizontal == nil { expansion.insert(.horizontal) }
            if child.expansion.contains(.vertical) && child.caps.vertical == nil { expansion.insert(.vertical) }
        }
        return expansion
    }

    /// The axes along which a container can be made smaller: those along which any child can.
    static func childrenCompression(_ node: RenderNode) -> Expansion {
        node.orderedChildren.reduce(into: Expansion()) { $0.formUnion($1.compression) }
    }

    /// The axis of the stack `node` is in: vertical in a VStack, horizontal in an HStack; nil in
    /// anything else.
    static func parentAxis(_ node: RenderNode) -> StackLayout.Axis? {
        switch node.parent?.element.type {
        case "VStack", "LazyVStack": return .vertical
        case "HStack", "LazyHStack": return .horizontal
        default: return nil
        }
    }

    static func configure(_ stack: StackLayout, spacing: Double?, alignment: StackSolver.Alignment) {
        if stack.spacing != spacing || stack.alignment != alignment {
            stack.spacing = spacing
            stack.alignment = alignment
            stack.invalidate()
        }
    }
}
