/*
 Sample JSON for LazyVGrid (ActionUI):
 {
   "type": "LazyVGrid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "columns": [
       { "minimum": 100.0 },
       { "flexible": true }
     ], // Array of column definitions (minimum: CGFloat, flexible: Bool)
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: The columns, spacing, and alignment properties are specific to LazyVGrid. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius) and additional View protocol modifiers are supported and applied via ModifierRegistry.shared.applyModifiers.
 }
*/

import SwiftUI

struct LazyVGrid: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["columns", "spacing", "alignment"]
        var validatedProperties = properties
        
        if let columns = properties["columns"] as? [[String: Any]] {
            var validatedColumns: [[String: Any]] = []
            for column in columns {
                var validatedColumn: [String: Any] = [:]
                if let minimum = column["minimum"] as? CGFloat {
                    validatedColumn["minimum"] = minimum
                }
                if let flexible = column["flexible"] as? Bool {
                    validatedColumn["flexible"] = flexible
                }
                if !validatedColumn.isEmpty {
                    validatedColumns.append(validatedColumn)
                }
            }
            if !validatedColumns.isEmpty {
                validatedProperties["columns"] = validatedColumns
            } else {
                print("Warning: LazyVGrid columns must contain valid minimum or flexible values; ignoring")
                validatedProperties["columns"] = nil
            }
        } else if properties["columns"] != nil {
            print("Warning: LazyVGrid columns must be an array of dictionaries; ignoring")
            validatedProperties["columns"] = nil
        }
        
        if let spacing = properties["spacing"] as? CGFloat {
            validatedProperties["spacing"] = spacing
        } else if properties["spacing"] != nil {
            print("Warning: LazyVGrid spacing must be a CGFloat; ignoring")
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = properties["alignment"] as? String,
           ["leading", "center", "trailing"].contains(alignment) {
            validatedProperties["alignment"] = alignment
        } else if properties["alignment"] != nil {
            print("Warning: LazyVGrid alignment must be 'leading', 'center', or 'trailing'; ignoring")
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for LazyVGrid; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("LazyVGrid") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            let spacing = validatedProperties["spacing"] as? CGFloat ?? 0.0
            let alignmentString = validatedProperties["alignment"] as? String
            let alignment: HorizontalAlignment = {
                switch alignmentString {
                case "leading": return .leading
                case "trailing": return .trailing
                default: return .center
                }
            }()
            
            let columns = (validatedProperties["columns"] as? [[String: Any]])?.compactMap { column in
                if let minimum = column["minimum"] as? CGFloat {
                    return GridItem(.fixed(minimum))
                } else if let flexible = column["flexible"] as? Bool, flexible {
                    return GridItem(.flexible())
                }
                return nil
            } ?? [GridItem(.flexible())]
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.LazyVGrid(columns: columns, alignment: alignment, spacing: spacing) {
                    ForEach(children.indices, id: \.self) { index in
                        ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
}
