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
     "showsIndicators": true, // Optional: Boolean for scroll indicators, defaults to true
     "onRefreshActionID": "scroll.refresh" // Optional: String. When set, enables pull-to-refresh; fires this actionID on pull. The spinner stays until the client delivers fresh data to this view or anything inside it (any setElementRows/setElementValue/setElementState call targeting this view or a descendant), or a safety timeout elapses.
   }
   // Note: These properties are specific to ScrollView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ScrollView: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

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

        // Validate onRefreshActionID (pull-to-refresh) — must be a string
        if properties["onRefreshActionID"] != nil && !(properties["onRefreshActionID"] is String) {
            logger.log("ScrollView onRefreshActionID must be a string; ignoring", .warning)
            validatedProperties["onRefreshActionID"] = nil
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
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, element, windowUUID, properties, logger in
        var modifiedView = view
        if let showsIndicators = properties["showsIndicators"] as? Bool {
            modifiedView = modifiedView.scrollIndicators(showsIndicators ? .automatic : .hidden)
        }
        if let onRefreshActionID = properties["onRefreshActionID"] as? String {
            let viewID = element.id
            modifiedView = modifiedView.refreshable {
                await ActionUIModel.shared.runRefresh(windowUUID: windowUUID, viewID: viewID, actionID: onRefreshActionID)
            }
        }
        return modifiedView
    }
}
