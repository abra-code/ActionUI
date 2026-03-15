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
   // macOS only — on other platforms, falls back to VStack.
   // Note: These properties are specific to VSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct VSplitView: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        // VSplitView has no view-specific properties beyond baseline View properties
        return properties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

#if os(macOS)
        return SwiftUI.VSplitView {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
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
