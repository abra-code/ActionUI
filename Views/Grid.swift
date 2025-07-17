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
     ], // Required: Array of arrays of UIElement objects
     "alignment": "center",        // Optional: "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"
     "horizontalSpacing": 8.0,    // Optional: CGFloat for horizontal spacing between columns
     "verticalSpacing": 8.0       // Optional: CGFloat for vertical spacing between rows
   }
   // Note: These properties (rows, alignment, horizontalSpacing, verticalSpacing) are specific to Grid. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Grid: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        #if os(watchOS) || os(tvOS)
        print("Warning: Grid is not supported on watchOS/tvOS; defaulting to empty properties")
        validatedProperties = [:]
        #else
        if let rows = validatedProperties["rows"] as? [[Any]], !rows.isEmpty {
            validatedProperties["rows"] = rows.map { row in
                row.compactMap { ($0 as? [String: Any]).flatMap { try? StaticElement(from: $0) } }
            }
        } else {
            print("Warning: Grid requires non-empty 'rows'; defaulting to empty")
            validatedProperties["rows"] = []
        }
        if let alignment = validatedProperties["alignment"] as? String,
           !["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            print("Warning: Grid alignment '\(alignment)' invalid; using SwiftUI default")
            validatedProperties["alignment"] = nil
        }
        if let horizontalSpacing = validatedProperties["horizontalSpacing"] as? CGFloat {
            validatedProperties["horizontalSpacing"] = horizontalSpacing
        } else if validatedProperties["horizontalSpacing"] != nil {
            print("Warning: Grid horizontalSpacing must be a CGFloat; ignoring")
            validatedProperties["horizontalSpacing"] = nil
        }
        if let verticalSpacing = validatedProperties["verticalSpacing"] as? CGFloat {
            validatedProperties["verticalSpacing"] = verticalSpacing
        } else if validatedProperties["verticalSpacing"] != nil {
            print("Warning: Grid verticalSpacing must be a CGFloat; ignoring")
            validatedProperties["verticalSpacing"] = nil
        }
        #endif
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(iOS) || os(macOS)
        registry.register("Grid") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            
            let rows = (validatedProperties["rows"] as? [[UIElement]]) ?? []
            let horizontalSpacing = validatedProperties["horizontalSpacing"] as? CGFloat
            let verticalSpacing = validatedProperties["verticalSpacing"] as? CGFloat
            let alignmentString = validatedProperties["alignment"] as? String
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
            
            return AnyView(
                SwiftUI.Grid(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        SwiftUI.GridRow {
                            ForEach(rows[rowIndex]) { child in
                                ActionUIView(element: child, state: state, windowUUID: windowUUID)
                            }
                        }
                    }
                }
            )
        }
        #else
        registry.register("Grid") { _, _, _ in
            print("Warning: Grid is not supported on this platform")
            return AnyView(EmptyView())
        }
        #endif
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers beyond base View properties
    }
}
