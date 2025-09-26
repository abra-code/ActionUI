// Sources/Views/Label.swift
/*
 Sample JSON for Label:
 {
   "type": "Label",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Title",    // Optional: String for title text, defaults to ""
     "systemImage": "star.fill", // Optional: String for SF Symbol, defaults to nil
     "imageName": "customIcon" // Optional: String for asset catalog image, defaults to nil
   }
   // Note: These properties are specific to Label. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Label: ActionUIViewConstruction {
    // Design decision: Defines valueType as Void since Label is a static view with no interactive state
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title
        if properties["title"] != nil && !(properties["title"] is String) {
            logger.log("Label title must be a String; ignoring", .warning)
            validatedProperties["title"] = nil
        }
        
        // Validate systemImage
        if properties["systemImage"] != nil && !(properties["systemImage"] is String) {
            logger.log("Label systemImage must be a String; ignoring", .warning)
            validatedProperties["systemImage"] = nil
        }
        
        // Validate imageName
        if properties["imageName"] != nil && !(properties["imageName"] is String) {
            logger.log("Label imageName must be a String; ignoring", .warning)
            validatedProperties["imageName"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, _ in
        
        let title = properties["title"] as? String ?? ""
        if let systemImage = properties["systemImage"] as? String {
            return SwiftUI.Label(title, systemImage: systemImage)
        } else if let imageName = properties["imageName"] as? String {
            return SwiftUI.Label(title, image: imageName)
        }
        
        return SwiftUI.Label(title, systemImage: "").labelStyle(.titleOnly)

//        return SwiftUI.Label(title: { SwiftUI.EmptyView() }, icon: { SwiftUI.EmptyView() })
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        return modifiedView
    }
}
