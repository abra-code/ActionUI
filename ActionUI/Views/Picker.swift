/*
 Sample JSON for Picker:
 {
   "type": "Picker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Option",    // Optional: String, no default
     "options": ["Option1", "Option2"], // Optional: Array of strings, no default
     "pickerStyle": "menu",      // Optional: "menu" (iOS/macOS/visionOS), "segmented" (iOS/macOS/visionOS), "wheel" (iOS/visionOS only); no default
     "actionID": "picker.selection", // Optional: String for action triggered on user-initiated selection change (inherited from View)
     "valueChangeActionID": "picker.valueChanged" // Optional: String for action triggered on any value change (user or programmatic, inherited from View)
   }
   // Note: actionID is triggered via onChange for user-initiated changes. valueChangeActionID is triggered for continous value changes via the binding's set closure. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 */

import SwiftUI

struct Picker: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate options
        if let options = properties["options"], !(options is [String]) {
            logger.log("Picker 'options' must be [String]; setting to nil", .warning)
            validatedProperties["options"] = nil
        }
        
        // Validate pickerStyle
        #if os(macOS)
        let validStyles = ["menu", "segmented"]
        #else
        let validStyles = ["menu", "segmented", "wheel"]
        #endif
        if let style = properties["pickerStyle"] as? String, !validStyles.contains(style) {
            logger.log("Picker style '\(style)' invalid on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString)); setting to nil", .warning)
            validatedProperties["pickerStyle"] = nil
        }
        
        // Validate title
        if let title = properties["title"], !(title is String) {
            logger.log("Picker 'title' must be String; setting to nil", .warning)
            validatedProperties["title"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let items = (properties["options"] as? [String]) ?? []
        let initialValue = items.first ?? ""
        
        // Initialize Picker-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        if newState["value"] == nil {
            newState["value"] = initialValue
            newState["validatedProperties"] = properties
            state.wrappedValue[element.id] = newState
            logger.log("Initialized state for viewID: \(element.id) with value: \(initialValue)", .debug)
        }
        
        // Create a specific binding for the value to ensure reactivity
        let valueBinding = Binding<String>(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? initialValue },
            set: { newValue in
                guard (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String != newValue else {
                    logger.log("No change in value for viewID: \(element.id), skipping update", .debug)
                    return
                }
                logger.log("Updating value for viewID: \(element.id) to \(newValue)", .debug)
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                newState["validatedProperties"] = properties
                state.wrappedValue[element.id] = newState
                
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    logger.log("Dispatching valueChangeActionID: \(valueChangeActionID) for viewID: \(element.id)", .debug)
                    Task { @MainActor in
                    	ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let title = properties["title"] as? String ?? ""
        let actionID = properties["actionID"] as? String
        
        return SwiftUI.Picker(title, selection: valueBinding) {
            ForEach(items, id: \.self) { item in
                SwiftUI.Text(item).tag(item)
            }
        }
        .onChange(of: valueBinding.wrappedValue) { _, newValue in
            if let actionID = actionID {
                logger.log("Triggering actionID: \(actionID) for viewID: \(element.id)", .debug)
                Task { @MainActor in
                    logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        if let style = properties["pickerStyle"] as? String {
            switch style {
            case "wheel":
                #if os(macOS)
                logger.log("wheel PickerStyle unavailable on macOS; ignoring", .warning)
                #else
                modifiedView = modifiedView.pickerStyle(.wheel)
                #endif
            case "menu":
                modifiedView = modifiedView.pickerStyle(.menu)
            case "segmented":
                modifiedView = modifiedView.pickerStyle(.segmented)
            default:
                break // Should not reach here due to validateProperties
            }
        }
        return modifiedView
    }
}
