/*
 Sample JSON for Menu:
 {
   "type": "Menu",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Options", // Optional: String for title, defaults to empty
   },
   "label": {            // Optional: a single child view to display instead of title for the control
     "type": "Image", "properties": { "systemName": "ellipsis.circle" }
   },
   "children": [
     { "type": "Button", "properties": { "title": "Option 1" } }
   ] // Required: Array of child views (typically Buttons)
   // Note: These properties are specific to Menu. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Children can include Divider and Section to organize menu items:
   //   { "type": "Divider" }                                                          — visual separator line
   //   { "type": "Section", "properties": { "header": "Group" }, "children": [...] }  — named group with header
 }
*/

import SwiftUI

struct Menu: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title
        if properties["title"] != nil && !(properties["title"] is String) {
            logger.log("Menu title must be a String; ignoring", .warning)
            validatedProperties["title"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        if let labelContent = element.subviews?["label"] as? any ActionUIElementBase {
            return SwiftUI.Menu {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            } label: {
                if let labelModel = windowModel?.viewModels[labelContent.id] {
                    ActionUIView(element: labelContent, model: labelModel, windowUUID: windowUUID)
                }
            }
        }
        
        let title = properties["title"] as? String ?? ""
        return SwiftUI.Menu(title) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
