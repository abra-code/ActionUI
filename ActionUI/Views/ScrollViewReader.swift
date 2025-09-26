// Sources/Views/ScrollViewReader.swift
/*
 Sample JSON for ScrollViewReader:
 {
   "type": "ScrollViewReader",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view (typically ScrollView). Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "ScrollView", "properties": { "content": { "type": "Text", "properties": { "text": "Item 1" } } }
   },
   "properties": {
     "scrollTo": 5,       // Optional: Integer ID to scroll to, defaults to nil
     "anchor": "top"      // Optional: "top", "center", "bottom"; defaults to "center"
   }
   // Note: These properties are specific to ScrollViewReader. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ScrollViewReader: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
                
        // Validate scrollTo
        if let scrollTo = validatedProperties["scrollTo"] as? Int {
            validatedProperties["scrollTo"] = scrollTo
        } else if validatedProperties["scrollTo"] != nil {
            logger.log("ScrollViewReader scrollTo must be an Int; ignoring", .warning)
            validatedProperties["scrollTo"] = nil
        }
        
        // Validate anchor
        if let anchor = validatedProperties["anchor"] as? String,
           !["top", "center", "bottom"].contains(anchor) {
            logger.log("ScrollViewReader anchor '\(anchor)' invalid; defaulting to 'center'", .warning)
            validatedProperties["anchor"] = "center"
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        
        return SwiftUI.ScrollViewReader { proxy in
            if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        if let scrollTo = properties["scrollTo"] as? Int {
            let anchor = (properties["anchor"] as? String).flatMap {
                switch $0 {
                case "top": return UnitPoint.top
                case "bottom": return UnitPoint.bottom
                default: return UnitPoint.center
                }
            } ?? .center
            modifiedView = modifiedView.onAppear {
                if let reader = modifiedView as? any ScrollViewReaderRepresentable {
                    withAnimation {
                        reader.proxy.scrollTo(scrollTo, anchor: anchor)
                    }
                }
            }
        }
        return modifiedView
    }
}

// Placeholder protocol for ScrollViewReaderRepresentable (to be refined with actual proxy access)
protocol ScrollViewReaderRepresentable: SwiftUI.View {
    var proxy: ScrollViewProxy { get }
}
