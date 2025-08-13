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
   // Note: These properties are specific to ZStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ZStack: ActionUIViewConstruction {
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if let alignment = validatedProperties["alignment"] as? String,
           ["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if validatedProperties["alignment"] != nil {
            print("Warning: ZStack alignment must be one of 'topLeading', 'top', 'topTrailing', 'leading', 'center', 'trailing', 'bottomLeading', 'bottom', 'bottomTrailing'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let alignmentString = properties["alignment"] as? String
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
        
        return SwiftUI.ZStack(alignment: alignment) {
            ForEach(element.children ?? [], id: \.id) { child in
                ActionUIView(element: child, state: state, windowUUID: windowUUID)
            }
        }
    }
}
