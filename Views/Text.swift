/*
 Sample JSON for Text:
 {
   "type": "Text",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello, World!", // Optional: String, defaults to empty string
   }
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Text: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["text"] == nil {
            validatedProperties["text"] = ""
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Text") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            
            let text = properties["text"] as? String ?? ""
            let padding = properties["padding"] as? CGFloat ?? 0.0
            let font = properties["font"]
            let foregroundColor = properties["foregroundColor"]
            let hidden = properties["hidden"] as? Bool ?? false
            
            return AnyView(
                SwiftUI.Text(text)
                    .font(FontUtility.resolveFont(font))
                    .foregroundColor(ColorUtility.resolveColor(foregroundColor))
                    .padding(padding)
                    .opacity(hidden ? 0 : 1)
            )
        }
    }
}
