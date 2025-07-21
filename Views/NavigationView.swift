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
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["content"] == nil {
            print("Warning: NavigationView requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["navigationTitle"] == nil {
            validatedProperties["navigationTitle"] = nil
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        
        return AnyView(
            SwiftUI.NavigationView {
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let navigationTitle = properties["navigationTitle"] as? String {
            modifiedView = AnyView(modifiedView.navigationTitle(navigationTitle))
        }
        return modifiedView
    }
}
