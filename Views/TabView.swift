/*
 Sample JSON for TabView:
 {
   "type": "TabView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "children": [
       { "type": "TabBarItem", "properties": { "title": "Home", "content": { "type": "Text", "properties": { "text": "Home" } } } }
     ], // Required: Array of TabBarItem views
     "selection": 0 // Optional: Integer for selected tab index, defaults to 0
   }
   // Note: These properties are specific to TabView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TabView: ActionUIViewConstruction {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["children"] == nil {
            print("Warning: TabView requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        if let selection = validatedProperties["selection"] as? Int {
            validatedProperties["selection"] = selection
        } else if validatedProperties["selection"] != nil {
            print("Warning: TabView selection must be an Integer; defaulting to 0")
            validatedProperties["selection"] = 0
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let children = validatedProperties["children"] as? [[String: Any]] ?? []
        
        return AnyView(
            SwiftUI.TabView {
                ForEach(children.indices, id: \.self) { index in
                    ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
                }
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let selection = properties["selection"] as? Int {
            modifiedView = AnyView(modifiedView.tabViewSelection(selection))
        }
        return modifiedView
    }
}
