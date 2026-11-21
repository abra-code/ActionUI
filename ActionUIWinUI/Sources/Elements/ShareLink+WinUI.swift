// Sources/Elements/ShareLink+WinUI.swift
/*
 ShareLink on WinUI: a button with the share symbol (square.and.arrow.up) and "Share", as SwiftUI's
 ShareLink shows on macOS (measured on macOS 27 for the Linux renderer: a bordered button like a
 Button's, the symbol and "Share" with an ellipsis; Windows' own share buttons say "Share"). A click
 opens Windows' share sheet for the button's window (DataTransferManager, as a desktop app shares),
 as macOS opens its sharing services:
 - the item's URL as a web link, titled by the subject property, else by the URL (the sheet needs a
   title);
 - for targets that take text (a mail's body), the message property, a blank line and the URL, or
   the URL alone without a message, as Mail shares a link on macOS and the Linux renderer's mail does.
   An item that is not an absolute URL ("example.com", which Core takes) is shared as that text alone.

 - The item is a URL string (ShareLink.Props); without one the button takes no place and no spacing,
   as SwiftUI shows an EmptyView (logged once), and is collapsed wherever it is (a ScrollView's
   content, a tab), as Link is.
 - Its accessible name is accessibilityLabel, else "Share".

 Not yet: controlSize and buttonStyle, as for a Button.
*/

import CWinUI

@MainActor private var reportedMissingItem = false

/// A ShareLink's button content.
@MainActor final class ShareLinkState {
    let layout: IconTitleLayout
    var shownName: String?
    /// Whether the button is collapsed (no item), nil before the first update.
    var collapsed: Bool?

    init(layout: IconTitleLayout) {
        self.layout = layout
    }
}

extension ShareLink: ActionUIWinUIRenderer {
    static let title = "Share"
    static let symbol = "square.and.arrow.up"

    static func takesNoPlace(_ node: RenderNode) -> Bool {
        Props(node.properties).item == nil
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()) else {
            throw WinUIError.last("creating a ShareLink")
        }
        let layout = try IconTitleLayout()
        layout.setIcon(ImageLayout.makeSymbol(symbol))
        layout.setTitle(title)
        if !actionUIWinUIButtonSetContent(button.pointer, layout.panel.object.pointer) {
            ActionUIModel.shared.logger.log("ShareLink: \(WinUIError.last("setting the button's content"))", .error)
        }
        node.state = ShareLinkState(layout: layout)
        WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a ShareLink's click") { [weak node, weak button] in
            guard let node, let button, node.isAttached else { return }
            share(node, from: button)
        }
        return button
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ShareLinkState else { return }
        let props = Props(node.properties)
        if props.item == nil, !reportedMissingItem {
            reportedMissingItem = true
            ActionUIModel.shared.logger.log("ShareLink \(node.element.id): no item URL to share; nothing is shown", .warning)
        }
        // No item: the button collapses itself, so it shows nothing and takes no keyboard focus also
        // where its container does not leave it out (takesNoPlace), as Link does.
        let collapsed = props.item == nil
        if state.collapsed != collapsed {
            if actionUIWinUIElementSetCollapsed(view.pointer, collapsed) {
                state.collapsed = collapsed
            } else {
                ActionUIModel.shared.logger.log("ShareLink: \(WinUIError.last("hiding a ShareLink with no item"))", .error)
            }
        }
        node.applyTextAppearance(to: view, what: "a ShareLink")
        state.layout.setIconSide(ImageLayout.symbolSide(node, scale: nil))
        let name = BaseModifiers(node.properties).accessibilityLabel ?? title
        if name != state.shownName {
            if actionUIWinUIElementSetAccessibleName(view.pointer, name) {
                state.shownName = name
            } else {
                ActionUIModel.shared.logger.log("ShareLink: \(WinUIError.last("naming the button"))", .error)
            }
        }
        node.applyAccessibilityHidden(to: state.layout.title)
        if let icon = state.layout.icon {
            node.applyAccessibilityHidden(to: icon)
        }
    }

    /// The click: Windows' share sheet with the item.
    private static func share(_ node: RenderNode, from button: WinUIObject) {
        let props = Props(node.properties)
        guard let item = props.item else { return }
        let subject = props.subject.flatMap { $0.isEmpty ? nil : $0 }
        let text = props.message.flatMap { $0.isEmpty ? nil : "\($0)\n\n\(item)" } ?? item
        if !actionUIWinUIShareLink(button.pointer, item, subject ?? item, text) {
            ActionUIModel.shared.logger.log("ShareLink: \(WinUIError.last("opening the share sheet"))", .error)
        }
    }
}
