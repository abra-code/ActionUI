/*
 Sample JSON for AsyncImage:
 {
   "type": "AsyncImage",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/image.jpg", // Required: String for web or local file URL
     "placeholder": "photo",                 // Optional: String for SF Symbol or asset name, defaults to "photo"
     "resizable": true,                     // Optional: Boolean to make image resizable, defaults to true
     "scaleMode": "fit"                     // Optional: "fit" or "fill" for scaling mode, defaults to "fit"
   }
   // Note: These properties are specific to AsyncImage. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct AsyncImage: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        // Validate url
        if let url = validatedProperties["url"] as? String, URL(string: url) == nil {
            print("Warning: AsyncImage url '\(url)' is not a valid URL; defaulting to placeholder")
            validatedProperties["url"] = nil
        }
        if validatedProperties["url"] == nil {
            print("Warning: AsyncImage requires 'url'; defaulting to placeholder")
            validatedProperties["url"] = nil
        }
        
        // Validate placeholder
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = "photo" // Default to "photo" SF Symbol
        }
        
        // Validate resizable
        if validatedProperties["resizable"] == nil {
            validatedProperties["resizable"] = true // Default to true for fit-to-size behavior
        } else if let resizable = validatedProperties["resizable"] as? Bool {
            validatedProperties["resizable"] = resizable
        } else {
            print("Warning: AsyncImage resizable must be a boolean; defaulting to true")
            validatedProperties["resizable"] = true
        }
        
        // Validate scaleMode
        if let scaleMode = validatedProperties["scaleMode"] as? String, !["fit", "fill"].contains(scaleMode) {
            print("Warning: AsyncImage scaleMode '\(scaleMode)' invalid; defaulting to 'fit'")
            validatedProperties["scaleMode"] = "fit"
        }
        if validatedProperties["scaleMode"] == nil {
            validatedProperties["scaleMode"] = "fit" // Default to fit
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("AsyncImage") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            
            let urlString = properties["url"] as? String
            let placeholder = properties["placeholder"] as? String ?? "photo"
            
            guard let urlString = urlString, let url = URL(string: urlString) else {
                return AnyView(SwiftUI.Image(systemName: placeholder))
            }
            
            return AnyView(
                SwiftUI.AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                    case .failure, .empty:
                        SwiftUI.Image(systemName: placeholder)
                    }
                }
            )
        }
    }
    
    static func registerModifiers() {
        ModifierRegistry.shared.register("resizable") { view, properties in
            if let resizable = properties["resizable"] as? Bool, resizable {
                let scaleMode = (properties["scaleMode"] as? String) ?? "fit"
                return AnyView(view.resizable().scaledToFit(scaleMode == "fit" ? .fit : .fill))
            }
            return view
        }
    }
}
