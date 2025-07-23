/*
 Sample JSON for Menu:
 {
   "type": "Menu",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Options",  // Optional: String for label, defaults to "Menu"
     "children": [
       { "type": "Button", "properties": { "title": "Option 1" } }
     ] // Required: Array of child views (typically Buttons)
   }
   // Note: These properties are specific to Menu. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Menu: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Menu"
        }
        if validatedProperties["children"] == nil {
            print("Warning: Menu requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let children = validatedProperties["children"] as? [[String: Any]] ?? []
        
        return AnyView(
            SwiftUI.Menu {
                ForEach(children.indices, id: \.self) { index in
                    ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
                }
            } label: {
                EmptyView()
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.overlay(Text(label), alignment: .center))
        }
        return modifiedView
    }
}
