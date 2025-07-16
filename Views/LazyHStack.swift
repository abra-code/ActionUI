/*
 Sample JSON for LazyHStack (ActionUI):
 {
   "type": "LazyHStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Vertical alignment (e.g., "top", "center", "bottom")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: The spacing and alignment properties are specific to LazyHStack. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius) and additional View protocol modifiers are supported and applied via ModifierRegistry.shared.applyModifiers.
 }
*/

import SwiftUI

struct LazyHStack: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["spacing", "alignment"]
        var validatedProperties = properties
        
        if let spacing = properties["spacing"] as? CGFloat {
            validatedProperties["spacing"] = spacing
        } else if properties["spacing"] != nil {
            print("Warning: LazyHStack spacing must be a CGFloat; ignoring")
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = properties["alignment"] as? String,
           ["top", "center", "bottom"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if properties["alignment"] != nil {
            print("Warning: LazyHStack alignment must be 'top', 'center', or 'bottom'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for LazyHStack; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("LazyHStack") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            let spacing = validatedProperties["spacing"] as? CGFloat ?? 0.0
            let alignmentString = validatedProperties["alignment"] as? String
            let alignment: VerticalAlignment = {
                switch alignmentString {
                case "top": return .top
                case "bottom": return .bottom
                default: return .center
                }
            }()
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.LazyHStack(alignment: alignment, spacing: spacing) {
                    ForEach(children.indices, id: \.self) { index in
                        ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
}