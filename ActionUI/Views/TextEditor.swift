/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Initial content",        // Optional: String initial value, defaults to ""
     "placeholder": "Enter text here", // Optional: String, no default value if omitted or empty
     "readOnly": false                 // Optional: Boolean; when true, text is selectable and scrollable but not editable. Defaults to false.
                                       //   Unlike "disabled" (which prevents all interaction including selection and scrolling),
                                       //   "readOnly" allows the user to select, scroll, and copy text but not modify it.
                                       //   Content can still be set programmatically via setElementValue.
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI
import Combine

struct TextEditor: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect text input for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { String.self }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        // Validate text (initial value)
        if properties["text"] != nil && !(properties["text"] is String) {
            logger.log("TextEditor text must be a String; ignoring", .warning)
            validatedProperties["text"] = nil
        }

        // Validate placeholder
        if !(properties["placeholder"] is String?), properties["placeholder"] != nil {
            logger.log("TextEditor placeholder must be a String; defaulting to nil", .warning)
            validatedProperties["placeholder"] = nil
        }

        return validatedProperties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? String ?? ""
        let isReadOnly = properties["readOnly"] as? Bool ?? false
        let placeholder = properties["placeholder"] as? String
        let valueChangeActionID = properties["valueChangeActionID"] as? String

        return TextEditorContainer(
            model: model,
            initialValue: initialValue,
            isReadOnly: isReadOnly,
            placeholder: placeholder,
            valueChangeActionID: valueChangeActionID,
            windowUUID: windowUUID,
            elementId: element.id
        )
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        if let text = model.validatedProperties["text"] as? String {
            return text
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

        init(model: ViewModel, initialValue: String, isReadOnly: Bool, placeholder: String?,
             valueChangeActionID: String?, windowUUID: String, elementId: Int) {
            self.model = model
            self.initialValue = initialValue
            self.isReadOnly = isReadOnly
            self.placeholder = placeholder
            self.valueChangeActionID = valueChangeActionID
            self.windowUUID = windowUUID
            self.elementId = elementId
            self._text = State(initialValue: model.value as? String ?? initialValue)
        }

        var body: some SwiftUI.View {
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
}
