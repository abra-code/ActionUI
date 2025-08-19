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
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["content"] == nil {
            logger.log("ScrollView requires 'content'; defaulting to EmptyView", .warning)
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if let axis = validatedProperties["axis"] as? String,
           !["vertical", "horizontal", "both"].contains(axis) {
            logger.log("ScrollView axis '\(axis)' invalid; defaulting to 'vertical'", .warning)
            validatedProperties["axis"] = "vertical"
        }
        if validatedProperties["showsIndicators"] == nil {
            validatedProperties["showsIndicators"] = true
        } else if let showsIndicators = validatedProperties["showsIndicators"] as? Bool {
            validatedProperties["showsIndicators"] = showsIndicators
        } else {
            logger.log("ScrollView showsIndicators must be a Boolean; defaulting to true", .warning)
            validatedProperties["showsIndicators"] = true
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let axis = (properties["axis"] as? String) ?? "vertical"
        let showsIndicators = properties["showsIndicators"] as? Bool ?? true
        let axes: Axis.Set = {
            switch axis {
            case "horizontal": return .horizontal
            case "both": return [.horizontal, .vertical]
            default: return .vertical
            }
        }()
        
        return SwiftUI.ScrollView(axes) {
            ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        if let showsIndicators = properties["showsIndicators"] as? Bool {
            return view.scrollContentBackground(.hidden).scrollIndicators(showsIndicators ? .automatic : .hidden)
        }
        return view
    }
}
