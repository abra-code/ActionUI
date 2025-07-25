/*
 Sample JSON for ScrollView:
 {
   "type": "ScrollView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Scrollable content" } }, // Required: Nested view or array of views
     "axis": "vertical",  // Optional: "vertical", "horizontal", or "both"; defaults to "vertical"
     "showsIndicators": true // Optional: Boolean for scroll indicators, defaults to true
   }
   // Note: These properties are specific to ScrollView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ScrollView: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if validatedProperties["content"] == nil {
            print("Warning: ScrollView requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if let axis = validatedProperties["axis"] as? String,
           !["vertical", "horizontal", "both"].contains(axis) {
            print("Warning: ScrollView axis '\(axis)' invalid; defaulting to 'vertical'")
            validatedProperties["axis"] = "vertical"
        }
        if validatedProperties["showsIndicators"] == nil {
            validatedProperties["showsIndicators"] = true
        } else if let showsIndicators = validatedProperties["showsIndicators"] as? Bool {
            validatedProperties["showsIndicators"] = showsIndicators
        } else {
            print("Warning: ScrollView showsIndicators must be a Boolean; defaulting to true")
            validatedProperties["showsIndicators"] = true
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let axis = (validatedProperties["axis"] as? String) ?? "vertical"
        let showsIndicators = validatedProperties["showsIndicators"] as? Bool ?? true
        let axes: Axis.Set = {
            switch axis {
            case "horizontal": return .horizontal
            case "both": return [.horizontal, .vertical]
            default: return .vertical
            }
        }()
        
        return AnyView(
            ScrollView(axes) {
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let showsIndicators = properties["showsIndicators"] as? Bool {
            modifiedView = AnyView(modifiedView.scrollContentBackground(.hidden).scrollIndicators(showsIndicators ? .automatic : .hidden))
        }
        return modifiedView
    }
}
