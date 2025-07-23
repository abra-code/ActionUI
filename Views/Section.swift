/*
 Sample JSON for Section:
 {
   "type": "Section",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "header": "Details", // Optional: String for header, defaults to nil
     "children": [
       { "type": "Text", "properties": { "text": "Item 1" } }
     ] // Required: Array of child views
   }
   // Note: These properties are specific to Section. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Section: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["header"] == nil {
            validatedProperties["header"] = nil
        }
        if validatedProperties["children"] == nil {
            print("Warning: Section requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let children = validatedProperties["children"] as? [[String: Any]] ?? []
        
        return AnyView(
            SwiftUI.Section {
                ForEach(children.indices, id: \.self) { index in
                    ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
                }
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let header = properties["header"] as? String {
            modifiedView = AnyView(modifiedView.sectionHeader(Text(header)))
        }
        return modifiedView
    }
}
