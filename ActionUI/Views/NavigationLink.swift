// Sources/Views/NavigationLink.swift
/*
 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Optional: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "label": "Go to Detail", // Optional: String for label, defaults to "Link" in buildView
     "link": "detail" // Optional: String identifier for navigation, returns EmptyView if nil or invalid
   }
   // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationLink: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate label
        if let label = validatedProperties["label"], !(label is String) {
            logger.log("Invalid type for NavigationLink label: expected String, got \(type(of: label)), ignoring", .warning)
            validatedProperties["label"] = nil
        }
                
        // Validate link
        if let link = validatedProperties["link"] as? String, link.isEmpty {
            logger.log("Invalid NavigationLink link: empty string, ignoring", .warning)
            validatedProperties["link"] = nil
        } else if validatedProperties["link"] != nil, !(validatedProperties["link"] is String) {
            logger.log("Invalid type for NavigationLink link: expected String, got \(type(of: validatedProperties["link"]!)), ignoring", .warning)
            validatedProperties["link"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        guard let link = properties["link"] as? String, !link.isEmpty else {
            logger.log("NavigationLink missing valid link, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let destination = element.subviews?["destination"] as? any ActionUIElement ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let label = properties["label"] as? String ?? "Link"
        
        // Initialize NavigationLink-specific state
        if model.states["link"] == nil {
            model.states["link"] = link
        }
        
        return SwiftUI.NavigationLink(value: link) {
            SwiftUI.Text(label)
        }
        .navigationDestination(for: String.self) { value in
            if value == link {
                ActionUIView(element: destination, model: model, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
}
