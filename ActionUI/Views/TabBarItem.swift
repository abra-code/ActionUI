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
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Item"
        }
        if validatedProperties["content"] == nil {
            print("Warning: TabBarItem requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        
        return SwiftUI.TabView {
            ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
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
