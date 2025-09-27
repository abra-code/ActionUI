// Sources/Views/ScrollView.swift
/*
 Sample JSON for ScrollView:
 {
   "type": "ScrollView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view or array of views. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Scrollable content" }
   },
   "properties": {
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
                
        // Validate axis
        if let axis = validatedProperties["axis"] as? String,
           !["vertical", "horizontal", "both"].contains(axis) {
            logger.log("ScrollView axis '\(axis)' invalid; defaulting to 'vertical'", .warning)
            validatedProperties["axis"] = "vertical"
        }
        
        // Validate showsIndicators
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
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let axis = (properties["axis"] as? String) ?? "vertical"
        let showsIndicators = properties["showsIndicators"] as? Bool ?? true
        let axes: Axis.Set = {
            switch axis {
            case "horizontal": return .horizontal
            case "both": return [.horizontal, .vertical]
            default: return .vertical
            }
        }()
        
        return SwiftUI.ScrollView(axes, showsIndicators: showsIndicators) {
            if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        if let showsIndicators = properties["showsIndicators"] as? Bool {
            modifiedView = modifiedView.scrollIndicators(showsIndicators ? .automatic : .hidden)
        }
        return modifiedView
    }
}
