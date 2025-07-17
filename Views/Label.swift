/*
 Sample JSON for Label:
 {
   "type": "Label",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Title",    // Optional: String for title text, defaults to ""
     "systemImage": "star.fill", // Optional: String for SF Symbol, defaults to nil
     "imageName": "customIcon" // Optional: String for asset catalog image, defaults to nil
   }
   // Note: These properties are specific to Label. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Label: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = ""
        }
        if validatedProperties["systemImage"] == nil {
            validatedProperties["systemImage"] = nil
        }
        if validatedProperties["imageName"] == nil {
            validatedProperties["imageName"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Label") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let title = properties["title"] as? String ?? ""
            return AnyView(
                Label(title: { SwiftUI.Text(title) }, icon: { EmptyView() })
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("systemImage") { view, properties in
            guard let systemImage = properties["systemImage"] as? String else { return view }
            return AnyView(view.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Image(systemName: systemImage),
                alignment: .leading
            ))
        }
        registry.register("imageName") { view, properties in
            guard let imageName = properties["imageName"] as? String else { return view }
            return AnyView(view.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Image(imageName),
                alignment: .leading
            ))
        }
    }
}
