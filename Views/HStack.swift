
/*
 Sample JSON for HStack:
 {
   "type": "HStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "alignment": "center", // Optional: "top", "center", "bottom"
     "spacing": 8.0,       // Optional: CGFloat for spacing between children
     "padding": 10.0,      // Optional: CGFloat for padding
     "font": "body",       // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false       // Optional: Boolean to hide the view
   },
   "children": [
     { "type": "Text", "properties": { "text": "Hello" } },
     { "type": "Button", "properties": { "title": "Click" } }
   ]
 }
*/

import SwiftUI

struct HStack: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["alignment", "spacing", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        if let alignment = properties["alignment"] as? String,
           !["top", "center", "bottom"].contains(alignment) {
            print("Warning: HStack alignment '\(alignment)' invalid; using SwiftUI default")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for HStack; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("HStack") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let spacing = properties["spacing"] as? CGFloat
            let alignmentString = properties["alignment"] as? String
            let alignment: VerticalAlignment = {
                switch alignmentString {
                case "top": return .top
                case "bottom": return .bottom
                default: return .center
                }
            }()
            return AnyView(
                SwiftUI.HStack(alignment: alignment, spacing: spacing) {
                    ForEach(element.children ?? []) { child in
                        UILibraryView(element: child, state: state, dialogGUID: dialogGUID)
                    }
                }
            )
        }
    }
}
