/*
 Sample JSON for ZStack:
 {
   "type": "ZStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "alignment": "center" // Optional: Alignment (e.g., "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Background" } },
     { "type": "Text", "properties": { "text": "Foreground" } }
   ]
   // Note: These properties are specific to ZStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ZStack: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let alignment = validatedProperties["alignment"] as? String,
           ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if validatedProperties["alignment"] != nil {
            print("Warning: ZStack alignment must be one of 'topLeading', 'top', 'topTrailing', 'leading', 'center', 'trailing', 'bottomLeading', 'bottom', 'bottomTrailing'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("ZStack") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            let alignmentString = validatedProperties["alignment"] as? String
            let alignment: Alignment = {
                switch alignmentString {
                case "topLeading": return .topLeading
                case "top": return .top
                case "topTrailing": return .topTrailing
                case "leading": return .leading
                case "trailing": return .trailing
                case "bottomLeading": return .bottomLeading
                case "bottom": return .bottom
                case "bottomTrailing": return .bottomTrailing
                default: return .center
                }
            }()
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.ZStack(alignment: alignment) {
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
