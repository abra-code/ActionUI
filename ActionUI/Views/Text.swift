/*
 Sample JSON for Text:
 {
   "type": "Text",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello, World!" // Optional: String, defaults to empty string
   }
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Text: ActionUIViewConstruction {
    // The runtime value of a Text view is its displayed string.
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        return properties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        
        let initialValue = Self.initialValue(model) as? String ?? ""
                
        return SwiftUI.Text(initialValue)
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let storedValue = model.value as? String {
            return storedValue
        }
        
        let propertiesValue = model.validatedProperties["text"] as? String ?? ""
        return propertiesValue
    }
}
