/*
 Sample JSON for DisclosureGroup:
 {
   "type": "DisclosureGroup",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Details",  // Non-optional: String for the disclosure label; defaults to "" if missing
     "children": [
       { "type": "Text", "properties": { "text": "Content" } }
     ], // Required: Array of child views
     "isExpanded": true   // Optional: Boolean for initial expanded state; if absent, uses false
   }
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct DisclosureGroup: ActionUIViewConstruction {
    // Design decision: Defines valueType as Bool to reflect isExpanded state for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { Bool.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate label
        if let label = properties["label"] as? String {
            validatedProperties["label"] = label
        } else {
            validatedProperties["label"] = ""
        }
        
        // Validate children
        if let children = properties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        } else {
            print("Warning: DisclosureGroup requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        }
        
        // Validate isExpanded
        if let isExpanded = properties["isExpanded"] as? Bool {
            validatedProperties["isExpanded"] = isExpanded
        } else {
            validatedProperties["isExpanded"] = false
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let label = properties["label"] as? String ?? ""
        let initialExpanded = properties["isExpanded"] as? Bool ?? false
        
        // Initialize DisclosureGroup-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["isExpanded"] == nil {
            viewSpecificState["isExpanded"] = initialExpanded
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let expandedBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["isExpanded"] as? Bool ?? initialExpanded },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["isExpanded"] = newValue
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        return SwiftUI.DisclosureGroup(isExpanded: expandedBinding) {
            ForEach(element.children ?? [], id: \.id) { child in
                ActionUIView(element: child, state: state, windowUUID: windowUUID)
            }
        } label: {
            SwiftUI.Text(label)
        }
    }
}
