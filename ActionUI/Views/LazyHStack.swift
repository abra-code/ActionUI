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
   // Note: These properties are specific to LazyHStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct LazyHStack: ActionUIViewConstruction {
        
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let spacing = validatedProperties.cgFloat(forKey: "spacing") {
            validatedProperties["spacing"] = spacing
        } else if validatedProperties["spacing"] != nil {
            logger.log("LazyHStack spacing must be a CGFloat; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String,
           ["top", "center", "bottom"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if validatedProperties["alignment"] != nil {
            logger.log("LazyHStack alignment must be 'top', 'center', or 'bottom'; ignoring", .warning)
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let spacing = properties.cgFloat(forKey: "spacing") ?? 0.0
        let alignmentString = properties["alignment"] as? String
        let alignment: VerticalAlignment = {
            switch alignmentString {
            case "top": return .top
            case "bottom": return .bottom
            default: return .center
            }
        }()
        
        let children = element.subviews?["children"] as? [any ActionUIElement] ?? []
        
        return SwiftUI.LazyHStack(alignment: alignment, spacing: spacing) {
            ForEach(children, id: \.id) { child in
                ActionUIView(element: child, state: state, windowUUID: windowUUID)
            }
        }
    }
}
