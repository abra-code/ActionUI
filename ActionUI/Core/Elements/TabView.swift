// Core/Elements/TabView.swift
/*
 Sample JSON for TabView:
 {
   "type": "TabView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "selection": 0,     // Optional: Integer for selected tab index (0-based), defaults to 0
     "style": "automatic" // Optional: "automatic" (default), "tabBarOnly", "sidebarAdaptable" (iOS 18+/macOS 15+), "page" (iOS/tvOS/watchOS/visionOS only), "verticalPage" (watchOS only), "grouped" (macOS only)
   },
   "children": [         // Required: Array of tab configurations with content
     {
       "type": "Tab",
       "properties": {          // Tab configuration (not a view type, just tab metadata)
         "title": "Home",        // Required: String for tab title
         "systemImage": "house", // Optional: String for SF Symbol name
         "assetImage": "myTab",  // Optional: String for asset image name. One of systemImage or assetImage must be provided
         "badge": 5              // Optional: Integer or String for badge display
       },
       "content": {      // Required: Single child view for tab content
         "type": "VStack",
         "properties": { "spacing": 10 },
         "children": [
           { "type": "Text", "properties": { "text": "Home Content" } }
         ]
       }
     },
     {
       "type": "Tab",
       "properties": {
         "title": "Settings",
         "systemImage": "gear",
         "badge": "!"
       },
       "content": {
         "type": "Text",
         "properties": { "text": "Settings Content" }
       }
     }
   ]
   // Note: These properties are specific to TabView. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: Each child in "children" is a dictionary with "properties" (tab configuration) and "content" (the actual ActionUIView to display). Tabs are identified by their index (0-based) in the children array.
   // Note: TabView supports "actionID" to trigger actions when selection changes via user interaction and passes selected tab index as context
   // Note: The "style" property controls the tab view style:
   //   "automatic" — default platform behavior (all platforms)
   //   "tabBarOnly" — always show tab bar (iOS 18+/macOS 15+)
   //   "sidebarAdaptable" — adaptive sidebar on iPad (iOS 18+/macOS 15+)
   //   "page" — horizontal scrolling pages (iOS/tvOS/watchOS/visionOS only, not macOS)
   //   "verticalPage" — vertical scrolling pages (watchOS only)
   //   "grouped" — grouped tab style (macOS only)
   // Platform compatibility: Uses native SwiftUI.Tab on iOS 18+/macOS 15+, falls back to .tabItem modifier on iOS 17.6/macOS 14.6 for backward compatibility.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension TabView {
    /// TabView's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// Not every style exists on every platform; the renderer applies none for a missing one.
        enum Style: String, Sendable, CaseIterable {
            case automatic, tabBarOnly, sidebarAdaptable, page, verticalPage, grouped
        }

        /// The initially selected tab, 0-based. An Int and nothing else.
        var selection = 0
        var style: Style?
        /// Fires when the user changes the selected tab.
        var actionID: String?

        init(_ properties: [String: Any]) {
            selection = properties["selection"] as? Int ?? 0
            style = (properties["style"] as? String).flatMap(Style.init(rawValue:))
            actionID = properties["actionID"] as? String
        }
    }
}

struct TabView: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]

    // Design decision: Defines valueType as Int to reflect selected tab index for type-safe state management
    static var valueType: Any.Type = Int.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Int {
            return initialValue
        }
        return Props(model.properties).selection
    }
}
