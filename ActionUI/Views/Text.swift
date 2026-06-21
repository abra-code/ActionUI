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
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)         Current plain-text content (via getElementValue / setElementValue).
//   value (AttributedString) Current attributed content when markdown is used or an AttributedString is set via setElementValue.
//                            setElementValue accepts AttributedString directly or a markdown String.
*/

import SwiftUI

struct Text: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    // Defines valueType as String to reflect plain-text access; model.value may hold AttributedString.
    static var valueType: Any.Type = String.self

    // Delegates to AttributedStringHelper for all content-type parsing and serialization.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = { value, contentType, logger in
        attributedStringParseContent(value, contentType: contentType, logger: logger)
    }

    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = { value, contentType, logger in
        attributedStringSerializeContent(value, contentType: contentType, logger: logger)
    }
    static var insertableContainers: [String: ContainerShape]? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        if properties["markdown"] != nil && !(properties["markdown"] is String) {
            logger.log("Text markdown must be a String; ignoring", .warning)
            validatedProperties["markdown"] = nil
        }
        if properties["text"] != nil && validatedProperties["markdown"] != nil {
            logger.log("Text has both text and markdown; markdown takes precedence", .warning)
        }
        return validatedProperties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, model, _, properties, _ in
        // Runtime value (set via setElementValue) takes precedence - an AttributedString or a plain String;
        // otherwise the markdown / text property. ActionUIView already owns the ViewModel as an
        // @ObservedObject and re-builds this leaf when model.value changes, so no reactive container is needed.
        if let attr = model.value as? AttributedString {
            return SwiftUI.Text(attr)
        }
        if let str = model.value as? String {
            return SwiftUI.Text(str)
        }
        if let markdown = properties["markdown"] as? String {
            return SwiftUI.Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
        }
        return SwiftUI.Text(properties["text"] as? String ?? "")
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let attr = model.value as? AttributedString { return attr }
        if let str = model.value as? String { return str }
        if let attrText = model.validatedProperties["markdown"] as? String {
            return (try? AttributedString(markdown: attrText)) ?? AttributedString(attrText)
        }
        return model.validatedProperties["text"] as? String ?? ""
    }
}
