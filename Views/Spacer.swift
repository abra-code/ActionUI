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
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let minLength = validatedProperties["minLength"] as? CGFloat {
            validatedProperties["minLength"] = minLength
        } else if validatedProperties["minLength"] != nil {
            print("Warning: Spacer minLength must be a CGFloat; ignoring")
            validatedProperties["minLength"] = nil
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        return AnyView(
            SwiftUI.Spacer()
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let minLength = properties["minLength"] as? CGFloat {
            modifiedView = AnyView(modifiedView.frame(minWidth: minLength))
        }
        return modifiedView
    }
}
