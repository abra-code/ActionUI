// Sources/Views/ComboBox.swift
/*
 Sample JSON for ComboBox (macOS, iOS, iPadOS only):
 {
   "type": "ComboBox",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Option1",                  // Optional: String initial value, defaults to ""
     "placeholder": "Select an option", // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Optional: Array of strings, defaults to []
   }
   // Note: These properties are specific to ComboBox. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ComboBox: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect selected option for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        #if os(watchOS) || os(tvOS)
        logger.log("ComboBox is not supported on watchOS/tvOS; defaulting to empty properties", .warning)
        validatedProperties = [:]
        #else
        // Validate text (initial value)
        if properties["text"] != nil && !(properties["text"] is String) {
            logger.log("ComboBox text must be a String; ignoring", .warning)
            validatedProperties["text"] = nil
        }

        // Validate options
        if let options = validatedProperties["options"] as? [String] {
            if options.isEmpty {
                logger.log("ComboBox options is empty", .warning)
            }
        } else if validatedProperties["options"] != nil {
            logger.log("ComboBox requires 'options' as [String]; ignoring", .warning)
            validatedProperties["options"] = nil
        }
        
        // Validate placeholder
        if !(validatedProperties["placeholder"] is String?), validatedProperties["placeholder"] != nil {
            logger.log("ComboBox requires 'placeholder' as String; ignoring", .warning)
            validatedProperties["placeholder"] = nil
        }
        #endif
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if os(macOS) || os(iOS)
        let items = (properties["options"] as? [String]) ?? []
        let placeholder = properties["placeholder"] as? String ?? ""
        let initialValue = Self.initialValue(model) as? String ?? ""
        
        let binding = Binding(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        return SwiftUI.HStack {
            SwiftUI.TextField(placeholder, text: binding)
            SwiftUI.Picker("", selection: binding) {
                ForEach(items, id: \.self) { item in
                    SwiftUI.Text(item).tag(item)
                }
            }
            .pickerStyle(.menu)
        }
        #else
        logger.log("ComboBox is not supported on this platform", .warning)
        return SwiftUI.EmptyView()
        #endif
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
}
