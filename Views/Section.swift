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

struct Section: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let children = validatedProperties["children"] as? [[String: Any]] ?? []
        
        return AnyView(
            SwiftUI.Section {
                ForEach(children.indices, id: \.self) { index in
                    ActionUIView(element: try! StaticElement(from: children[index]), state: state, windowUUID: windowUUID)
                }
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let header = properties["header"] as? String {
            modifiedView = AnyView(modifiedView.sectionHeader(Text(header)))
        }
        return modifiedView
    }
}
