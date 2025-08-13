/*
 Sample JSON for Picker:
 {
   "type": "Picker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Option",    // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Required: Array of strings
     "pickerStyle": "menu"       // Optional: "menu" (iOS/macOS/visionOS), "segmented" (iOS/macOS/visionOS), "wheel" (iOS/visionOS only); defaults to "menu"
   }
   // Note: These properties are specific to Picker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Picker: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect selected option for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate options
        if let options = validatedProperties["options"] as? [String] {
            if options.isEmpty {
                print("Warning: Picker options is empty; initializing with empty array")
                validatedProperties["options"] = []
            }
        } else {
            print("Warning: Picker requires 'options' as [String]; defaulting to empty array")
            validatedProperties["options"] = []
        }
        
        // Validate pickerStyle
        #if os(macOS)
        let validStyles = ["menu", "segmented"]
        #else
        let validStyles = ["menu", "segmented", "wheel"]
        #endif
        if let style = validatedProperties["pickerStyle"] as? String, !validStyles.contains(style) {
            print("Warning: Picker style '\(style)' invalid on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString)); defaulting to 'menu'")
            validatedProperties["pickerStyle"] = "menu"
        }
        if validatedProperties["pickerStyle"] == nil {
            validatedProperties["pickerStyle"] = "menu"
        }
        
        // Validate title
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = ""
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let items = (properties["options"] as? [String]) ?? []
        let initialValue = items.first ?? ""
        
        // Initialize Picker-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = initialValue
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let selectionBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? initialValue },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let title = properties["title"] as? String ?? ""
        
        return SwiftUI.Picker(title, selection: selectionBinding) {
            ForEach(items, id: \.self) { item in
                SwiftUI.Text(item).tag(item)
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> AnyView = { view, properties in
        var modifiedView = view
        if let style = properties["pickerStyle"] as? String {
            switch style {
            case "wheel":
                #if os(macOS)
                print("Warning: wheel PickerStyle unavailable on macOS; using menu")
                modifiedView = modifiedView.pickerStyle(.menu)
                #else
                modifiedView = modifiedView.pickerStyle(.wheel)
                #endif
            case "menu":
                modifiedView = modifiedView.pickerStyle(.menu)
            case "segmented":
                modifiedView = modifiedView.pickerStyle(.segmented)
            default:
                modifiedView = modifiedView.pickerStyle(.menu)
            }
        }
        return AnyView(modifiedView)
    }
}
