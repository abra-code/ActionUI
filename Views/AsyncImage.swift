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
   // Note: These properties are specific to AsyncImage. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct AsyncImage: ActionUIViewConstruction {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let url = validatedProperties["url"] as? String, URL(string: url) == nil {
            print("Warning: AsyncImage url '\(url)' is not a valid URL; defaulting to placeholder")
            validatedProperties["url"] = nil
        }
        if validatedProperties["url"] == nil {
            print("Warning: AsyncImage requires 'url'; defaulting to placeholder")
            validatedProperties["url"] = nil
        }
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = "photo"
        }
        if validatedProperties["resizable"] == nil {
            validatedProperties["resizable"] = true
        } else if let resizable = validatedProperties["resizable"] as? Bool {
            validatedProperties["resizable"] = resizable
        } else {
            print("Warning: AsyncImage resizable must be a boolean; defaulting to true")
            validatedProperties["resizable"] = true
        }
        if let scaleMode = validatedProperties["scaleMode"] as? String, !["fit", "fill"].contains(scaleMode) {
            print("Warning: AsyncImage scaleMode '\(scaleMode)' invalid; defaulting to 'fit'")
            validatedProperties["scaleMode"] = "fit"
        }
        if validatedProperties["scaleMode"] == nil {
            validatedProperties["scaleMode"] = "fit"
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let urlString = validatedProperties["url"] as? String
        let placeholder = validatedProperties["placeholder"] as? String ?? "photo"
        
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return AnyView(SwiftUI.Image(source: placeholder))
        }
        
        return AnyView(
            SwiftUI.AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                case .failure, .empty:
                    SwiftUI.Image(source: placeholder)
                }
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let resizable = properties["resizable"] as? Bool, resizable {
            let scaleMode = (properties["scaleMode"] as? String) ?? "fit"
            modifiedView = AnyView(modifiedView.resizable().scaledToFit(scaleMode == "fit" ? .fit : .fill))
        }
        return modifiedView
    }
}
