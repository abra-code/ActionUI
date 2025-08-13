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
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["children"] == nil {
            print("Warning: Section requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let children = properties["children"] as? [[String: Any]] ?? []
        
        let header = properties["header"] as? String
        
        return SwiftUI.Section() {
            ForEach(children.indices, id: \.self) { index in
                ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
            }
        } header: {
            if let header = header {
                SwiftUI.Text(header)
            }
        }
    }
}
