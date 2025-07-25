/*
 Sample JSON for TabBarItem:
 {
   "type": "TabBarItem",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Home",     // Optional: String for title, defaults to "Item"
     "content": { "type": "Text", "properties": { "text": "Home" } }, // Required: Nested view
     "systemImage": "house" // Optional: String for SF Symbol, defaults to nil
   }
   // Note: These properties are specific to TabBarItem. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TabBarItem: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Item"
        }
        if validatedProperties["content"] == nil {
            print("Warning: TabBarItem requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["systemImage"] == nil {
            validatedProperties["systemImage"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let title = validatedProperties["title"] as? String ?? "Item"
        let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let systemImage = validatedProperties["systemImage"] as? String
        
        return AnyView(
            SwiftUI.TabView {
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        let title = properties["title"] as? String ?? "Item"
        if let systemImage = properties["systemImage"] as? String {
            modifiedView = AnyView(modifiedView.tabItem {
                Label(title, systemImage: systemImage)
            })
        } else {
            modifiedView = AnyView(modifiedView.tabItem {
                Text(title)
            })
        }
        return modifiedView
    }
}
