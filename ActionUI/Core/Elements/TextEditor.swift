/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Initial content",              // Optional: String initial value, defaults to ""
     "markdown": "**Bold** _italic_",  // Optional: Markdown string (macOS 26, iOS 26+). Rendered with markdown formatting; takes precedence over "text". Value is the AttributedString of the current content; accepts AttributedString or markdown String via setElementValue.
     "placeholder": "Enter text here",       // Optional: String, no default value if omitted or empty
     "readOnly": false                        // Optional: Boolean; when true, text is selectable and scrollable but not editable. Defaults to false.
                                              //   Unlike "disabled" (which prevents all interaction including selection and scrolling),
                                              //   "readOnly" allows the user to select, scroll, and copy text but not modify it.
                                              //   Content can still be set programmatically via setElementValue.
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)         Current plain-text content (via getElementValue / setElementValue).
//   value (AttributedString) Current attributed content when markdown is used (macOS 26, iOS 26+). setElementValue accepts AttributedString directly or a markdown String.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension TextEditor {
    /// TextEditor's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The initial plain text; nil when not given (or not a String).
        var text: String?
        /// The initial markdown content; nil when not given (or not a String).
        var markdown: String?
        var placeholder: String?
        var readOnly = false
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            text = properties["text"] as? String
            markdown = properties["markdown"] as? String
            placeholder = properties["placeholder"] as? String
            readOnly = properties["readOnly"] as? Bool ?? false
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }
    }
}

struct TextEditor: ActionUIElementSpec {
    // parseStringValue and serializeValueToString are in TextEditor+SwiftUI.swift: the rich-text helper they call uses SwiftUI.
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var insertableContainers: [String: ContainerShape]? = nil

    // Design decision: Defines valueType as String to reflect text input for type-safe string parsing in ActionUIModel.
    // When markdown is used, model.value holds AttributedString; getElementValueAsString extracts plain text.
    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        if let attributedValue = model.value as? AttributedString {
            return String(attributedValue.characters)
        }
        let props = Props(model.properties)
        if let text = props.text {
            return text
        }
        if let markdown = props.markdown {
            return markdown
        }
        return ""
    }
}
