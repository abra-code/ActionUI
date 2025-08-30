// Sources/Views/DisclosureGroup.swift
/*
 Sample JSON for DisclosureGroup:
 {
   "type": "DisclosureGroup",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Details",  // Non-optional: String for the disclosure label; set to nil if invalid
     "isExpanded": true   // Optional: Boolean for initial expanded state; set to nil if invalid
   },
   "children": [
     { "type": "Text", "properties": { "text": "Content" } }
   ]
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct DisclosureGroup: ActionUIViewConstruction {
    static var valueType: Any.Type { Bool.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate label (must be String)
        if let label = properties["label"], !(label is String) {
            logger.log("DisclosureGroup 'label' must be String; setting to nil", .warning)
            validatedProperties["label"] = nil
        }
        
        // Validate isExpanded (must be Bool)
        if let isExpanded = properties["isExpanded"], !(isExpanded is Bool) {
            logger.log("DisclosureGroup 'isExpanded' must be Bool; setting to nil", .warning)
            validatedProperties["isExpanded"] = nil
        }
        
        // Note: 'children' is not validated here as it is handled by element.children
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let label = properties["label"] as? String ?? ""
        let initialExpanded = properties["isExpanded"] as? Bool ?? false
        
        // Initialize DisclosureGroup-specific state
        model.states["isExpanded"] = initialExpanded
        
        let expandedBinding = Binding(
            get: { model.states["isExpanded"] as? Bool ?? initialExpanded },
            set: { newValue in
                model.states["isExpanded"] = newValue
                
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    Task { @MainActor in
                    	ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let children = element.subviews?["children"] as? [any ActionUIElement] ?? []
        
        return SwiftUI.DisclosureGroup(isExpanded: expandedBinding) {
            ForEach(children, id: \.id) { child in
                ActionUIView(element: child, model: model, windowUUID: windowUUID)
            }
        } label: {
            SwiftUI.Text(label)
        }
    }
}
