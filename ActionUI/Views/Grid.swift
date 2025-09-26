// Sources/Views/Grid.swift
/*
 Sample JSON for Grid:
 {
   "type": "Grid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "rows": [             // Required: Array of arrays of ActionUIElementBase objects. Note: Declared as a top-level key in JSON but stored in subviews["rows"] by ViewElement.init(from:).
     [
       { "type": "Text", "properties": { "text": "Cell1" } },
       { "type": "Button", "properties": { "title": "Click" } }
     ],
     [
       { "type": "Image", "properties": { "systemName": "star" } }
     ]
   ],
   "properties": {
     "alignment": "center",        // Optional: "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"
     "horizontalSpacing": 8.0,    // Optional: Double for horizontal spacing between columns
     "verticalSpacing": 8.0       // Optional: Double for vertical spacing between rows
   }
   // Note: These properties (alignment, horizontalSpacing, verticalSpacing) are specific to Grid. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Performance: Child ActionUIView instances leverage Equatable conformance to optimize rendering, reducing re-renders for unchanged cells in large grids.
 }
*/

import SwiftUI

struct Grid: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate alignment
        if let alignment = validatedProperties["alignment"] as? String {
            if !["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
                logger.log("Grid alignment '\(alignment)' invalid; defaulting to nil", .warning)
                validatedProperties["alignment"] = nil
            }
        } else if validatedProperties["alignment"] != nil {
            logger.log("LazyHGrid alignment must be 'top', 'center', or 'bottom'; ignoring", .warning)
            validatedProperties["alignment"] = nil
        }

        // Validate spacing
        if validatedProperties["horizontalSpacing"] != nil,
           validatedProperties.cgFloat(forKey: "horizontalSpacing") == nil {
            logger.log("Grid horizontalSpacing must be a number; ignoring", .warning)
            validatedProperties["horizontalSpacing"] = nil
        }
        if validatedProperties["verticalSpacing"] != nil,
           validatedProperties.cgFloat(forKey: "verticalSpacing") == nil {
            logger.log("Grid verticalSpacing must be a number; ignoring", .warning)
            validatedProperties["verticalSpacing"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let rows = (element.subviews?["rows"] as? [[any ActionUIElementBase]]) ?? []
        let horizontalSpacing = properties.cgFloat(forKey: "horizontalSpacing")
        let verticalSpacing = properties.cgFloat(forKey: "verticalSpacing")
        let alignmentString = properties["alignment"] as? String
        let alignment: Alignment = {
            switch alignmentString {
            case "topLeading": return .topLeading
            case "top": return .top
            case "topTrailing": return .topTrailing
            case "leading": return .leading
            case "trailing": return .trailing
            case "bottomLeading": return .bottomLeading
            case "bottom": return .bottom
            case "bottomTrailing": return .bottomTrailing
            default: return .center
            }
        }()
        
        return SwiftUI.Grid(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(rows.indices, id: \.self) { rowIndex in
                SwiftUI.GridRow {
                    ForEach(rows[rowIndex], id: \.id) { child in
                        if let childModel = windowModel?.viewModels[child.id] {
                            ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                        }
                    }
                }
            }
        }
    }
}
