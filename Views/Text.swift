/*
 Sample JSON for Text:
 {
   "type": "Text",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello, World!" // Optional: String, defaults to empty string
   }
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Text: ActionUIViewConstruction {
    // Design decision: Defines valueType as Void since Text is a static display view with no interactive state
    static var valueType: Any.Type? { Void.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if validatedProperties["text"] == nil {
            validatedProperties["text"] = ""
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let text = validatedProperties["text"] as? String ?? ""
        
        return AnyView(
            SwiftUI.Text(text)
        )
    }
}
