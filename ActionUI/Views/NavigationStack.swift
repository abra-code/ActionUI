// Sources/Views/NavigationStack.swift
/*
 Sample JSON for NavigationStack:
 {
   "type": "NavigationStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "properties": {
     "navigationTitle": "App", // Optional: String for navigation title
     "path": ["detail"] // Optional: Array of String for navigation path
   }
   // Note: These properties are specific to NavigationStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationStack: ActionUIViewConstruction {
    // Design decision: Defines valueType as NavigationPath to reflect the navigation stack's path
    static var valueType: Any.Type { SwiftUI.NavigationPath.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
                
        // Validate path
        if let path = validatedProperties["path"] as? [String] {
            validatedProperties["path"] = path
        } else if validatedProperties["path"] != nil {
            logger.log("NavigationStack path must be an array of strings; ignoring on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString))", .warning)
            validatedProperties["path"] = []
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElement ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let initialPath = (properties["path"] as? [String]) ?? []
        
        // Initialize NavigationStack-specific state
        if model.states["path"] == nil {
            model.states["path"] = initialPath
        }
        
        // Use NavigationPath to manage navigation state
        let pathBinding = Binding<NavigationPath>(
            get: {
                if let path = model.states["path"] as? [String] {
                    var navigationPath = NavigationPath()
                    for item in path {
                        navigationPath.append(item)
                    }
                    return navigationPath
                }
                return NavigationPath()
            },
            set: { newPath in
                // Store path as an array of strings
                let newPathArray = newPath.codable.map { String(describing: $0) }
                model.states["path"] = newPathArray
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    Task { @MainActor in
                    	ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        return SwiftUI.NavigationStack(path: pathBinding) {
            ActionUIView(element: content, model: model, windowUUID: windowUUID)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        if let navigationTitle = properties["navigationTitle"] as? String {
            modifiedView = modifiedView.navigationTitle(navigationTitle)
        }
        return modifiedView
    }
}
