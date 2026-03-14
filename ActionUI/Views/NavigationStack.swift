// Sources/Views/NavigationStack.swift
/*
 Sample JSON for NavigationStack:
 {
   "type": "NavigationStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "destinations": [ // Optional, needed if in "content" you placed NavigationLink(s) with destinationViewId
     { "type": "Text", "id": 10, "properties": { "text": "Destination View 10" } },
     { "type": "Text", "id": 11, "properties": { "text": "Destination View 11" } }
   ]
   
   // Note: These properties are specific to NavigationStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationStack: ActionUIViewConstruction {
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase] ?? []

        return SwiftUI.NavigationStack() {
            if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
                  .navigationDestination(for: Int.self) { destinationViewId in
                    if let target = destinations.first(where: { $0.id == destinationViewId }) {
                        if let targetModel = windowModel.viewModels[target.id] {
                           ActionUIView(element: target, model: targetModel, windowUUID: windowUUID)
                        }
                        else { // fallback – must always return some View
                            SwiftUI.Text("Destination \(destinationViewId) has no model")
                                .foregroundStyle(.red)
                        }
                    } else { // fallback – must always return some View
                        SwiftUI.Text("Destination \(destinationViewId) not found")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
