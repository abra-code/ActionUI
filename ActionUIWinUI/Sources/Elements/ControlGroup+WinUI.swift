// Sources/Elements/ControlGroup+WinUI.swift
/*
 ControlGroup on WinUI: its children side by side with no gap, their buttons joined into one bar (the
 outer corners rounded, one border between neighbors), as macOS joins a control group's buttons into one
 bar with thin separators and the Linux renderer GTK's linked buttons. As large as its children
 (measured on macOS 27: it does not grow in either axis).

 - A Button's or a Menu's button is joined (actionUIWinUIControlSetJoined) by its place among all the
   children, as the Linux renderer's linked boxes: a button after a Text has square leading corners;
   another child sits in the row as it is.
 - A child's padding and frame do not apply (RenderNode's geometry): macOS draws the group from its
   buttons' titles and ignores both, so padded buttons stay joined.
 - The title is not shown, as macOS shows none for a control group outside a menu or a toolbar.

 Not yet: a Picker, Toggle or Stepper joined into the bar (macOS joins a Picker as segments); a title
 for accessibility tools (macOS reads the buttons).
*/

import CWinUI

/// What a ControlGroup keeps: its row and the children it joined, in order.
@MainActor final class ControlGroupState {
    let row: StackLayout
    var joined: [ObjectIdentifier] = []

    init(row: StackLayout) {
        self.row = row
    }
}

extension ControlGroup: ActionUIWinUIRenderer {
    /// The children whose WinUI object is a button the group joins.
    static let joinedTypes: Set<String> = ["Button", "Menu"]

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let row = try StackLayout(axis: .horizontal)
        node.state = ControlGroupState(row: row)
        return row.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ControlGroupState else { return }
        StackViews.configure(state.row, spacing: 0, alignment: .center)
        syncStackContent(node, state.row)
        // Join the buttons by their place among all the children, as the Linux renderer's linked boxes: the
        // first child rounded at its leading edge, the last at its trailing one. Again only when the
        // children or their order changed. A child that takes no place (an EmptyView) is not counted. A
        // button whose object could not be made shows a placeholder (no Control), which is not joined.
        let children = node.orderedChildren.filter { !$0.takesNoPlace }
        let identities = children.map { ObjectIdentifier($0) }
        guard identities != state.joined else { return }
        state.joined = identities
        for (index, child) in children.enumerated()
        where joinedTypes.contains(child.element.type) && child.view != nil && !(child.renderer is PlaceholderRenderer.Type) {
            if !actionUIWinUIControlSetJoined(child.view.pointer, index == 0, index == children.count - 1) {
                ActionUIModel.shared.logger.log("ControlGroup: \(WinUIError.last("joining a button"))", .error)
            }
        }
    }
}
