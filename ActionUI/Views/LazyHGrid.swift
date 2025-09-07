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
   // Note: These properties are specific to LazyHGrid. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct LazyHGrid: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let rows = validatedProperties["rows"] as? [[String: Any]] {
            var validatedRows: [[String: Any]] = []
            for row in rows {
                var validatedRow: [String: Any] = [:]
                if let minimum = row.cgFloat(forKey: "minimum") {
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
                logger.log("LazyHGrid rows must contain valid minimum or flexible values; ignoring", .warning)
                validatedProperties["rows"] = nil
            }
        } else if validatedProperties["rows"] != nil {
            logger.log("LazyHGrid rows must be an array of dictionaries; ignoring", .warning)
            validatedProperties["rows"] = nil
        }
        
        if validatedProperties.cgFloat(forKey: "spacing") == nil, validatedProperties["spacing"] != nil {
            logger.log("LazyHGrid spacing must be numeric; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String {
            if !["top", "center", "bottom"].contains(alignment) {
                logger.log("LazyHGrid alignment '\(alignment)' invalid; defaulting to nil", .warning)
                validatedProperties["alignment"] = nil
            }
        } else if validatedProperties["alignment"] != nil {
            logger.log("LazyHGrid alignment must be 'top', 'center', or 'bottom'; ignoring", .warning)
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let spacing = properties.cgFloat(forKey: "spacing") ?? 0.0
        let alignmentString = properties["alignment"] as? String
        let alignment: VerticalAlignment = {
            switch alignmentString {
            case "top": return .top
            case "bottom": return .bottom
            default: return .center
            }
        }()
        
        let rows = (properties["rows"] as? [[String: Any]])?.compactMap { row in
            if let minimum = row.cgFloat(forKey: "minimum") {
                return GridItem(.fixed(minimum))
            } else if let flexible = row["flexible"] as? Bool, flexible {
                return GridItem(.flexible())
            }
            return nil
        } ?? [GridItem(.flexible())]
        
        let children = element.subviews?["children"] as? [any ActionUIElement] ?? []
        
        return SwiftUI.LazyHGrid(rows: rows, alignment: alignment, spacing: spacing) {
            ForEach(children, id: \.id) { child in
                ActionUIView(element: child, model: model, windowUUID: windowUUID)
            }
        }
    }
}
