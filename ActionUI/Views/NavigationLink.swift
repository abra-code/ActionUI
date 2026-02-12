// Sources/Views/NavigationLink.swift
/*
 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Optional: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "title": "Go to Detail", // Optional: String for title, defaults to "Link" in buildView
     "link": "detail" // String identifier for navigation, returns EmptyView if nil or invalid. this property is gettable and settable value for this view
   }
   // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationLink: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title
        if let title = validatedProperties["title"], !(title is String) {
            logger.log("Invalid type for NavigationLink title: expected String, got \(type(of: title)), ignoring", .warning)
            validatedProperties["title"] = nil
        }
                
        // Validate link
        if let link = validatedProperties["link"] as? String, link.isEmpty {
            logger.log("Invalid NavigationLink link: empty string, ignoring", .warning)
            validatedProperties["link"] = nil
        } else if validatedProperties["link"] != nil, !(validatedProperties["link"] is String) {
            logger.log("Invalid type for NavigationLink link: expected String, got \(type(of: validatedProperties["link"]!)), ignoring", .warning)
            validatedProperties["link"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialLink = Self.initialValue(model) as? String ?? ""
        guard !initialLink.isEmpty else {
            logger.log("NavigationLink missing valid link, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let destination = element.subviews?["destination"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let title = properties["title"] as? String ?? "Link"
        
        return SwiftUI.NavigationLink(title, value: initialLink)
          .navigationDestination(for: String.self) { value in
            if value == initialLink,
               let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[destination.id] {
                ActionUIView(element: destination, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
          }
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        let initialValue = model.validatedProperties["link"] as? String ?? ""
        return initialValue
    }
}
