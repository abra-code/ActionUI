/*
 Sample JSON for Spacer:
 {
   "type": "Spacer",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "minLength": 20.0    // Optional: CGFloat for minimum length
   }
   // Note: These properties are specific to Spacer. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Spacer: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let minLength = validatedProperties.cgFloat(forKey: "minLength") {
            validatedProperties["minLength"] = minLength
        } else if validatedProperties["minLength"] != nil {
            logger.log("Spacer minLength must be a CGFloat; ignoring", .warning)
            validatedProperties["minLength"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        return SwiftUI.Spacer()
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        if let minLength = properties.cgFloat(forKey: "minLength") {
            return view.frame(minWidth: minLength)
        }
        return view
    }
}
