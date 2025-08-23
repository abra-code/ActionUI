// Sources/Views/TabBarItem.swift
/*
 Sample JSON for TabBarItem:
 {
   "type": "TabBarItem",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "properties": {
     "title": "Home",     // Optional: String for title, defaults to "Item"
     "systemImage": "house" // Optional: String for SF Symbol, defaults to nil
   }
   // Note: These properties are specific to TabBarItem. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TabBarItem: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Item"
        } else if !(validatedProperties["title"] is String) {
            logger.log("TabBarItem title must be a String; defaulting to 'Item'", .warning)
            validatedProperties["title"] = "Item"
        }
        
        // Validate systemImage
        if let systemImage = validatedProperties["systemImage"], !(systemImage is String) {
            logger.log("TabBarItem systemImage must be a String; ignoring", .warning)
            validatedProperties["systemImage"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElement ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        
        return SwiftUI.TabView {
            ActionUIView(element: content, state: state, windowUUID: windowUUID)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        let title = properties["title"] as? String ?? "Item"
        if let systemImage = properties["systemImage"] as? String {
            modifiedView = modifiedView.tabItem {
                SwiftUI.Label(title, systemImage: systemImage)
            }
        } else {
            modifiedView = modifiedView.tabItem {
                SwiftUI.Text(title)
            }
        }
        return modifiedView
    }
}
