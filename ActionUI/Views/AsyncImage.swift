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
    // Design decision: Defines valueType as Void since AsyncImage is a static view with no interactive state

    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
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
        if let contentMode = validatedProperties["contentMode"] as? String, !["fit", "fill"].contains(contentMode) {
            print("Warning: AsyncImage contentMode '\(contentMode)' invalid; defaulting to 'fit'")
            validatedProperties["contentMode"] = "fit"
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let urlString = properties["url"] as? String
        let placeholder = properties["placeholder"] as? String
        
        guard let urlString = urlString, let url = URL(string: urlString) else {
            if let placeholder = placeholder {
                return SwiftUI.Image(placeholder)
            }
            else {
                return SwiftUI.Image(systemName:"photo")
            }
        }
        
        var contentMode: ContentMode = .fit
        let resizable = properties["resizable"] as? Bool ?? true
        if resizable {
            let scaleMode = (properties["contentMode"] as? String) ?? "fit"
            if scaleMode == "fit" {
                contentMode = .fit
            } else {
                contentMode = .fill
            }
        }
        
        return SwiftUI.AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                if resizable {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    image
                }
            case .failure, .empty:
                if let placeholder = placeholder {
                    SwiftUI.Image(placeholder)
                }
                else {
                    SwiftUI.Image(systemName:"photo")
                }
            @unknown default:
                SwiftUI.Image(systemName:"photo")
            }
        }
    }
}
