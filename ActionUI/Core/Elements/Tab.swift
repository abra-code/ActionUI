// Core/Elements/Tab.swift
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct Tab: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
}
