// Sources/Views/NavigationLink.swift
/*
 Sample JSON for NavigationLink:

// Form 1: Inline destination view (destination provided with the link)
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Optional: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "title": "Go to Detail" // Optional: String for title, defaults to "Link" in buildView
   }
 }

// Form 2: Destination by reference (views declared in parent NavigationStack's "destinations")
 {
   "type": "NavigationLink",
   "id": 1,
   "properties": {
     "title": "Go to Detail", // Optional: String for title, defaults to "Link" in buildView
     "destinationViewId": 10  // Base View property (Int): identifies the push target in NavigationStack.
                              // Ignored when an inline "destination" view is provided.
   }
 }

 // Note: "destinationViewId" is a base View property validated by View.validateProperties.
 // NavigationLink uses it specifically to create SwiftUI.NavigationLink(title, value: destinationViewId)
 // for push-based navigation inside NavigationStack.
 // The same property is also used by sidebar List children in NavigationSplitView to select a destination view.
 // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
*/

import SwiftUI

struct NavigationLink: ActionUIViewConstruction {
    static var valueType: Any.Type { Int?.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        // Validate title
        if let title = validatedProperties["title"], !(title is String) {
            logger.log("Invalid type for NavigationLink title: expected String, got \(type(of: title)), ignoring", .warning)
            validatedProperties["title"] = nil
        }

        // Note: destinationViewId is validated by View.validateProperties (base View property)

        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in

        let title = properties["title"] as? String ?? "Link"

        // Form 1: destination view is provided inline with NavigationLink
        if let destination = element.subviews?["destination"] as? any ActionUIElementBase {
             return SwiftUI.NavigationLink(title) {
                  if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                   let childModel = windowModel.viewModels[destination.id] {
                    ActionUIView(element: destination, model: childModel, windowUUID: windowUUID)
                }
              }
        }
        // Form 2: destinationViewId is provided and the views themselves will be in parent NavigationStack or NavigationSplitView
        else if let destinationViewId = Self.initialValue(model) as? Int {
            return SwiftUI.NavigationLink(title, value: destinationViewId)
        }
        else {
            return SwiftUI.NavigationLink(title, destination: SwiftUI.EmptyView())
        }
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Int {
            return initialValue
        }
        let initialValue = model.validatedProperties["destinationViewId"] as? Int
        return initialValue
    }
}
