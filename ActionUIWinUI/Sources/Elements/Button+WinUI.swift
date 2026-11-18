// Sources/Elements/Button+WinUI.swift
/*
 Button on WinUI: a Button showing the title. A click (pointer, keyboard, or an accessibility
 tool's invoke) runs Core's Button.userTapped (popover, sheet, cover, actionID), as a tap does on
 Apple and a click on Linux; an update never fires it (WinUI's Click comes from the user only).

 Not yet: images (systemImage, assetImage), role and buttonStyle, controlSize.
*/

import CWinUI

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
        return button
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let title = Props(node.properties).title
        let state = node.state as? ShownText ?? ShownText()
        node.state = state
        if state.text != title {
            if actionUIWinUIButtonSetTitle(view.pointer, title) {
                state.text = title
            } else {
                ActionUIModel.shared.logger.log("Button: \(WinUIError.last("setting a Button's title"))", .error)
            }
        }
    }
}
