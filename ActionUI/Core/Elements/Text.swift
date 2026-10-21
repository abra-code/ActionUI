/*
 Sample JSON for Text:
 {
   "type": "Text",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello, World!",               // Optional: String, defaults to empty string
     "markdown": "**Bold** _italic_"  // Optional: Markdown string. Rendered with markdown formatting; takes precedence over "text".
                                            //   Value is the AttributedString of the current content; accepts AttributedString or markdown String via setElementValue.
   }
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)         Current plain-text content (via getElementValue / setElementValue).
//   value (AttributedString) Current attributed content when markdown is used or an AttributedString is set via setElementValue.
//                            setElementValue accepts AttributedString directly or a markdown String.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Text {
    /// Text's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The plain content; "" when not given (or not a String).
        var text = ""
        /// The markdown content, which takes precedence over "text"; nil when not given (or not a String).
        var markdown: String?

        init(_ properties: [String: Any]) {
            text = properties["text"] as? String ?? ""
            markdown = properties["markdown"] as? String
        }
    }
}

struct Text: ActionUIElementSpec {
    // Rich-text string conversions; a renderer installs its own (SwiftUI: Text+SwiftUI.swift, from
    // ActionUIRegistry.loadRendererBuiltIns). nil until then: the generic conversions apply.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    // Defines valueType as String to reflect plain-text access; model.value may hold AttributedString.
    static var valueType: Any.Type = String.self

    static var insertableContainers: [String: ContainerShape]? = nil

    static var initialValue: (ViewModel) -> Any? = { model in
        if let attr = model.value as? AttributedString { return attr }
        if let str = model.value as? String { return str }
        let props = Props(model.properties)
        if let attrText = props.markdown {
            return ActionUIRendererHooks.markdown(attrText)
        }
        return props.text
    }
}
