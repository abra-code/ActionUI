/*
 Sample JSON for LazyHGrid (ActionUI):
 {
   "type": "LazyHGrid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "rows": [
       { "minimum": 100.0 },
       { "flexible": true }
     ], // Array of row definitions (minimum: CGFloat, flexible: Bool)
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Vertical alignment (e.g., "top", "center", "bottom")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: These properties are specific to LazyHGrid. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct LazyHGrid: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let rows = validatedProperties["rows"] as? [[String: Any]] {
            var validatedRows: [[String: Any]] = []
            for row in rows {
                var validatedRow: [String: Any] = [:]
                if let minimum = row["minimum"] as? CGFloat {
                    validatedRow["minimum"] = minimum
                }
                if let flexible = row["flexible"] as? Bool {
                    validatedRow["flexible"] = flexible
                }
                if !validatedRow.isEmpty {
                    validatedRows.append(validatedRow)
                }
            }
            if !validatedRows.isEmpty {
                validatedProperties["rows"] = validatedRows
            } else {
                print("Warning: LazyHGrid rows must contain valid minimum or flexible values; ignoring")
                validatedProperties["rows"] = nil
            }
        } else if validatedProperties["rows"] != nil {
            print("Warning: LazyHGrid rows must be an array of dictionaries; ignoring")
            validatedProperties["rows"] = nil
        }
        
        if let spacing = validatedProperties["spacing"] as? CGFloat {
            validatedProperties["spacing"] = spacing
        } else if validatedProperties["spacing"] != nil {
            print("Warning: LazyHGrid spacing must be a CGFloat; ignoring")
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String,
           ["top", "center", "bottom"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if validatedProperties["alignment"] != nil {
            print("Warning: LazyHGrid alignment must be 'top', 'center', or 'bottom'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("LazyHGrid") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            let spacing = validatedProperties["spacing"] as? CGFloat ?? 0.0
            let alignmentString = validatedProperties["alignment"] as? String
            let alignment: VerticalAlignment = {
                switch alignmentString {
                case "top": return .top
                case "bottom": return .bottom
                default: return .center
                }
            }()
            
            let rows = (validatedProperties["rows"] as? [[String: Any]])?.compactMap { row in
                if let minimum = row["minimum"] as? CGFloat {
                    return GridItem(.fixed(minimum))
                } else if let flexible = row["flexible"] as? Bool, flexible {
                    return GridItem(.flexible())
                }
                return nil
            } ?? [GridItem(.flexible())]
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.LazyHGrid(rows: rows, alignment: alignment, spacing: spacing) {
                    ForEach(children.indices, id: \.self) { index in
                        ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
}
