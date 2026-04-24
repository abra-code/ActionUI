/*
 Sample JSON for LabeledContent:
 {
   "type": "LabeledContent",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Username"  // Required: String for the label displayed before the content
   },
   "children": [
     { "type": "TextField", "id": 2, "properties": { "prompt": "Enter username" } }
   ]
   // Note: LabeledContent pairs a title label with one or more child views. It renders consistently
   // across all container contexts (Form, VStack, etc.), making labels visible where SwiftUI's built-in
   // view labels (e.g., TextField's title) would otherwise be hidden. Baseline View properties (padding,
   // hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
*/

import SwiftUI

struct LabeledContent: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        if properties["title"] != nil && !(properties["title"] is String) {
            logger.log("LabeledContent 'title' must be String; setting to nil", .warning)
            validatedProperties["title"] = nil
        }

        return validatedProperties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let title = properties["title"] as? String ?? ""
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

        return SwiftUI.LabeledContent(title) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
