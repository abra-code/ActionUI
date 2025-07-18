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
   // Note: These properties are specific to Section. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Section: StaticElement, ViewBuilder {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Section") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let header = properties["header"] as? String
            let children = properties["children"] as? [[String: Any]] ?? []
            return AnyView(
                Section(header: header.map { Text($0) } ?? nil) {
                    ForEach(children.indices, id: \.self) { index in
                        ViewBuilderRegistry.shared.buildView(from: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("header") { view, properties in
            guard let header = properties["header"] as? String else { return view }
            return AnyView(view.sectionHeader(Text(header)))
        }
    }
}
