/*
 Sample JSON for TabView:
 {
   "type": "TabView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "selection": 0 // Optional: Integer for selected tab index, defaults to 0
   },
   "children": [
     {
       "type": "TabBarItem",
       "id": 2,
       "properties": {"title": "Home"},
       "content": {"type": "Text", "properties": {"text": "Home"}}
     }
   ] // Required: Array of TabBarItem views
   // Note: These properties are specific to TabView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TabView: ActionUIViewConstruction {
    // Design decision: Defines valueType as Int to reflect selected tab index for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { Int.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let selection = validatedProperties["selection"] as? Int {
            validatedProperties["selection"] = selection
        } else if validatedProperties["selection"] != nil {
            logger.log("TabView selection must be an Integer; defaulting to 0", .warning)
            validatedProperties["selection"] = 0
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElement] ?? []
        let initialSelection = (properties["selection"] as? Int) ?? 0
        if model.value == nil {
            model.value = initialSelection
        }
        let selectionBinding = Binding(
            get: { model.value as? Int ?? initialSelection },
            set: { newValue in
                model.value = newValue
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return SwiftUI.TabView(selection: selectionBinding) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }    
}
