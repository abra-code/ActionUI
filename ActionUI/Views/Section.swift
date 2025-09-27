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
   // Note: These properties are specific to Section. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Section: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate header
        if properties["header"] != nil && !(properties["header"] is String) {
            logger.log("Section header must be a String; ignoring", .warning)
            validatedProperties["header"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        let header = properties["header"] as? String
        
        return SwiftUI.Section() {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        } header: {
            if let header = header {
                SwiftUI.Text(header)
            }
        }
    }
}
