// SwiftUI rendering of TextEditor; its portable part is in Core/Elements/TextEditor.swift.

import SwiftUI
import Combine

extension TextEditor: ActionUISwiftUIRenderer {
    // The spec's string conversions (parseStringValue, serializeValueToString), installed by
    // ActionUIRegistry.loadRendererBuiltIns: they delegate to AttributedStringHelper, which uses SwiftUI.
    static let swiftUIParseStringValue: (String, String?, any ActionUILogger) -> Any? = { value, contentType, logger in
        attributedStringParseContent(value, contentType: contentType, logger: logger)
    }

    static let swiftUISerializeValueToString: (Any, String?, any ActionUILogger) -> String? = { value, contentType, logger in
        attributedStringSerializeContent(value, contentType: contentType, logger: logger)
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

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

    /// Non-@State counter to track pending async model updates without triggering view refreshes.
    /// While pendingCount > 0, onReceive from model.valuePublisher is suppressed to prevent stale async
    /// updates from resetting @State text and jumping the cursor during fast typing.
    private class PendingUpdateTracker {
        var pendingCount = 0
    }

    /// Wrapper view that owns @State for text, keeping SwiftUI in full control of cursor position.
    /// Changes are synced to/from the ViewModel asynchronously, preventing cursor jumping
    /// when hosted in NSHostingController. Mirrors NavigationStack.NavigationPathContainer pattern.
    /// When markdown is set and running on macOS 26 / iOS 26+, delegates to AttributedTextEditorContainer.
    private struct TextEditorContainer: SwiftUI.View {
        let model: ViewModel
        @State private var text: String
        /// How many times typing was ignored in a read-only editor; the editor's identity, so it is
        /// made again with its text.
        @State private var ignoredEdits = 0
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
            let _ = model.trackAllChanges()
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
                        // Also while an update is pending: typing back to the model's value (a
                        // letter, then Backspace, in one turn) must not leave the pending, older
                        // text as the last one sent, which onReceive would then show.
                        if model.value as? String != newValue || tracker.pendingCount > 0 {
                            tracker.pendingCount += 1
                            DispatchQueue.main.async {
                                // Counted down first: a later keystroke's update is still pending, so
                                // this one's value is ignored by onReceive; the last one's equals the
                                // text. A value the action sets is then taken, as before.
                                tracker.pendingCount -= 1
                                TextField.userEditedText(newValue, valueChangeActionID: valueChangeActionID, viewID: elementId,
                                                         model: model, windowUUID: windowUUID)
                            }
                        }
                    }
                    .onReceive(model.valuePublisher.map { $0 as? String ?? initialValue }) { modelValue in
                        // Only accept external (programmatic) changes; suppress feedback from our own async updates
                        if tracker.pendingCount == 0 && modelValue != text {
                            text = modelValue
                        }
                    }
            }
        }

        /// The text the editor shows and edits; read-only, a binding that ignores what is typed: SwiftUI
        /// has no read-only TextEditor, and the editor then shows the text again at once while it stays
        /// selectable (measured on macOS 27, where .disabled(true) still let the text view change). The
        /// ignored edit still makes the editor again: the text view's undo would otherwise undo it on the
        /// text shown again, which raised NSRangeException on macOS 27 after typing at the end.
        private var editorText: Binding<String> {
            isReadOnly ? Binding(get: { text }, set: { if $0 != text { ignoredEdits += 1 } }) : $text
        }

        @ViewBuilder
        private var textEditorView: some SwiftUI.View {
            if let placeholder, !placeholder.isEmpty {
                SwiftUI.TextEditor(text: editorText)
                    .id(ignoredEdits)
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
                SwiftUI.TextEditor(text: editorText)
                    .id(ignoredEdits)
            }
        }
    }

    /// Attributed-text editor for macOS 26 / iOS 26+. Stores AttributedString in model.value,
    /// accepting either AttributedString or a markdown String via setElementValue.
    @available(iOS 26.0, macOS 26.0, *)
    private struct AttributedTextEditorContainer: SwiftUI.View {
        let model: ViewModel
        @State private var attributedContent: AttributedString
        /// How many times typing was ignored in a read-only editor; the editor's identity, so it is
        /// made again with its content.
        @State private var ignoredEdits = 0
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
            let _ = model.trackAllChanges()
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
                .onReceive(model.valuePublisher) { newValue in
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

        /// The content the editor shows and edits; read-only, a binding that ignores what is typed, as
        /// in TextEditorContainer.editorText. The attributed editor does not show its content again by
        /// itself then (measured on macOS 27), so an ignored edit makes it again. Only an edit: a
        /// selection change also sets the content, unchanged, and making the editor again then would
        /// drop the selection and the focus.
        private var editorContent: Binding<AttributedString> {
            isReadOnly
                ? Binding(get: { attributedContent }, set: { if $0 != attributedContent { ignoredEdits += 1 } })
                : $attributedContent
        }

        @ViewBuilder
        private var attributedEditorView: some SwiftUI.View {
            if let placeholder, !placeholder.isEmpty {
                SwiftUI.TextEditor(text: editorContent)
                    .id(ignoredEdits)
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
                SwiftUI.TextEditor(text: editorContent)
                    .id(ignoredEdits)
            }
        }
    }
}

