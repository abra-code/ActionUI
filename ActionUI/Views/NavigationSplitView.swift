// Sources/Views/NavigationSplitView.swift
/*
 Sample JSON for NavigationSplitView:
 {
   "type": "NavigationSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "sidebar": {          // Required: Single child view for sidebar. Note: Declared as a top-level key in JSON but stored in subviews["sidebar"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "content": {          // Required: Single child view for content. Note: Declared as a top-level key in JSON but stored in subviews["content"].
     "type": "Text", "properties": { "text": "Content" }
   },
   "detail": {           // Required: Single child view for detail. Note: Declared as a top-level key in JSON but stored in subviews["detail"].
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "columnVisibility": "all", // Optional: "automatic", "all", "doubleColumn", "detail"; defaults to "all"
     "style": "balanced" // Optional: "automatic", "balanced", "prominentDetail"; defaults to "automatic"
   }
   // Note: These properties are specific to NavigationSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationSplitView: ActionUIViewConstruction {
    // Design decision: Defines valueType as NavigationSplitViewVisibility to reflect column visibility state
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
                
        // Validate columnVisibility
        if let columnVisibility = validatedProperties["columnVisibility"] as? String,
           !["automatic", "all", "doubleColumn", "detail"].contains(columnVisibility) {
            logger.log("Invalid NavigationSplitView columnVisibility: \(columnVisibility); defaulting to 'all'", .warning)
            validatedProperties["columnVisibility"] = "all"
        }
        
        // Validate style
        if let style = validatedProperties["style"] as? String,
           !["automatic", "balanced", "prominentDetail"].contains(style) {
            logger.log("Invalid NavigationSplitView style: \(style); defaulting to 'automatic'", .warning)
            validatedProperties["style"] = "automatic"
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let detail = element.subviews?["detail"] as? any ActionUIElementBase ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        
        let visibilityBinding = Binding<NavigationSplitViewVisibility>(
            get: {
                if let visibility = model.states["columnVisibility"] as? String {
                    switch visibility {
                    case "automatic": return .automatic
                    case "doubleColumn": return .doubleColumn
                    case "detail": return .detailOnly
                    default: return .all
                    }
                }
                return .all
            },
            set: { newVisibility in
                let newVisibilityString: String
                switch newVisibility {
                case .automatic: newVisibilityString = "automatic"
                case .doubleColumn: newVisibilityString = "doubleColumn"
                case .detailOnly: newVisibilityString = "detail"
                case .all: newVisibilityString = "all"
                default: newVisibilityString = "all"
                }
                model.states["columnVisibility"] = newVisibilityString
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        return SwiftUI.NavigationSplitView(columnVisibility: visibilityBinding) {
            if let childModel = windowModel?.viewModels[sidebar.id] {
                ActionUIView(element: sidebar, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        } content: {
            if let childModel = windowModel?.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        } detail: {
            if let childModel = windowModel?.viewModels[detail.id] {
                ActionUIView(element: detail, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        if let style = properties["style"] as? String {
            switch style {
            case "balanced":
                modifiedView = modifiedView.navigationSplitViewStyle(.balanced)
            case "prominentDetail":
                modifiedView = modifiedView.navigationSplitViewStyle(.prominentDetail)
            case "automatic":
                modifiedView = modifiedView.navigationSplitViewStyle(.automatic)
            default:
                break
            }
        }
        return modifiedView
    }
}
