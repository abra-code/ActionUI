// Sources/Elements/Text+WinUI.swift
/*
 Text on WinUI: a TextBlock showing the value (a String or an AttributedString set at run time),
 else the markdown property's text, else the text property, as on Apple and Linux. It wraps as
 SwiftUI's Text does, at word boundaries and inside a word that does not fit, when offered less
 width than one line needs (in a VStack narrower than the line; an HStack does not yet compress
 its children).

 Not yet: fonts, colors and alignment. Markdown shows its
 source as is (asterisks included): Core's default markdown hook makes no styles, and the Markdown
 parser the GTK renderer uses has not moved to the shared code yet.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

extension Text: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let text = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a TextBlock")
        }
        guard actionUIWinUITextBlockSetWraps(text.pointer, true) else {
            throw WinUIError.last("making a TextBlock wrap")
        }
        return text
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let shown = displayedText(node.model.value, node.properties)
        let state = node.state as? ShownText ?? ShownText()
        node.state = state
        // Set only when it changed: a new text changes the TextBlock's size, and WinUI lays its
        // parents out again.
        if state.text != shown {
            if actionUIWinUITextBlockSetText(view.pointer, shown) {
                state.text = shown
            } else {
                // Not remembered, so the next update tries again.
                ActionUIModel.shared.logger.log("Text: \(WinUIError.last("setting a TextBlock's text"))", .error)
            }
        }
    }

    /// What a Text with `value` and `properties` shows, as plain text: the value, else the
    /// markdown (through ActionUIRendererHooks.markdown), else the text property.
    static func displayedText(_ value: Any?, _ properties: [String: Any]) -> String {
        if let attributed = value as? AttributedString {
            return String(attributed.characters)
        }
        if let plain = value as? String {
            return plain
        }
        let props = Props(properties)
        if let markdown = props.markdown {
            return String(ActionUIRendererHooks.markdown(markdown).characters)
        }
        return props.text
    }
}

/// The text a Text node's TextBlock shows (nil before the first update).
@MainActor final class ShownText {
    var text: String?
}
