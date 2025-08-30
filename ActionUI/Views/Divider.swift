// Sources/Views/Divider.swift
/*
 Sample JSON for Divider:
 {
   "type": "Divider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "background": "#FF0000", // Optional: Color for the divider background, defaults to system gray if invalid or nil
     "frameHeight": 2.0,     // Optional: Thickness for horizontal divider, defaults to 1.0
     "frameWidth": 0.0       // Optional: Thickness for vertical divider, defaults to 0.0 (ignored unless specified)
   }
   // Note: These properties are specific to Divider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Divider: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate background
        if !(properties["background"] is String?), properties["background"] != nil {
            logger.log("Divider background must be a String; ignoring", .warning)
            validatedProperties["background"] = nil
        }
        
        // Validate frameHeight
        if let frameHeight = validatedProperties.cgFloat(forKey: "frameHeight") {
            if frameHeight <= 0 {
                logger.log("Divider frameHeight must be a positive Double; ignoring", .warning)
                validatedProperties["frameHeight"] = nil
            }
        } else if validatedProperties["frameHeight"] != nil {
            logger.log("Invalid type for frameHeight: expected Double, got \(type(of: validatedProperties["frameHeight"]!)), ignoring", .warning)
            validatedProperties["frameHeight"] = nil
        }
        
        // Validate frameWidth
        if let frameWidth = validatedProperties.cgFloat(forKey: "frameWidth") {
            if frameWidth <= 0 {
                logger.log("Divider frameWidth must be a positive Double; ignoring", .warning)
                validatedProperties["frameWidth"] = nil
            }
        } else if validatedProperties["frameWidth"] != nil {
            logger.log("Invalid type for frameWidth: expected Double, got \(type(of: validatedProperties["frameWidth"]!)), ignoring", .warning)
            validatedProperties["frameWidth"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        return SwiftUI.Divider()
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        let background = (properties["background"] as? String).flatMap { ColorHelper.resolveColor($0) } ?? .gray
        modifiedView = modifiedView.background(background)
        let frameHeight = properties.cgFloat(forKey: "frameHeight") ?? 1.0
        modifiedView = modifiedView.frame(height: frameHeight)
        let frameWidth = properties.cgFloat(forKey: "frameWidth") ?? 0.0
        if frameWidth > 0 {
            modifiedView = modifiedView.frame(width: frameWidth)
        }
        return modifiedView
    }
}
