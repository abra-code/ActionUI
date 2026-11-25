// Sources/Runtime/PlaceholderRenderer.swift
/*
 What an element type without a WinUI renderer shows: its type name in brackets, so a UI
 still opens and shows where the missing element is (Linux shows a placeholder too).
*/

import CWinUI

enum PlaceholderRenderer: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let text = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a placeholder")
        }
        return text
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        _ = actionUIWinUITextBlockSetText(view.pointer, "[\(node.element.type)]")
    }
}
