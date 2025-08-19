/*
 Sample JSON for Grid (macOS, iOS, iPadOS only):
 {
   "type": "Grid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "rows": [
       [
         { "type": "Text", "properties": { "text": "Cell1" } },
         { "type": "Button", "properties": { "title": "Click" } }
       ],
       [
         { "type": "Image", "properties": { "systemName": "star" } }
       ]
     ], // Required: Array of arrays of ActionUIElement objects
     "alignment": "center",        // Optional: "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"
     "horizontalSpacing": 8.0,    // Optional: CGFloat for horizontal spacing between columns
     "verticalSpacing": 8.0       // Optional: CGFloat for vertical spacing between rows
   }
   // Note: These properties (rows, alignment, horizontalSpacing, verticalSpacing) are specific to Grid. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
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
        if let rows = validatedProperties["rows"] as? [[Any]], !rows.isEmpty {
            validatedProperties["rows"] = rows.map { row in
                row.compactMap { ($0 as? [String: Any]).flatMap { try? StaticElement(from: $0) } }
            }
        } else {
            logger.log("Grid requires non-empty 'rows'; defaulting to empty", .warning)
            validatedProperties["rows"] = []
        }
        if let alignment = validatedProperties["alignment"] as? String,
           !["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            logger.log("Grid alignment '\(alignment)' invalid; using SwiftUI default", .warning)
            validatedProperties["alignment"] = nil
        }
        if let horizontalSpacing = validatedProperties["horizontalSpacing"] as? CGFloat {
            validatedProperties["horizontalSpacing"] = horizontalSpacing
        } else if validatedProperties["horizontalSpacing"] != nil {
            logger.log("Grid horizontalSpacing must be a CGFloat; ignoring", .warning)
            validatedProperties["horizontalSpacing"] = nil
        }
        if let verticalSpacing = validatedProperties["verticalSpacing"] as? CGFloat {
            validatedProperties["verticalSpacing"] = verticalSpacing
        } else if validatedProperties["verticalSpacing"] != nil {
            logger.log("Grid verticalSpacing must be a CGFloat; ignoring", .warning)
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
        let horizontalSpacing = properties["horizontalSpacing"] as? CGFloat
        let verticalSpacing = properties["verticalSpacing"] as? CGFloat
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
