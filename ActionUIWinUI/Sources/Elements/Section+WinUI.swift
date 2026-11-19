// Sources/Elements/Section+WinUI.swift
/*
 Section on WinUI: its header, a line of text, then its rows, in a column. Measured on macOS 27 in a Form
 (for the Linux renderer): a Section adds no space of its own, so a Form's rows are as far apart across
 Sections as within one, and the header is as far above the first row as the rows are apart. So the
 column takes the spacing and alignment of the stack it is in (a Form's 8 and leading edge, a VStack's
 own, a GroupBox's, an enclosing Section's), and elsewhere no spacing, centered, as on Linux; without a
 header the column holds only the rows.

 Not yet: the template form (one row per content row after the header); a Section in a List is one
 row (header and rows), where SwiftUI shows its rows as the List's under a header; a Section in an HStack (Linux
 lays its rows out as the row's own); the Section's modifiers apply to the whole column, where the Linux
 renderer applies them to each row, as SwiftUI does.
*/

import CWinUI

/// A Section's column and its header.
@MainActor final class SectionState {
    let stack: StackLayout
    let header: WinUIObject
    var shownHeader: String?

    init(stack: StackLayout, header: WinUIObject) {
        self.stack = stack
        self.header = header
    }
}

extension Section: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let stack = try StackLayout(axis: .vertical)
        guard let header = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a Section's header")
        }
        node.state = SectionState(stack: stack, header: header)
        return stack.panel.object
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? SectionState else { return }
        // The spacing and alignment of the stack the Section is in, as its rows are that stack's on macOS.
        let spacing: Double?
        let alignment: StackSolver.Alignment
        switch node.parent?.element.type {
        case "Form":
            spacing = Form.rowSpacing
            alignment = .start
        case "VStack", "LazyVStack":
            let props = VStack.Props(node.parent?.properties ?? [:])
            spacing = props.spacing
            switch props.alignment {
            case .leading: alignment = .start
            case .center: alignment = .center
            case .trailing: alignment = .end
            }
        case "GroupBox":
            // A GroupBox's content is a column at the default spacing, centered.
            spacing = nil
            alignment = .center
        case "Section":
            // The enclosing Section's column (synced first), as SwiftUI lays nested Sections' rows out as one.
            let outer = (node.parent?.state as? SectionState)?.stack
            spacing = outer?.spacing ?? 0
            alignment = outer?.alignment ?? .center
        default:
            spacing = 0
            alignment = .center
        }
        StackViews.configure(state.stack, spacing: spacing, alignment: alignment)
        let header = Props(node.properties).header ?? ""
        if header != state.shownHeader {
            if actionUIWinUITextBlockSetText(state.header.pointer, header) {
                state.shownHeader = header
            } else {
                ActionUIModel.shared.logger.log("Section: \(WinUIError.last("setting the header"))", .error)
            }
        }
        node.applyTextAppearance(to: state.header, what: "a Section's header")
        node.applyAccessibilityHidden(to: state.header)
        let headerItem = header.isEmpty ? [] : [StackLayout.Item(view: state.header, spacerMinimum: nil)]
        state.stack.setItems(headerItem + stackItems(node.syncChildren(node.subviews("children"))))
    }
}
