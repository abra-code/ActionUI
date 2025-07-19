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
   // Note: These properties are specific to Label. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Label: ActionUIViewElement {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        return AnyView(
            SwiftUI.Label(title: { EmptyView() }, icon: { EmptyView() })
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        let title = properties["title"] as? String ?? ""
        if let systemImage = properties["systemImage"] as? String {
            modifiedView = AnyView(modifiedView.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Label(title, systemImage: systemImage),
                alignment: .center
            ))
        } else if let imageName = properties["imageName"] as? String {
            modifiedView = AnyView(modifiedView.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Label(title, image: imageName),
                alignment: .center
            ))
        } else {
            modifiedView = AnyView(modifiedView.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Text(title),
                alignment: .center
            ))
        }
        return modifiedView
    }
}
