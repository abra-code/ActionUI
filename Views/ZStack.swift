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
   // Note: The alignment property is specific to ZStack. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius) and additional View protocol modifiers are supported and applied via ModifierRegistry.shared.applyModifiers.
 }
*/

import SwiftUI

struct ZStack: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["alignment"]
        var validatedProperties = properties
        
        if let alignment = properties["alignment"] as? String,
           ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if properties["alignment"] != nil {
            print("Warning: ZStack alignment must be one of 'topLeading', 'top', 'topTrailing', 'leading', 'center', 'trailing', 'bottomLeading', 'bottom', 'bottomTrailing'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for ZStack; ignoring")
                return false
            }
        }
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
}
