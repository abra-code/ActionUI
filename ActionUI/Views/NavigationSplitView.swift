/*
 Sample JSON for NavigationSplitView:
 {
   "type": "NavigationSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "sidebar": { "type": "Text", "properties": { "text": "Sidebar" } }, // Required: Nested view for sidebar
     "content": { "type": "Text", "properties": { "text": "Content" } }, // Required: Nested view for content
     "detail": { "type": "Text", "properties": { "text": "Detail" } }, // Required: Nested view for detail
     "columnVisibility": "all", // Optional: "automatic", "all", "doubleColumn", "detail"; defaults to "all"
     "style": "balanced" // Optional: "automatic", "balanced", "prominentDetail"; defaults to "automatic"
   }
   // Note: These properties are specific to NavigationSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationSplitView: ActionUIViewConstruction {
    // Design decision: Defines valueType as NavigationSplitViewVisibility to reflect column visibility state
    static var valueType: Any.Type { SwiftUI.NavigationSplitViewVisibility.self }
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate sidebar, content, detail
        for key in ["sidebar", "content", "detail"] {
            if validatedProperties[key] == nil {
                print("Warning: NavigationSplitView requires '\(key)'; defaulting to EmptyView on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
                validatedProperties[key] = ["type": "EmptyView", "properties": [:]]
            } else if !(validatedProperties[key] is [String: Any]) {
                print("Warning: NavigationSplitView '\(key)' must be a dictionary; defaulting to EmptyView on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
                validatedProperties[key] = ["type": "EmptyView", "properties": [:]]
            }
        }
        
        // Validate columnVisibility
        let validVisibilities = ["automatic", "all", "doubleColumn", "detail"]
        if let visibility = validatedProperties["columnVisibility"] as? String, validVisibilities.contains(visibility) {
            validatedProperties["columnVisibility"] = visibility
        } else if validatedProperties["columnVisibility"] != nil {
            print("Warning: NavigationSplitView columnVisibility must be one of \(validVisibilities); defaulting to 'all' on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
            validatedProperties["columnVisibility"] = "all"
        } else {
            validatedProperties["columnVisibility"] = "all"
        }
        
        // Validate style
        let validStyles = ["automatic", "balanced", "prominentDetail"]
        if let style = validatedProperties["style"] as? String, validStyles.contains(style) {
            validatedProperties["style"] = style
        } else if validatedProperties["style"] != nil {
            print("Warning: NavigationSplitView style must be one of \(validStyles); defaulting to 'automatic' on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))")
            validatedProperties["style"] = "automatic"
        } else {
            validatedProperties["style"] = "automatic"
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let sidebar = properties["sidebar"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        let detail = properties["detail"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        
        // Initialize NavigationSplitView-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["columnVisibility"] == nil {
            viewSpecificState["columnVisibility"] = properties["columnVisibility"] as? String ?? "all"
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        // Bind columnVisibility
        let visibilityBinding = Binding<NavigationSplitViewVisibility>(
            get: {
                if let visibility = (state.wrappedValue[element.id] as? [String: Any])?["columnVisibility"] as? String {
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
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                let newVisibilityString: String
                switch newVisibility {
                case .automatic: newVisibilityString = "automatic"
                case .doubleColumn: newVisibilityString = "doubleColumn"
                case .detailOnly: newVisibilityString = "detail"
                case .all: newVisibilityString = "all"
                default: newVisibilityString = "all"
                }
                newState["columnVisibility"] = newVisibilityString
                newState["validatedProperties"] = properties
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        return SwiftUI.NavigationSplitView(columnVisibility: visibilityBinding) {
            ActionUIView(element: try! StaticElement(from: sidebar), state: state, windowUUID: windowUUID)
        } content: {
            ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
        } detail: {
            ActionUIView(element: try! StaticElement(from: detail), state: state, windowUUID: windowUUID)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> AnyView = { view, properties in
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
        return AnyView(modifiedView)
    }
}
