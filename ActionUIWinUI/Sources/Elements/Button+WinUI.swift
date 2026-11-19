// Sources/Elements/Button+WinUI.swift
/*
 Button on WinUI: a Button whose content follows the properties as SwiftUI's label does, as on Linux:
 the title alone as text; the symbol (systemImage) alone as an icon; both side by side, 8 apart
 (IconTitleLayout). The symbol is the one Image shows for the name (ImageLayout.symbolSide: the font
 size times 1.18, imageScale's 0.8 and 1.28), and it takes the button's text color, which follows the
 button's state. A click (pointer, keyboard, or an accessibility tool's invoke) runs Core's
 Button.userTapped (popover, sheet, cover, actionID), as a tap does on Apple and a click on Linux; an
 update never fires it (WinUI's Click comes from the user only).

 Not yet: assetImage (a button with one shows its systemImage, where Apple shows the asset); an
 accessible name for a button showing only a symbol (Apple names it after the symbol); role and
 buttonStyle, controlSize.
*/

import CWinUI

/// What a Button shows, kept in its node's state.
@MainActor final class ButtonContent {
    enum Kind: Equatable {
        case title(String)
        case icon(String)
        case iconAndTitle(String)
    }

    var kind: Kind?
    /// The symbol shown alone, and the side it was sized to.
    var icon: WinUIObject?
    var iconSide = -1.0
    /// The icon and the title side by side.
    var layout: IconTitleLayout?
}

extension Button: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()) else {
            throw WinUIError.last("creating a Button")
        }
        WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a Button's click") { [weak node] in
            guard let node, node.isAttached else { return }
            Button.userTapped(element: node.effectiveElement, model: node.model, windowUUID: node.windowModel.windowUUID,
                              props: Props(node.properties))
        }
        node.state = ButtonContent()
        return button
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        node.applyTextAppearance(to: view, what: "a Button")
        guard let content = node.state as? ButtonContent else { return }
        let props = Props(node.properties)
        let side = ImageLayout.symbolSide(node, scale: props.imageScale?.rawValue)
        let kind: ButtonContent.Kind
        // An empty name is no image, as on Apple and Linux.
        if let symbol = props.systemImage, !symbol.isEmpty {
            kind = props.title.isEmpty ? .icon(symbol) : .iconAndTitle(symbol)
        } else {
            kind = .title(props.title)
        }
        if kind != content.kind {
            show(kind, in: view, content: content)
        }
        if case .iconAndTitle = kind {
            content.layout?.setTitle(props.title)
            content.layout?.setIconSide(side)
        }
        // The content's own objects: hiding the button from accessibility tools does not hide them.
        if let icon = content.icon {
            node.applyAccessibilityHidden(to: icon)
        }
        if let layout = content.layout {
            node.applyAccessibilityHidden(to: layout.title)
            if let icon = layout.icon {
                node.applyAccessibilityHidden(to: icon)
            }
        }
        if case .icon = kind, let icon = content.icon, side != content.iconSide {
            content.iconSide = side
            if !actionUIWinUISymbolSetSize(icon.pointer, side) {
                ActionUIModel.shared.logger.log("Button: \(WinUIError.last("sizing a symbol"))", .error)
            }
        }
    }

    /// Makes the button's content for `kind`.
    private static func show(_ kind: ButtonContent.Kind, in view: WinUIObject, content: ButtonContent) {
        content.kind = kind
        content.icon = nil
        content.iconSide = -1
        var shown = true
        switch kind {
        case .title(let title):
            content.layout = nil
            shown = actionUIWinUIButtonSetTitle(view.pointer, title)
        case .icon(let name):
            content.layout = nil
            content.icon = ImageLayout.makeSymbol(name)
            shown = actionUIWinUIButtonSetContent(view.pointer, content.icon?.pointer)
        case .iconAndTitle(let name):
            do {
                let layout = try IconTitleLayout()
                layout.setIcon(ImageLayout.makeSymbol(name))
                content.layout = layout
                shown = actionUIWinUIButtonSetContent(view.pointer, layout.panel.object.pointer)
            } catch {
                ActionUIModel.shared.logger.log("Button: \(error)", .error)
                content.layout = nil
                // Not remembered, so the next update tries again.
                content.kind = nil
            }
        }
        if !shown {
            ActionUIModel.shared.logger.log("Button: \(WinUIError.last("setting a Button's content"))", .error)
            // Not remembered, so the next update tries again (the button still shows what it showed).
            content.kind = nil
        }
    }
}
