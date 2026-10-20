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

import SwiftUI
import Combine

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

struct TextEditor: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    // Delegates to AttributedStringHelper for all content-type parsing and serialization.
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = { value, contentType, logger in
        attributedStringParseContent(value, contentType: contentType, logger: logger)
    }

    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = { value, contentType, logger in
        attributedStringSerializeContent(value, contentType: contentType, logger: logger)
    }

    static var insertableContainers: [String: ContainerShape]? = nil

    // Design decision: Defines valueType as String to reflect text input for type-safe string parsing in ActionUIModel.
    // When markdown is used, model.value holds AttributedString; getElementValueAsString extracts plain text.
    static var valueType: Any.Type = String.self

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? String ?? ""
        let props = Props(properties)
        let isReadOnly = props.readOnly
        let placeholder = props.placeholder
        let valueChangeActionID = props.valueChangeActionID
        let markdown = props.markdown

        return TextEditorContainer(
            model: model,
            initialValue: initialValue,
            isReadOnly: isReadOnly,
            placeholder: placeholder,
            valueChangeActionID: valueChangeActionID,
            windowUUID: windowUUID,
            elementId: element.id,
            markdown: markdown
        )
    }

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

    /// Non-@State counter to track pending async model updates without triggering view refreshes.
    /// While pendingCount > 0, onReceive from model.$value is suppressed to prevent stale async
    /// updates from resetting @State text and jumping the cursor during fast typing.
    private class PendingUpdateTracker {
        var pendingCount = 0
    }

    /// Wrapper view that owns @State for text, keeping SwiftUI in full control of cursor position.
    /// Changes are synced to/from the ViewModel asynchronously, preventing cursor jumping
    /// when hosted in NSHostingController. Mirrors NavigationStack.NavigationPathContainer pattern.
    /// When markdown is set and running on macOS 26 / iOS 26+, delegates to AttributedTextEditorContainer.
    private struct TextEditorContainer: SwiftUI.View {
        @ObservedObject var model: ViewModel
        @State private var text: String
        @State private var tracker = PendingUpdateTracker()
        let initialValue: String
        let isReadOnly: Bool
        let placeholder: String?
        let valueChangeActionID: String?
        let windowUUID: String
        let elementId: Int
        let markdown: String?

        init(model: ViewModel, initialValue: String, isReadOnly: Bool, placeholder: String?,
             valueChangeActionID: String?, windowUUID: String, elementId: Int, markdown: String? = nil) {
            self.model = model
            self.initialValue = initialValue
            self.isReadOnly = isReadOnly
            self.placeholder = placeholder
            self.valueChangeActionID = valueChangeActionID
            self.windowUUID = windowUUID
            self.elementId = elementId
            self.markdown = markdown
            self._text = State(initialValue: model.value as? String ?? initialValue)
        }

        var body: some SwiftUI.View {
            if #available(iOS 26.0, macOS 26.0, *), let markdownText = markdown {
                AttributedTextEditorContainer(
                    model: model,
                    initialMarkdown: markdownText,
                    isReadOnly: isReadOnly,
                    placeholder: placeholder,
                    valueChangeActionID: valueChangeActionID,
                    windowUUID: windowUUID,
                    elementId: elementId
                )
            } else {
                textEditorView
                    .onChange(of: text) { _, newValue in
                        // User typing → sync to model asynchronously (safe since @State holds cursor truth)
                        if isReadOnly { return }
                        if model.value as? String != newValue {
                            tracker.pendingCount += 1
                            DispatchQueue.main.async {
                                model.value = newValue
                                tracker.pendingCount -= 1
                                if let valueChangeActionID {
                                    ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: elementId, viewPartID: 0)
                                }
                            }
                        }
                    }
                    .onReceive(model.$value.map { $0 as? String ?? initialValue }) { modelValue in
                        // Only accept external (programmatic) changes; suppress feedback from our own async updates
                        if tracker.pendingCount == 0 && modelValue != text {
                            text = modelValue
                        }
                    }
            }
        }

        @ViewBuilder
        private var textEditorView: some SwiftUI.View {
            if let placeholder, !placeholder.isEmpty {
                SwiftUI.TextEditor(text: $text)
                    .overlay(
                        SwiftUI.Group {
                            if text.isEmpty {
                                SwiftUI.Text(placeholder)
                                    .foregroundColor(.gray)
                                    .allowsHitTesting(false)
                            } else {
                                SwiftUI.EmptyView()
                            }
                        },
                        alignment: .topLeading
                    )
            } else {
                SwiftUI.TextEditor(text: $text)
            }
        }
    }

    /// Attributed-text editor for macOS 26 / iOS 26+. Stores AttributedString in model.value,
    /// accepting either AttributedString or a markdown String via setElementValue.
    @available(iOS 26.0, macOS 26.0, *)
    private struct AttributedTextEditorContainer: SwiftUI.View {
        @ObservedObject var model: ViewModel
        @State private var attributedContent: AttributedString
        @State private var tracker = PendingUpdateTracker()
        let initialMarkdown: String
        let isReadOnly: Bool
        let placeholder: String?
        let valueChangeActionID: String?
        let windowUUID: String
        let elementId: Int

        init(model: ViewModel, initialMarkdown: String, isReadOnly: Bool, placeholder: String?,
             valueChangeActionID: String?, windowUUID: String, elementId: Int) {
            self.model = model
            self.initialMarkdown = initialMarkdown
            self.isReadOnly = isReadOnly
            self.placeholder = placeholder
            self.valueChangeActionID = valueChangeActionID
            self.windowUUID = windowUUID
            self.elementId = elementId
            let initial: AttributedString
            if let storedAttr = model.value as? AttributedString {
                initial = storedAttr
            } else if let storedString = model.value as? String {
                initial = (try? AttributedString(markdown: storedString)) ?? AttributedString(storedString)
            } else {
                initial = (try? AttributedString(markdown: initialMarkdown)) ?? AttributedString(initialMarkdown)
            }
            self._attributedContent = State(initialValue: initial)
        }

        var body: some SwiftUI.View {
            attributedEditorView
                .onChange(of: attributedContent) { _, newValue in
                    if isReadOnly { return }
                    if model.value as? AttributedString != newValue {
                        tracker.pendingCount += 1
                        DispatchQueue.main.async {
                            model.value = newValue
                            tracker.pendingCount -= 1
                            if let valueChangeActionID {
                                ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: elementId, viewPartID: 0)
                            }
                        }
                    }
                }
                .onReceive(model.$value) { newValue in
                    guard tracker.pendingCount == 0 else { return }
                    if let attrValue = newValue as? AttributedString, attrValue != attributedContent {
                        attributedContent = attrValue
                    } else if let stringValue = newValue as? String {
                        let parsed = (try? AttributedString(markdown: stringValue)) ?? AttributedString(stringValue)
                        if parsed != attributedContent {
                            attributedContent = parsed
                        }
                    }
                }
        }

        @ViewBuilder
        private var attributedEditorView: some SwiftUI.View {
            if let placeholder, !placeholder.isEmpty {
                SwiftUI.TextEditor(text: $attributedContent)
                    .overlay(
                        SwiftUI.Group {
                            if attributedContent.characters.isEmpty {
                                SwiftUI.Text(placeholder)
                                    .foregroundColor(.gray)
                                    .allowsHitTesting(false)
                            } else {
                                SwiftUI.EmptyView()
                            }
                        },
                        alignment: .topLeading
                    )
            } else {
                SwiftUI.TextEditor(text: $attributedContent)
            }
        }
    }
}

