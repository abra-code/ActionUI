/*
 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Go to Detail", // Optional: String for label, defaults to "Link"
     "destination": { "type": "Text", "properties": { "text": "Detail" } }, // Required: Nested view
     "isActive": true // Optional: Boolean for active state, defaults to false
   }
   // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationLink: ActionUIViewConstruction {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Link"
        }
        if validatedProperties["destination"] == nil {
            print("Warning: NavigationLink requires 'destination'; defaulting to EmptyView")
            validatedProperties["destination"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["isActive"] == nil {
            validatedProperties["isActive"] = false
        } else if let isActive = validatedProperties["isActive"] as? Bool {
            validatedProperties["isActive"] = isActive
        } else {
            print("Warning: NavigationLink isActive must be a Boolean; defaulting to false")
            validatedProperties["isActive"] = false
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let destination = validatedProperties["destination"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        
        return AnyView(
            SwiftUI.NavigationLink(
                destination: ActionUIView(element: try! StaticElement(from: destination), state: state, windowUUID: windowUUID)
            ) {
                EmptyView()
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        let label = properties["label"] as? String ?? "Link"
        if let isActive = properties["isActive"] as? Bool {
            modifiedView = AnyView(modifiedView.navigationLinkIsActive(isActive, label: Text(label)))
        } else {
            modifiedView = AnyView(modifiedView.navigationLinkLabel(Text(label)))
        }
        return modifiedView
    }
}
