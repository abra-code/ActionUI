// Sources/Views/Grid.swift
/*
 Sample JSON for Grid:
 {
   "type": "Grid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "rows": [             // Required: Array of arrays of ActionUIElementBase objects. Note: Declared as a top-level key in JSON but stored in subviews["rows"] by ActionUIElement.init(from:).
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
   // Note: These properties (alignment, horizontalSpacing, verticalSpacing) are specific to Grid. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Performance: Child ActionUIView instances leverage Equatable conformance to optimize rendering, reducing re-renders for unchanged cells in large grids.
 }
*/

import SwiftUI

extension Grid {
    /// Grid's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
        }

        /// nil for either spacing: the system's default.
        var horizontalSpacing: Double?
        var verticalSpacing: Double?
        var alignment = Alignment.center

        init(_ properties: [String: Any]) {
            horizontalSpacing = properties.double(forKey: "horizontalSpacing")
            verticalSpacing = properties.double(forKey: "verticalSpacing")
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .center
        }
    }
}

struct Grid: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["rows": .rows]

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let rows = (element.subviews?["rows"] as? [[any ActionUIElementBase]]) ?? []
        let props = Props(properties)
        let horizontalSpacing = props.horizontalSpacing.map { CGFloat($0) }
        let verticalSpacing = props.verticalSpacing.map { CGFloat($0) }
        let alignment: Alignment = {
            switch props.alignment {
            case .topLeading: return .topLeading
            case .top: return .top
            case .topTrailing: return .topTrailing
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            case .bottomLeading: return .bottomLeading
            case .bottom: return .bottom
            case .bottomTrailing: return .bottomTrailing
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
