// Sources/Views/VStack.swift
/*
 Sample JSON for VStack:
 {
   "type": "VStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: These properties are specific to VStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct VStack: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["spacing"] != nil, validatedProperties.cgFloat(forKey: "spacing") == nil {
            logger.log("VStack spacing must be numeric; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String {
            if !["leading", "center", "trailing"].contains(alignment) {
                logger.log("VStack alignment '\(alignment)' invalid; defaulting to nil", .warning)
                validatedProperties["alignment"] = nil
            }
        } else if validatedProperties["alignment"] != nil {
            logger.log("VStack alignment must be 'leading', 'center', or 'trailing'; ignoring", .warning)
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let spacing = properties.cgFloat(forKey: "spacing") ?? 0.0
        let alignmentString = properties["alignment"] as? String
        let alignment: HorizontalAlignment = {
            switch alignmentString {
            case "leading": return .leading
            case "trailing": return .trailing
            default: return .center
            }
        }()
        
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        return SwiftUI.VStack(alignment: alignment, spacing: spacing) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
