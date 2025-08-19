/*
 Sample JSON for VStack:
 {
   "type": "VStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: These properties are specific to VStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct VStack: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let spacing = validatedProperties["spacing"] as? CGFloat {
            validatedProperties["spacing"] = spacing
        } else if validatedProperties["spacing"] != nil {
            logger.log("VStack spacing must be a CGFloat; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String,
           ["leading", "center", "trailing"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if validatedProperties["alignment"] != nil {
            logger.log("VStack alignment must be 'leading', 'center', or 'trailing'; ignoring", .warning)
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let spacing = properties["spacing"] as? CGFloat ?? 0.0
        let alignmentString = properties["alignment"] as? String
        let alignment: HorizontalAlignment = {
            switch alignmentString {
            case "leading": return .leading
            case "trailing": return .trailing
            default: return .center
            }
        }()
        
        return SwiftUI.VStack(alignment: alignment, spacing: spacing) {
            ForEach(element.children ?? [], id: \.id) { child in
                ActionUIView(element: child, state: state, windowUUID: windowUUID)
            }
        }
    }
}
