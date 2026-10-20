// Core/Elements/HSplitView.swift
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
   // On macOS, the first child's idealWidth (from its frame properties) is used to set the
   // initial divider position, working around SwiftUI.HSplitView's default 50/50 split.
   // macOS only — on other platforms, falls back to HStack.
   // Note: These properties are specific to HSplitView. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct HSplitView: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
