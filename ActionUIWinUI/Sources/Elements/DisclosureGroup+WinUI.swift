// Sources/Elements/DisclosureGroup+WinUI.swift
/*
 DisclosureGroup on WinUI: an Expander (Windows' own: a header with a chevron over a content area that
 opens and closes), the title as its header; expanded, its children below in a column, as macOS shows a
 disclosure group's content under its title and Linux a GtkExpander's. Measured on macOS 27 (the Linux
 renderer's parity recordings):
 - It takes the width it is offered and the height it needs.
 - The children are a centered column with 8 points between them (none next to a Spacer, as in a
   VStack given no spacing), offered the group's width; the template form shows one template instance
   per content row (setElementRows) as the children (TemplateRows).
 - Expanded is states["isExpanded"], which starts as the isExpanded property; the host changes it with
   setElementState. The user's expanding or collapsing runs Core's DisclosureGroup.userSetExpanded (the
   state, then valueChangeActionID); the renderer's own change fires nothing (WinUI reports it as it
   reports the user's: the state the renderer last set is ignored).
 - Accessibility tools read the Expander with its expanded state, named after the title (set on it: its
   peer takes no name from the header).

 The Expander draws its content in its own card (a border and padding), the Windows look, where macOS
 indents nothing; the column's 8-point spacing is SwiftUI's.
*/

import CWinUI

/// What a DisclosureGroup keeps: its children's column and the state it last set.
@MainActor final class DisclosureState {
    let column: StackLayout
    var title: String?
    /// The expanded state the renderer last set: the Expander's event reporting it is the renderer's own.
    var shownExpanded: Bool?

    init(column: StackLayout) {
        self.column = column
    }
}

extension DisclosureGroup: ActionUIWinUIRenderer {
    /// The title, which the Expander is named after (actionUIWinUIExpanderSetTitle).
    static func defaultAccessibleName(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// As wide as it is offered, as tall as it needs, whatever its children do (measured on macOS 27).
    static var defaultExpansion: Expansion { .horizontal }

    /// Made smaller along an axis when a child can be (a long text wraps), as GroupBox and Section.
    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let column = try StackLayout(axis: .vertical)
        guard let expander = WinUIObject(adopting: actionUIWinUIExpanderCreate(column.panel.object.pointer)) else {
            throw WinUIError.last("creating a DisclosureGroup")
        }
        let state = DisclosureState(column: column)
        node.state = state
        WinUIEvents.connect(expander, actionUIWinUIExpanderOnExpandedChanged, "a DisclosureGroup's expansion") { [weak node, weak state, weak expander] in
            guard let node, let state, let expander, node.isAttached else { return }
            let expanded = actionUIWinUIExpanderIsExpanded(expander.pointer)
            // The renderer's own change, reported as the user's.
            guard expanded != state.shownExpanded else { return }
            state.shownExpanded = expanded
            DisclosureGroup.userSetExpanded(expanded, element: node.element, model: node.model,
                                            windowUUID: node.windowModel.windowUUID, props: Props(node.properties))
        }
        return expander
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? DisclosureState else { return }
        let props = Props(node.properties)
        if state.title != props.title {
            if actionUIWinUIExpanderSetTitle(view.pointer, props.title) {
                state.title = props.title
            } else {
                ActionUIModel.shared.logger.log("DisclosureGroup: \(WinUIError.last("showing the title"))", .error)
            }
        }
        node.applyTextAppearance(to: view, what: "a DisclosureGroup")
        let expanded = node.model.states["isExpanded"] as? Bool ?? props.isExpanded
        if expanded != state.shownExpanded {
            // Before the call, whose event can come at once.
            state.shownExpanded = expanded
            if !actionUIWinUIExpanderSetExpanded(view.pointer, expanded) {
                ActionUIModel.shared.logger.log("DisclosureGroup: \(WinUIError.last("expanding or collapsing"))", .error)
                // What it shows: else the user's change to `expanded` would pass for the renderer's own.
                state.shownExpanded = actionUIWinUIExpanderIsExpanded(view.pointer)
            }
        }
        // SwiftUI's default spacing: 8 points between the children, none next to a Spacer (measured on
        // macOS 27).
        StackViews.configure(state.column, spacing: nil, alignment: .center)
        syncStackContent(node, state.column)
    }
}
