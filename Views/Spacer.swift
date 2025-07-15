
/*
 Sample JSON for Spacer:
 {
   "type": "Spacer",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "minLength": 20.0,    // Optional: CGFloat for minimum length
     "padding": 10.0,      // Optional: CGFloat for padding
     "font": "body",       // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false       // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct Spacer: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["minLength", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Spacer; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Spacer") { element, _, _ in
            let properties = validateProperties(element.properties)
            let minLength = properties["minLength"] as? CGFloat
            return AnyView(SwiftUI.Spacer().frame(minWidth: minLength))
        }
    }
}
