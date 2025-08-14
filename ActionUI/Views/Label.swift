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

struct Label: ActionUIViewConstruction {
    
    // Design decision: Defines valueType as Void since Label is a static view with no interactive state
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = ""
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        return SwiftUI.Label(title: { SwiftUI.EmptyView() }, icon: { SwiftUI.EmptyView() })
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        var modifiedView = view
        let title = properties["title"] as? String ?? ""
        if let systemImage = properties["systemImage"] as? String {
            modifiedView = modifiedView.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Label(title, systemImage: systemImage),
                alignment: .center
            )
        } else if let imageName = properties["imageName"] as? String {
            modifiedView = modifiedView.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Label(title, image: imageName),
                alignment: .center
            )
        } else {
            modifiedView = modifiedView.labelStyle(DefaultLabelStyle()).overlay(
                SwiftUI.Text(title),
                alignment: .center
            )
        }
        return modifiedView
    }
}
