// SwiftUI rendering of Text; its portable part is in Core/Elements/Text.swift.

import SwiftUI

extension Text: ActionUISwiftUIRenderer {
    // Delegates to AttributedStringHelper for all content-type parsing and serialization. The string
    // conversions are part of the element's spec, but they live here because that helper uses SwiftUI.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = { value, contentType, logger in
        attributedStringParseContent(value, contentType: contentType, logger: logger)
    }

    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = { value, contentType, logger in
        attributedStringSerializeContent(value, contentType: contentType, logger: logger)
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, model, _, properties, _ in
        let props = Props(properties)
        // Runtime value (set via setElementValue) takes precedence - an AttributedString or a plain String;
        // otherwise the markdown / text property. ActionUIView already observes the ViewModel
        // and re-builds this leaf when model.value changes, so no reactive container is needed.
        //
        // An empty string reserves no line height in SwiftUI, so a styled / sized Text box collapses when
        // empty and grows once content arrives (e.g. a result field before its value is set). Substituting a
        // zero-width space keeps one line's height for an empty Text, matching the Web renderer
        // (`.aui-text:empty::before`); it is invisible and gone the moment real content is set.
        func reserveLine(_ s: String) -> String { s.isEmpty ? "\u{200B}" : s }
        if let attr = model.value as? AttributedString {
            return attr.characters.isEmpty ? SwiftUI.Text(verbatim: "\u{200B}") : SwiftUI.Text(attr)
        }
        if let str = model.value as? String {
            return SwiftUI.Text(reserveLine(str))
        }
        if let markdown = props.markdown {
            return SwiftUI.Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
        }
        return SwiftUI.Text(reserveLine(props.text))
    }
}
