// Sources/Views/ShareLink.swift
/*
 Sample JSON for ShareLink:
 {
   "type": "ShareLink",
   "id": 1,
   "properties": {
     "item": "https://example.com", // Optional: URL string, returns EmptyView if nil or invalid
     "subject": "Check this out", // Optional: String for subject, ignored if nil
     "message": "Look at this link!" // Optional: String for message, ignored if nil
   }
   // Note: These properties are specific to ShareLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ShareLink: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let item = validatedProperties["item"] as? String {
            if URL(string: item) == nil {
                logger.log("Invalid ShareLink item '\(item)', ignoring", .warning)
                validatedProperties["item"] = nil
            }
        } else if validatedProperties["item"] != nil {
            logger.log("Invalid type for ShareLink item: expected String, got \(type(of: properties["item"]!)), ignoring", .warning)
            validatedProperties["item"] = nil
        }
        
        if let subject = validatedProperties["subject"], !(subject is String) {
            logger.log("Invalid type for ShareLink subject: expected String, got \(type(of: subject)), ignoring", .warning)
            validatedProperties["subject"] = nil
        }
        
        if let message = validatedProperties["message"], !(message is String) {
            logger.log("Invalid type for ShareLink message: expected String, got \(type(of: message)), ignoring", .warning)
            validatedProperties["message"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        guard let item = properties["item"] as? String, let url = URL(string: item) else {
            logger.log("ShareLink missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let subject = properties["subject"] as? String
        let message = properties["message"] as? String
        return SwiftUI.ShareLink(item: url, subject: SwiftUI.Text(subject ?? ""), message: SwiftUI.Text(message ?? ""))
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
