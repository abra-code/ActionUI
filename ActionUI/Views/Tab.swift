// Sources/Views/Tab.swift
/*
 Sample JSON for Tab:
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
*/

import SwiftUI

// Tab is not meant to be instantiated outside of TabView definition
// We only need the Tab as a distinct element to take adavantage of existing decoding infrastructure of children[] array in TabView
// Without it, we would need to add a lot of specialized code to load non-ActionUIElement type

struct Tab: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        return properties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, logger in
        logger.log("Tab should not be constructed as a regular view. It is only used to build a tab in a TabView.", .error)
        return SwiftUI.EmptyView()
    }
}
