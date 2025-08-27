// Sources/Views/ComboBox.swift
/*
 Sample JSON for ComboBox (macOS, iOS, iPadOS only):
 {
   "type": "ComboBox",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Select an option", // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Optional: Array of strings, defaults to []
   }
   // Note: These properties are specific to ComboBox. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
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
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        #if os(macOS) || os(iOS)
        let items = (properties["options"] as? [String]) ?? []
        let placeholder = properties["placeholder"] as? String ?? ""
        
        // Initialize ComboBox-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = ""
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let binding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
                    ["value": newValue, "validatedProperties": properties],
                    uniquingKeysWith: { _, new in new }
                )
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    ActionHelper.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, logger: logger)
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
}
