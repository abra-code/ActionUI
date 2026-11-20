// Sources/Elements/Spacer+WinUI.swift
/*
 Spacer on WinUI: an empty panel. Its stack gives it its length (StackLayout: it expands along
 the stack's axis, at least minLength long, 8 when not given, as SwiftUI's Spacer(minLength:)), and
 the stack expands along its axis for it (a row with a Spacer takes the width it is offered).
 In a Grid it expands in both axes, as on Linux (GridLayout gives its column and row the room).
 Outside a stack or a Grid it takes no room yet.
*/

extension Spacer: ActionUIWinUIRenderer {
    static let defaultMinLength = 8.0

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let panel = try LayoutPanel()
        node.state = panel
        return panel.object
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        switch StackViews.parentAxis(node) {
        case .vertical?: return .vertical
        case .horizontal?: return .horizontal
        case nil: return node.parent?.element.type == "Grid" ? [.horizontal, .vertical] : []
        }
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {}
}
