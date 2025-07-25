/*
 Sample JSON for Form:
 {
   "type": "Form",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "children": [
       { "type": "Text", "properties": { "text": "Field 1" } }
     ] // Required: Array of child views
   }
   // Note: These properties are specific to Form. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Form: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if validatedProperties["children"] == nil {
            print("Warning: Form requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let children = validatedProperties["children"] as? [[String: Any]] ?? []
        
        return AnyView(
            SwiftUI.Form {
                ForEach(children.indices, id: \.self) { index in
                    ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
                }
            }
        )
    }
}
