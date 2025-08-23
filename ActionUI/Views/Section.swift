/*
 Sample JSON for Section:
 {
   "type": "Section",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "header": "Details", // Optional: String for header, defaults to nil
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } }
   ] // Required: Array of child views
   // Note: These properties are specific to Section. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Section: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        return properties                
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let children = element.children ?? []
        
        let header = properties["header"] as? String
        
        return SwiftUI.Section() {
            ForEach(children, id: \.id) { child in
                ActionUIView(element: child, state: state, windowUUID: windowUUID)
            }
        } header: {
            if let header = header {
                SwiftUI.Text(header)
            }
        }
    }
}
