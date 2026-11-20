// Sources/Elements/EmptyView+WinUI.swift
/*
 EmptyView on WinUI: nothing. An empty panel that asks for no room; a stack (and a Form, a Section,
 a GroupBox), a Grid, a ZStack and a List leave it out (stackItems, Grid's cells, ZStack's layers,
 List's rows), so it gets no place, no spacing, no cell, no layer and no row, and its frame makes no
 stack expand: measured on macOS 27 (two views with an EmptyView between them are as far apart as
 without it; a List shows no row for it). Its modifiers show nothing either, as in SwiftUI (it is in
 no panel).
*/

extension EmptyView: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        // Kept in the state: the panel's callbacks hold it weakly.
        let panel = try LayoutPanel()
        node.state = panel
        return panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {}

    static func takesNoPlace(_ node: RenderNode) -> Bool { true }
}
