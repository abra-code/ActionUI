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
 // or no-results conditions. Available on macOS 14.0+, iOS 17.0+.
 // Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled)
 // and additional View protocol modifiers are inherited and applied via
 // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
*/

import SwiftUI

struct ContentUnavailableView: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        // Validate title
        if properties["title"] != nil && !(properties["title"] is String) {
            logger.log("ContentUnavailableView title must be a String; ignoring", .warning)
            validatedProperties["title"] = nil
        }

        // Validate systemImage
        if properties["systemImage"] != nil && !(properties["systemImage"] is String) {
            logger.log("ContentUnavailableView systemImage must be a String; ignoring", .warning)
            validatedProperties["systemImage"] = nil
        }

        // Validate description
        if properties["description"] != nil && !(properties["description"] is String) {
            logger.log("ContentUnavailableView description must be a String; ignoring", .warning)
            validatedProperties["description"] = nil
        }

        // Validate search
        if properties["search"] != nil && !(properties["search"] is Bool) {
            logger.log("ContentUnavailableView search must be a Boolean; ignoring", .warning)
            validatedProperties["search"] = nil
        }

        // Validate query
        if properties["query"] != nil && !(properties["query"] is String) {
            logger.log("ContentUnavailableView query must be a String; ignoring", .warning)
            validatedProperties["query"] = nil
        }

        return validatedProperties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let isSearch = properties["search"] as? Bool ?? false

        if isSearch {
            let query = model.value as? String ?? properties["query"] as? String ?? ""
            if query.isEmpty {
                return SwiftUI.ContentUnavailableView.search
            } else {
                return SwiftUI.ContentUnavailableView.search(text: query)
            }
        }

        let title = model.value as? String ?? properties["title"] as? String ?? "No Content"
        let description = properties["description"] as? String
        let systemImage = properties["systemImage"] as? String

        if let systemImage {
            if let description {
                return SwiftUI.ContentUnavailableView(title, systemImage: systemImage, description: SwiftUI.Text(description))
            } else {
                return SwiftUI.ContentUnavailableView(title, systemImage: systemImage)
            }
        } else {
            if let description {
                return SwiftUI.ContentUnavailableView {
                    SwiftUI.Label(title, systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleOnly)
                } description: {
                    SwiftUI.Text(description)
                }
            } else {
                return SwiftUI.ContentUnavailableView {
                    SwiftUI.Label(title, systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleOnly)
                }
            }
        }
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let storedValue = model.value as? String {
            return storedValue
        }
        // For search variant, use query; otherwise use title
        if model.validatedProperties["search"] as? Bool == true {
            return model.validatedProperties["query"] as? String ?? ""
        }
        return model.validatedProperties["title"] as? String ?? "No Content"
    }
}
