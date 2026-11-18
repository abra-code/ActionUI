// Sources/Elements/HStack+WinUI.swift
/*
 HStack on WinUI: a StackLayout along the horizontal axis, holding the element's children.
 Without a spacing it uses the default (8, 0 next to a Spacer), as on Apple and Linux. The
 baseline alignments are placed as center until baselines come.
*/

extension HStack: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try StackViews.make(node, axis: .horizontal)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let stack = StackViews.stack(of: node) else { return }
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .top: alignment = .start
        case .center, .firstTextBaseline, .lastTextBaseline: alignment = .center
        case .bottom: alignment = .end
        }
        StackViews.configure(stack, spacing: props.spacing, alignment: alignment)
        syncStackContent(node, stack)
    }
}
