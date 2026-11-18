// Sources/Elements/Spacer+WinUI.swift
/*
 Spacer on WinUI: an empty panel. Its stack gives it its length (StackLayout: it expands along
 the stack's axis, at least minLength long, 8 when not given, as SwiftUI's Spacer(minLength:)).
 Outside a stack it takes no room yet.
*/

extension Spacer: ActionUIWinUIRenderer {
    static let defaultMinLength = 8.0

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let panel = try LayoutPanel()
        node.state = panel
        return panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {}
}
