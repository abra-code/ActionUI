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

 // Note: "destinationViewId" is a base View property, read by BaseModifiers.
 // NavigationLink uses it specifically to create SwiftUI.NavigationLink(title, value: destinationViewId)
 // for push-based navigation inside NavigationStack.
 // The same property is also used by sidebar List children in NavigationSplitView to select a destination view.
 // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
*/

import SwiftUI

extension NavigationLink {
    /// NavigationLink's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = "Link"
        /// Names the destination in the enclosing navigation container; an Int and nothing else.
        var destinationViewId: Int?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? "Link"
            destinationViewId = properties["destinationViewId"] as? Int
        }
    }
}

struct NavigationLink: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Int?.self
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in

        let props = Props(properties)
        let title = props.title

        // Form 1: destination view is provided inline with NavigationLink
        if let destination = element.subviews?["destination"] as? any ActionUIElementBase {
             return SwiftUI.NavigationLink(title) {
                  if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                   let childModel = windowModel.viewModels[destination.id] {
                    // A screen inside the enclosing stack like any other, so it carries that
                    // container's persistentToolbar too. Form 2's destinations are built by
                    // NavigationStack itself and handled there; this form is pushed straight
                    // from here, and without this it would be the one screen that loses them.
                    PersistentToolbar.onScreen(
                        ActionUIView(element: destination, model: childModel, windowUUID: windowUUID),
                        element: destination,
                        windowUUID: windowUUID
                    )
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
        let initialValue = Props(model.properties).destinationViewId
        return initialValue
    }
}
