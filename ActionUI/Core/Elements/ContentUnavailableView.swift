/*
 Sample JSON for ContentUnavailableView:
 {
   "type": "ContentUnavailableView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "No Results",              // Required: String for the primary message
     "systemImage": "magnifyingglass",   // Optional: String for SF Symbol, defaults to nil (no image)
     "description": "Try a different search term." // Optional: String for secondary descriptive text, defaults to nil
   }
 }

 Search variant (shows "No results for <query>" with magnifying glass icon):
 {
   "type": "ContentUnavailableView",
   "id": 2,
   "properties": {
     "search": true,      // Optional: Boolean. When true, uses the built-in search appearance.
                           //   The search query text can be set via setElementValue to display "No results for <query>".
                           //   When search is true, title/systemImage/description are ignored.
     "query": "planets"   // Optional: String for the search query shown in the message. Can also be set at runtime via value.
   }
 }

 // Note: ContentUnavailableView is the standard SwiftUI view for displaying empty states, missing data,
 // or no-results conditions.
 // Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled)
 // and additional View protocol modifiers are inherited and applied via
 // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ContentUnavailableView {
    /// ContentUnavailableView's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = "No Content"
        var systemImage: String?
        var description: String?
        /// True for the system "no search results" variant.
        var search = false
        /// The search text of the search variant.
        var query = ""

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? "No Content"
            systemImage = properties["systemImage"] as? String
            description = properties["description"] as? String
            search = properties["search"] as? Bool ?? false
            query = properties["query"] as? String ?? ""
        }
    }
}

struct ContentUnavailableView: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let storedValue = model.value as? String {
            return storedValue
        }
        // For search variant, use query; otherwise use title
        let props = Props(model.properties)
        if props.search {
            return props.query
        }
        return props.title
    }
}
