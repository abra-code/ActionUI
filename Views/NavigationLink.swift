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
    // Design decision: Defines valueType as Bool to reflect isActive state for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { Bool.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
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
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let destination = validatedProperties["destination"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let isActiveBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Bool ?? (validatedProperties["isActive"] as? Bool ?? false) },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.NavigationLink(
                isActive: isActiveBinding,
                destination: {
                    ActionUIView(element: try! StaticElement(from: destination), state: state, windowUUID: windowUUID)
                }
            ) {
                EmptyView()
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
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
