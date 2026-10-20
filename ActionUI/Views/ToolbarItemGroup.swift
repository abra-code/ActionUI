// Sources/Views/ToolbarItemGroup.swift
/*
 ToolbarItemGroup declares a group of related items at a specific placement in a view's
 toolbar or navigation bar. Like ToolbarItem, it lives inside the "toolbar" subview array
 and is never rendered standalone — the parent view's .toolbar modifier consumes it.

 The key difference from ToolbarItem: SwiftUI's ToolbarItemGroup renders multiple children
 with platform-appropriate spacing and overflow behavior, rather than leaving layout to the
 content view. Prefer ToolbarItemGroup when placing two or more related controls at the same
 placement (e.g., a pair of Edit/Add buttons in topBarTrailing).

 Sample JSON for two trailing buttons grouped at the same placement:
 {
   "type": "VStack",
   "toolbar": [
     {
       "type": "ToolbarItemGroup",
       "id": 10,                         // Optional: Non-zero positive integer
       "properties": {
         "placement": "topBarTrailing"   // Optional: placement string; defaults to "automatic"
       },
       "children": [
         { "type": "Button", "properties": { "title": "Edit",  "actionID": "toolbar.edit"  } },
         { "type": "Button", "properties": { "title": "Share", "actionID": "toolbar.share" } }
       ]
     }
   ]
 }

 For a single control, prefer ToolbarItem. For two or more controls at the same placement,
 ToolbarItemGroup lets the system manage grouping and spacing.

 Supported placement values are identical to ToolbarItem — see ToolbarItem.swift for the full list.
 Platform-unavailable placements fall back to "automatic" at runtime without warning.
 ToolbarItemGroup elements are never rendered standalone. Their content is built by ToolbarModifierView.
*/

import SwiftUI

extension ToolbarItemGroup {
    /// ToolbarItemGroup's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The same thirteen names as ToolbarItem.
        typealias Placement = ToolbarItem.Props.Placement

        /// A name that is not one of the thirteen, or no string, is automatic.
        var placement = Placement.automatic

        init(_ properties: [String: Any]) {
            placement = (properties["placement"] as? String).flatMap(Placement.init(rawValue:)) ?? .automatic
        }
    }
}

struct ToolbarItemGroup: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // ToolbarItemGroup is never rendered standalone — buildView returns EmptyView.
    // Content is rendered inside ToolbarModifierView as part of the parent view's .toolbar modifier.
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        SwiftUI.EmptyView()
    }
}
