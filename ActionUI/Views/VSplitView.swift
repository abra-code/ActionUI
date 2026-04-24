// Sources/Views/VSplitView.swift
/*
 Sample JSON for VSplitView (macOS only):
 {
   "type": "VSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   "children": [
     { "type": "TextEditor", "id": 2, "properties": { "text": "Top pane" } },
     { "type": "TextEditor", "id": 3, "properties": { "text": "Bottom pane" } }
   ]
   // Note: VSplitView arranges children vertically with a draggable divider between them.
   // Use frame properties (minHeight, idealHeight, maxHeight) on children to control pane sizing.
   // On macOS, the first child's idealHeight (from its frame properties) is used to set the
   // initial divider position, working around SwiftUI.VSplitView's default 50/50 split.
   // macOS only — on other platforms, falls back to VStack.
   // Note: These properties are specific to VSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct VSplitView: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        // VSplitView has no view-specific properties beyond baseline View properties
        return properties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

#if os(macOS)
        // Read the first child's idealHeight from its frame properties to set initial divider position
        let initialPosition: CGFloat? = {
            guard let firstChild = children.first,
                  let childModel = windowModel?.viewModels[firstChild.id] else { return nil }
            let props = ActionUIRegistry.shared.getValidatedProperties(element: firstChild, model: childModel)
            if let frame = props["frame"] as? [String: Any] {
                return frame.cgFloat(forKey: "idealHeight")
            }
            return nil
        }()

        return SwiftUI.VSplitView {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                if let childModel = windowModel?.viewModels[child.id] {
                    if index == 0, let position = initialPosition {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                            .background(SplitViewInitialPositionSetter(position: position))
                    } else {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        }
#else
        // Fallback for non-macOS platforms: use VStack
        return SwiftUI.VStack(spacing: 0) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
#endif
    }
}
