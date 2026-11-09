/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Initial content",              // Optional: String initial value, defaults to ""
     "markdown": "**Bold** _italic_",  // Optional: Markdown string (macOS 26, iOS 26+). Rendered with markdown formatting; takes precedence over "text". Value is the AttributedString of the current content; accepts AttributedString or markdown String via setElementValue.
     "placeholder": "Enter text here",       // Optional: String, no default value if omitted or empty
     "readOnly": false,                       // Optional: Boolean; when true, text is selectable and scrollable but not editable. Defaults to false.
                                              //   Unlike "disabled" (which prevents all interaction including selection and scrolling),
                                              //   "readOnly" allows the user to select, scroll, and copy text but not modify it.
                                              //   Content can still be set programmatically via setElementValue.
     "implementation": "native"               // Optional: "swiftUI" (default) or "native". "native" draws the editor with the platform's
                                              //   own text view (macOS: an NSTextView), where a value that extends the text shown (appendElementText,
                                              //   or a setElementValue that starts with the current text) appends only the new text, at the new
                                              //   text's cost: for logs and large output. SwiftUI's TextEditor lays its whole text out again on
                                              //   every change. Plain text only: with "markdown" the default editor is used. The native editor
                                              //   takes its font and text color from the element's own "font" and "foregroundStyle" (not from an
                                              //   enclosing view); a "font" with both a name and a design uses the design when the named font is
                                              //   missing. iOS and Linux use their default editor (Linux's is already the platform's text view).
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)         Current plain-text content (via getElementValue / setElementValue).
//   value (AttributedString) Current attributed content when markdown is used (macOS 26, iOS 26+). setElementValue accepts AttributedString directly or a markdown String.
//   appendElementText appends to the value (to an AttributedString as an unstyled run); with "implementation": "native" only the
//   new text is laid out.
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
        var implementation = Implementation.swiftUI
        var valueChangeActionID: String?

        /// Which editor draws the element (the "implementation" property).
        enum Implementation: String, Sendable {
            /// SwiftUI's TextEditor. The default; also for an unknown value.
            case swiftUI
            /// The platform's own text view (macOS: NSTextView), which appends at the new text's cost.
            case native
        }

        init(_ properties: [String: Any]) {
            text = properties["text"] as? String
            markdown = properties["markdown"] as? String
            placeholder = properties["placeholder"] as? String
            readOnly = properties["readOnly"] as? Bool ?? false
            implementation = (properties["implementation"] as? String).flatMap(Implementation.init(rawValue:)) ?? .swiftUI
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }
    }
}

struct TextEditor: ActionUIElementSpec {
    // Rich-text string conversions; a renderer installs its own (SwiftUI: TextEditor+SwiftUI.swift,
    // from ActionUIRegistry.loadRendererBuiltIns). nil until then: the generic conversions apply.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

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
