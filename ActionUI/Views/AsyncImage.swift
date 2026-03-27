// Sources/Views/AsyncImage.swift
/*
 Sample JSON for AsyncImage:
 {
   "type": "AsyncImage",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/image.jpg", // Required: String for web or local file URL, returns placeholder if nil or invalid
     "placeholder": "photo",                 // Optional: String for SF Symbol or asset name, defaults to "photo" in buildView
     "resizable": true,                     // Optional: Boolean to make image resizable, defaults to true in buildView
     "contentMode": "fit"                   // Optional: "fit" or "fill" for scaling mode, defaults to "fit" in buildView
   }
   // Note: These properties are specific to AsyncImage. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Note: Invalid URLs (e.g., "invalid-url") are allowed and will construct AsyncImage, which may fail to download but should not crash.
 }
*/

import SwiftUI

struct AsyncImage: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    // The runtime value of an AsyncImage is its URL string.
    // Setting the value programmatically overrides the static "url" property.
    static var valueType: Any.Type = String.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate url
        if let url = validatedProperties["url"] as? String {
            // Allow any string URL, even if invalid (e.g., "invalid-url"); AsyncImage will handle download failure
        } else if validatedProperties["url"] != nil {
            logger.log("Invalid type for AsyncImage url: expected String, got \(type(of: validatedProperties["url"]!)), ignoring", .warning)
            validatedProperties["url"] = nil
        }
        
        // Validate placeholder
        if let placeholder = validatedProperties["placeholder"], !(placeholder is String) {
            logger.log("Invalid type for AsyncImage placeholder: expected String, got \(type(of: placeholder)), ignoring", .warning)
            validatedProperties["placeholder"] = nil
        }
        
        // Validate resizable
        if let resizable = validatedProperties["resizable"], !(resizable is Bool) {
            logger.log("Invalid type for AsyncImage resizable: expected Bool, got \(type(of: resizable)), ignoring", .warning)
            validatedProperties["resizable"] = nil
        }
        
        // Validate contentMode
        if let contentMode = validatedProperties["contentMode"] as? String {
            if !["fit", "fill"].contains(contentMode) {
                logger.log("Invalid AsyncImage contentMode '\(contentMode)', ignoring", .warning)
                validatedProperties["contentMode"] = nil
            }
        } else if validatedProperties["contentMode"] != nil {
            logger.log("Invalid type for AsyncImage contentMode: expected String, got \(type(of: validatedProperties["contentMode"]!)), ignoring", .warning)
            validatedProperties["contentMode"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let urlString = Self.initialValue(model) as? String
        let placeholder = properties["placeholder"] as? String ?? "photo"
        let resizable = properties["resizable"] as? Bool ?? true
        let contentModeString = properties["contentMode"] as? String ?? "fit"

        let contentMode: ContentMode = contentModeString == "fit" ? .fit : .fill

        guard let urlString = urlString, let url = URL(string: urlString) else {
            logger.log("AsyncImage missing valid url, using placeholder '\(placeholder)'", .warning)
            return SwiftUI.Image(systemName: placeholder)
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
                SwiftUI.Image(systemName: placeholder)
            @unknown default:
                SwiftUI.Image(systemName: placeholder)
            }
        }
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        // Runtime value (set via set_string / set_value) takes precedence
        if let storedValue = model.value as? String {
            return storedValue
        }
        // Fall back to the static "url" property from JSON
        return model.validatedProperties["url"] as? String
    }
}
