// Sources/Elements/LazyStacks+WinUI.swift
/*
 LazyVStack and LazyHStack on WinUI: laid out as a VStack and an HStack, but taking all the room they
 are offered across their axis (measured on macOS 27: a LazyVStack is as wide as its column, its
 children aligned in that width; a LazyHStack as tall as its row, sharing the height with a Spacer),
 where a VStack and an HStack take their widest and tallest child's. Their children are all made at
 once, not as they scroll into view. Their spacing is the element's (Core's Props: 0 when it gives
 none).

 Their template form (one instance per content row, TemplateRows) is VStack's and HStack's: every
 row's instance is made when the row arrives, as on Linux.
*/

extension LazyVStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let view = try StackViews.make(node, axis: .vertical)
        // Its children aligned in the whole width it takes, not in its widest child's.
        StackViews.stack(of: node)?.fillsAcross = true
        return view
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node).union(.horizontal) }

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

extension LazyHStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let view = try StackViews.make(node, axis: .horizontal)
        StackViews.stack(of: node)?.fillsAcross = true
        return view
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node).union(.vertical) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let stack = StackViews.stack(of: node) else { return }
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .top: alignment = .start
        case .center: alignment = .center
        case .bottom: alignment = .end
        }
        StackViews.configure(stack, spacing: props.spacing, alignment: alignment)
        syncStackContent(node, stack)
    }
}
