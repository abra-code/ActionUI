// Sources/Views/HStack.swift
/*
 Sample JSON for HStack:
 {
   "type": "HStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0      // Optional: Double for spacing between elements
   },
   "children": [         // Static children — mutually exclusive with "template"
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ],
   // OR data-driven mode
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
      "type": "Button",
      "properties": { "title": "$1", "actionID": "chip.tap", "buttonStyle": "bordered" }
   }
   //
   // Column reference syntax in template string properties:
   //   $1  — column 0 (first column, 1-based)
   //   $2  — column 1 (second column, 1-based)
   //   $N  — column N-1
   //   $0  — all columns joined with ", "
   //
   // Data is set at runtime via setElementRows(windowUUID:viewID:rows:).
   //
   // Note: The spacing property is specific to HStack. Baseline View properties (padding, hidden,
   // foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct HStack: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["spacing"] != nil, (validatedProperties.cgFloat(forKey:"spacing") == nil) {
            logger.log("HStack spacing must be a number; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let spacing = properties.cgFloat(forKey: "spacing")

        // Data-driven template container mode: render one template instance per row.
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            logger.log("HStack(id:\(element.id)) template mode — template type: \(template.type), rows: \(rows.count)", .debug)
            let parentID = element.id
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.HStack(spacing: spacing) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
        }

        // Children mode
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        if let tc = model.templateContext {
            // Template child mode: this HStack is inside a template, children are blueprints
            let childViews: [AnyView] = children.map { child in
                TemplateHelper.buildTemplateView(
                    template: child, row: tc.row, rowIndex: tc.rowIndex,
                    parentID: tc.parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.HStack(spacing: spacing) {
                ForEach(childViews.indices, id: \.self) { i in childViews[i] }
            }
        } else {
            // Normal mode: children have registered ViewModels
            return SwiftUI.HStack(spacing: spacing) {
                let windowModel = ActionUIModel.shared.windowModels[windowUUID]
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        }
    }
}
