/*
 Sample JSON for NavigationView:
 {
   "type": "NavigationView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Home" } }, // Required: Nested view
     "navigationTitle": "App" // Optional: String for navigation title, defaults to nil
   }
   // Note: These properties are specific to NavigationView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationView: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if validatedProperties["content"] == nil {
            print("Warning: NavigationView requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["navigationTitle"] == nil {
            validatedProperties["navigationTitle"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        
        return AnyView(
            SwiftUI.NavigationView {
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let navigationTitle = properties["navigationTitle"] as? String {
            modifiedView = AnyView(modifiedView.navigationTitle(navigationTitle))
        }
        return modifiedView
    }
}
