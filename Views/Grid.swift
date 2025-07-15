
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
     "horizontalSpacing": 8.0,    // Optional: CGFloat for horizontal spacing
     "verticalSpacing": 8.0,      // Optional: CGFloat for vertical spacing
     "padding": 10.0,             // Optional: CGFloat for padding
     "font": "body",              // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue",   // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false              // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct Grid: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["rows", "alignment", "horizontalSpacing", "verticalSpacing", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        #if os(watchOS) || os(tvOS)
        print("Warning: Grid is not supported on watchOS/tvOS; defaulting to empty properties")
        validatedProperties = [:]
        #else
        if let rows = properties["rows"] as? [[Any]], !rows.isEmpty {
            validatedProperties["rows"] = rows.map { row in
                row.compactMap { ($0 as? [String: Any]).flatMap { try? StaticElement(from: $0) } }
            }
        } else {
            print("Warning: Grid requires non-empty 'rows'; defaulting to empty")
            validatedProperties["rows"] = []
        }
        if let alignment = properties["alignment"] as? String,
           !["topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"].contains(alignment) {
            print("Warning: Grid alignment '\(alignment)' invalid; using SwiftUI default")
            validatedProperties["alignment"] = nil
        }
        #endif
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Grid; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(iOS) || os(macOS)
        registry.register("Grid") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let rows = (properties["rows"] as? [[UIElement]]) ?? []
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
            return AnyView(
                SwiftUI.Grid(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        SwiftUI.GridRow {
                            ForEach(rows[rowIndex]) { child in
                                UILibraryView(element: child, state: state, dialogGUID: dialogGUID)
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
}
