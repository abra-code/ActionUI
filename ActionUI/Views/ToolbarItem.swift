// Sources/Views/ToolbarItem.swift
/*
 ToolbarItem declares a single item (or group of items) at a specific placement in a view's
 toolbar or navigation bar. ToolbarItem elements are declared inside the "toolbar" subview
 array on any view, not rendered standalone — the parent view's .toolbar modifier, applied
 through View.applyModifiers, consumes them.

 Sample JSON for a navigation bar button (iOS trailing position):
 {
   "type": "VStack",
   "toolbar": [
     {
       "type": "ToolbarItem",
       "id": 10,                        // Optional: Non-zero positive integer
       "properties": {
         "placement": "topBarTrailing"  // Optional: placement string; defaults to "automatic"
       },
       "content": { "type": "Button", "properties": { "title": "Done", "actionID": "toolbar.done" } }
     }
   ]
 }

 Multiple ToolbarItem entries in "toolbar" create separate items at their respective placements.
 "content" is a single view — use Button, Menu, ControlGroup, Image, or any layout container
 (HStack, ZStack, etc.) when you need to compose multiple views into one toolbar slot.

 Supported placement values:
   Cross-platform:
     "automatic"          — System-chosen default placement
     "principal"          — Center of the toolbar / navigation bar (title area)
     "confirmationAction" — Platform primary confirmation action (e.g., "Done", "Save")
     "cancellationAction" — Platform cancel action (e.g., "Cancel")
     "destructiveAction"  — Platform destructive action (e.g., "Delete")
     "primaryAction"      — macOS/iPadOS primary toolbar action (leading toolbar area)
     "secondaryAction"    — Secondary toolbar action
   iOS / visionOS only:
     "topBarLeading"      — Navigation bar leading edge
     "topBarTrailing"     — Navigation bar trailing edge
     "bottomBar"          — Bottom toolbar bar
     "keyboard"           — Above the software keyboard
   macOS only:
     "navigation"         — Leading portion of the toolbar (before back/forward navigation)
     "status"             — Bottom status bar of the macOS app window

 Note: Platform-unavailable placements fall back to "automatic" at runtime without warning.
 ToolbarItem elements are never rendered standalone. Their content is built by ToolbarModifierView.
*/

import SwiftUI

struct ToolbarItem: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        if let placement = properties["placement"] {
            if let placementStr = placement as? String {
                let validPlacements = [
                    "automatic", "principal",
                    "confirmationAction", "cancellationAction", "destructiveAction",
                    "primaryAction", "secondaryAction",
                    "topBarLeading", "topBarTrailing",
                    "bottomBar", "keyboard",
                    "navigation", "status"
                ]
                if !validPlacements.contains(placementStr) {
                    logger.log("Invalid ToolbarItem placement '\(placementStr)'; expected one of \(validPlacements). Defaulting to 'automatic'.", .warning)
                    validatedProperties["placement"] = "automatic"
                }
            } else {
                logger.log("Invalid type for ToolbarItem placement: expected String, got \(type(of: placement)). Defaulting to 'automatic'.", .warning)
                validatedProperties["placement"] = "automatic"
            }
        }

        return validatedProperties
    }

    // ToolbarItem is never rendered standalone — buildView returns EmptyView.
    // Content is rendered inside ToolbarModifierView as part of the parent view's .toolbar modifier.
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        SwiftUI.EmptyView()
    }
}
