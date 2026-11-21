// Sources/Elements/VStack+WinUI.swift
/*
 VStack on WinUI: a StackLayout along the vertical axis, holding the element's children, or one
 template instance per content row (TemplateRows).
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
        // One that takes no place (an EmptyView, a Link with no URL) takes no place (stackItems), so its frame makes nothing expand.
        // The children, or the template instances (one or the other is empty).
        for child in node.orderedChildren + node.templateNodes where !child.takesNoPlace {
            if child.expansion.contains(.horizontal) && child.caps.horizontal == nil { expansion.insert(.horizontal) }
            if child.expansion.contains(.vertical) && child.caps.vertical == nil { expansion.insert(.vertical) }
        }
        return expansion
    }

    /// The axes along which a container can be made smaller: those along which any child can.
    static func childrenCompression(_ node: RenderNode) -> Expansion {
        (node.orderedChildren + node.templateNodes).reduce(into: Expansion()) { $0.formUnion($1.compression) }
    }

    /// The axis of the stack `node` is in: vertical in a VStack, a GroupBox, a Form or a Section (their
    /// content is a column), horizontal in an HStack or a LabeledContent (its content is a row); in a
    /// Group, the Group's own (that of the stack it is in, else a column); nil in anything else.
    static func parentAxis(_ node: RenderNode) -> StackLayout.Axis? {
        // A background or overlay view is in no stack.
        guard !node.isDecoration else { return nil }
        switch node.parent?.element.type {
        case "VStack", "LazyVStack", "GroupBox", "Form", "Section": return .vertical
        case "HStack", "LazyHStack", "LabeledContent": return .horizontal
        case "Group": return node.parent.flatMap { parentAxis($0) } ?? .vertical
        default: return nil
        }
    }

    /// The spacing and alignment of the stack `node` is in, for content laid out as that stack's own
    /// children (a Group's): a VStack's or an HStack's own, a Form's rows (8, leading), a GroupBox's
    /// column or a LabeledContent's row (the default spacing, centered), an enclosing Section's or
    /// Group's; elsewhere no spacing, centered.
    static func parentArrangement(_ node: RenderNode) -> (spacing: Double?, alignment: StackSolver.Alignment) {
        guard let parent = node.parent, !node.isDecoration else { return (0, .center) }
        switch parent.element.type {
        case "VStack", "LazyVStack":
            let props = VStack.Props(parent.properties)
            switch props.alignment {
            case .leading: return (props.spacing, .start)
            case .center: return (props.spacing, .center)
            case .trailing: return (props.spacing, .end)
            }
        case "HStack", "LazyHStack":
            let props = HStack.Props(parent.properties)
            switch props.alignment {
            case .top: return (props.spacing, .start)
            case .center, .firstTextBaseline, .lastTextBaseline: return (props.spacing, .center)
            case .bottom: return (props.spacing, .end)
            }
        case "Form": return (Form.rowSpacing, .start)
        case "GroupBox", "LabeledContent": return (nil, .center)
        case "Section":
            let outer = (parent.state as? SectionState)?.stack
            return (outer?.spacing ?? 0, outer?.alignment ?? .center)
        case "Group":
            // The enclosing Group's, worked out again rather than read from its column, so this read
            // is tracked: a change to the stack around both re-syncs this node too.
            return parentArrangement(parent)
        default: return (0, .center)
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
