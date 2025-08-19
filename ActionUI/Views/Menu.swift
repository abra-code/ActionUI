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
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Menu"
        }
        if validatedProperties["children"] == nil {
            logger.log("Menu requires 'children'; defaulting to empty array", .warning)
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let children = properties["children"] as? [[String: Any]] ?? []
        
        return SwiftUI.Menu {
            ForEach(children.indices, id: \.self) { index in
                ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
            }
        } label: {
            SwiftUI.EmptyView()
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        if let label = properties["label"] as? String {
            return view.overlay(SwiftUI.Text(label), alignment: .center)
        }
        return view
    }
}
