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
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if let background = validatedProperties["background"] as? String {
            if let resolvedColor = ColorHelper.resolveColor(background) {
                validatedProperties["background"] = resolvedColor
            } else {
                print("Warning: Divider background '\(background)' invalid; setting to nil")
                validatedProperties["background"] = nil
            }
        }
        if let frameHeight = validatedProperties["frameHeight"] as? Double, frameHeight > 0 {
            validatedProperties["frameHeight"] = frameHeight
        } else if validatedProperties["frameHeight"] != nil {
            print("Warning: Divider frameHeight must be a positive number; defaulting to 1.0")
            validatedProperties["frameHeight"] = 1.0
        }
        if let frameWidth = validatedProperties["frameWidth"] as? Double, frameWidth > 0 {
            validatedProperties["frameWidth"] = frameWidth
        } else if validatedProperties["frameWidth"] != nil {
            print("Warning: Divider frameWidth must be a positive number; defaulting to 0.0")
            validatedProperties["frameWidth"] = 0.0
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { _, _, _, _ in
        return SwiftUI.Divider()
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        var modifiedView = view
        if let background = properties["background"] as? Color {
            modifiedView = modifiedView.background(background)
        }
        if let frameHeight = properties["frameHeight"] as? Double {
            modifiedView = modifiedView.frame(height: frameHeight)
        }
        if let frameWidth = properties["frameWidth"] as? Double, frameWidth > 0 {
            modifiedView = modifiedView.frame(width: frameWidth)
        }
        return modifiedView
    }
}
