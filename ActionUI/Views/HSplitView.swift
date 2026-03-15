// Sources/Views/HSplitView.swift
/*
 Sample JSON for HSplitView (macOS only):
 {
   "type": "HSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   "children": [
     { "type": "List", "id": 2, "properties": {} },
     { "type": "TextEditor", "id": 3, "properties": { "text": "" } }
   ]
   // Note: HSplitView arranges children side by side with a draggable divider between them.
   // Use frame properties (minWidth, idealWidth, maxWidth) on children to control pane sizing.
   // macOS only — on other platforms, falls back to HStack.
   // Note: These properties are specific to HSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct HSplitView: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        // HSplitView has no view-specific properties beyond baseline View properties
        return properties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

#if os(macOS)
        return SwiftUI.HSplitView {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
#else
        // Fallback for non-macOS platforms: use HStack
        return SwiftUI.HStack(spacing: 0) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
#endif
    }
}
