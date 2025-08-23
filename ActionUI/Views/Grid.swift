// Sources/Views/Grid.swift
/*
 Sample JSON for Grid (macOS, iOS, iPadOS only):
 {
   "type": "Grid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "rows": [             // Required: Array of arrays of ActionUIElement objects. Note: Declared as a top-level key in JSON but stored in properties["rows"] by StaticElement.init(from:).
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
        
        #if os(watchOS) || os(tvOS)
        logger.log("Grid is not supported on watchOS/tvOS; defaulting to empty properties", .warning)
        validatedProperties = [:]
        #else
        // Validate rows
        // Note: Expects rows in properties["rows"] as [[any ActionUIElement]], set by StaticElement.init(from:) after decoding from top-level JSON "rows" key.
        if let rows = validatedProperties["rows"] as? [[any ActionUIElement]], !rows.isEmpty {
            logger.log("Validated rows: \(rows.map { $0.map { ($0 as? StaticElement)?.type ?? "nil" } })", .debug)
        } else {
            logger.log("Grid requires non-empty 'rows' of ActionUIElement; defaulting to empty", .warning)
            validatedProperties["rows"] = []
        }
        
        // Validate alignment
        if let alignment = validatedProperties["alignment"] as? String,
           !["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            logger.log("Grid alignment '\(alignment)' invalid; defaulting to nil", .warning)
            validatedProperties["alignment"] = nil
        }
        
        // Validate spacing
        if validatedProperties["horizontalSpacing"] != nil, !(validatedProperties["horizontalSpacing"] is Double) {
            logger.log("Grid horizontalSpacing must be a number; ignoring", .warning)
            validatedProperties["horizontalSpacing"] = nil
        }
        if validatedProperties["verticalSpacing"] != nil, !(validatedProperties["verticalSpacing"] is Double) {
            logger.log("Grid verticalSpacing must be a number; ignoring", .warning)
            validatedProperties["verticalSpacing"] = nil
        }
        #endif
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        #if os(watchOS) || os(tvOS)
        return EmptyView()
        #else
        let rows = (properties["rows"] as? [[any ActionUIElement]]) ?? []
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
            ForEach(rows.indices, id: \.self) { rowIndex in
                SwiftUI.GridRow {
                    ForEach(rows[rowIndex], id: \.id) { child in
                        ActionUIView(element: child, state: state, windowUUID: windowUUID)
                    }
                }
            }
        }
        #endif
    }
}
