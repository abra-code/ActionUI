/*
 Sample JSON for LazyVStack (ActionUI):
 {
   "type": "LazyVStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: These properties are specific to LazyVStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct LazyVStack: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let spacing = validatedProperties["spacing"] as? CGFloat {
            validatedProperties["spacing"] = spacing
        } else if validatedProperties["spacing"] != nil {
            print("Warning: LazyVStack spacing must be a CGFloat; ignoring")
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String,
           ["leading", "center", "trailing"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if validatedProperties["alignment"] != nil {
            print("Warning: LazyVStack alignment must be 'leading', 'center', or 'trailing'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("LazyVStack") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            let spacing = validatedProperties["spacing"] as? CGFloat ?? 0.0
            let alignmentString = validatedProperties["alignment"] as? String
            let alignment: HorizontalAlignment = {
                switch alignmentString {
                case "leading": return .leading
                case "trailing": return .trailing
                default: return .center
                }
            }()
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.LazyVStack(alignment: alignment, spacing: spacing) {
                    ForEach(children.indices, id: \.self) { index in
                        ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers() {
        // No specific modifiers beyond base View properties
    }
}
