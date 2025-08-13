/*
 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Go to Detail", // Optional: String for label, defaults to "Link"
     "destination": { "type": "Text", "properties": { "text": "Detail" } }, // Required: Nested view
     "link": "detail" // Required: String identifier for navigation
   }
   // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationLink: ActionUIViewConstruction {
    // Design decision: Defines valueType as AnyHashable to support NavigationLink(value:) for type-safe navigation
    static var valueType: Any.Type { AnyHashable.self }
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate label
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Link"
        } else if let label = validatedProperties["label"] as? String {
            validatedProperties["label"] = label
        } else {
            print("Warning: NavigationLink label must be a String; defaulting to 'Link' on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
            validatedProperties["label"] = "Link"
        }
        
        // Validate destination
        if validatedProperties["destination"] == nil {
            print("Warning: NavigationLink requires 'destination'; defaulting to EmptyView on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
            validatedProperties["destination"] = ["type": "EmptyView", "properties": [:]]
        } else if !(validatedProperties["destination"] is [String: Any]) {
            print("Warning: NavigationLink destination must be a dictionary; defaulting to EmptyView on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
            validatedProperties["destination"] = ["type": "EmptyView", "properties": [:]]
        }
        
        // Validate link (non-optional)
        if let link = validatedProperties["link"] as? String, !link.isEmpty {
            validatedProperties["link"] = link
        } else {
            print("Error: NavigationLink requires a non-empty 'link' String; please provide a valid identifier")
            fatalError("NavigationLink 'link' is missing or invalid")
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let destination = properties["destination"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let label = properties["label"] as? String ?? "Link"
        let link = properties["link"] as? String ?? "" // Validated as non-empty in validateProperties
        
        // Initialize NavigationLink-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["link"] == nil {
            viewSpecificState["link"] = link
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        return SwiftUI.NavigationLink(value: link) {
            SwiftUI.Text(label)
        }
        .navigationDestination(for: String.self) { value in
            if value == link {
                ActionUIView(element: try! StaticElement(from: destination), state: state, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
}
