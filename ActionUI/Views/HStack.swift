// Sources/Views/HStack.swift
/*
 Sample JSON for HStack:
 {
   "type": "HStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0      // Optional: Double for spacing between elements
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: The spacing property is specific to HStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct HStack: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["spacing"] != nil, (validatedProperties.cgFloat(forKey:"spacing") == nil) {
            logger.log("HStack spacing must be a number; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let spacing = properties.cgFloat(forKey: "spacing")
        
        let children = element.subviews?["children"] as? [any ActionUIElement] ?? []
        
        return SwiftUI.HStack(spacing: spacing) {
            ForEach(children, id: \.id) { child in
                ActionUIView(element: child, model: model, windowUUID: windowUUID)
            }
        }
    }
}
