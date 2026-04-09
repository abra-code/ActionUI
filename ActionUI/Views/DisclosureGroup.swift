// Sources/Views/DisclosureGroup.swift
/*
 Sample JSON for DisclosureGroup:
 {
   "type": "DisclosureGroup",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Details",  // Non-optional: String for the disclosure title; set to nil if invalid
     "isExpanded": true   // Optional: Boolean for initial expanded state; set to nil if invalid
   },
   "children": [
     { "type": "Text", "properties": { "text": "Content" } }
   ],
   // OR data-driven mode
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
     "type": "Text",
     "properties": { "text": "$1" }
   }
   //
   // Column reference syntax in template string properties:
   //   $1  — column 0 (first column, 1-based)
   //   $2  — column 1 (second column, 1-based)
   //   $N  — column N-1
   //   $0  — all columns joined with ", "
   //
   // Data is set at runtime via setElementRows(windowUUID:viewID:rows:).
   // states["content"] ([[String]]) holds the current rows.
   //
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden,
   // foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }

 Observable state (via getElementState / setElementState):
   states["isExpanded"] Bool          true when the group is expanded, false when collapsed.
                                      Reflects user interaction; write to expand/collapse programmatically.
   states["content"]  [[String]]      All items in template mode; each inner array holds the item string and any optional
                                      hidden-column data. Access via getElementRows / setElementRows /
                                      appendElementRows / clearElementRows.
*/

import SwiftUI

struct DisclosureGroup: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }

    static var valueType: Any.Type = Void.self
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title (must be String)
        if let title = properties["title"], !(title is String) {
            logger.log("DisclosureGroup 'title' must be String; setting to nil", .warning)
            validatedProperties["title"] = nil
        }
        
        // Validate isExpanded (must be Bool)
        if let isExpanded = properties["isExpanded"], !(isExpanded is Bool) {
            logger.log("DisclosureGroup 'isExpanded' must be Bool; setting to nil", .warning)
            validatedProperties["isExpanded"] = nil
        }
        
        // Note: 'children' is not validated here as it is handled by element.children
        return validatedProperties
    }
    
    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states: [String: Any] = model.states
        
        // Only initialize if states is empty (first-time setup)
        if states.isEmpty {
            let initialExpanded = model.validatedProperties["isExpanded"] as? Bool ?? false
            states["isExpanded"] = initialExpanded
        }
        
        return states
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let title = properties["title"] as? String ?? ""
        
        let expandedBinding = Binding(
            get: { model.states["isExpanded"] as? Bool ?? false },
            set: { newValue in
                guard model.states["isExpanded"] as? Bool != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.states["isExpanded"] = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )

        // Template mode: render one template instance per row in states["content"]
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            logger.log("DisclosureGroup(id:\(element.id)) template mode — template type: \(template.type), rows: \(rows.count)", .debug)
            let parentID = element.id
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.DisclosureGroup(title, isExpanded: expandedBinding) {
                SwiftUI.VStack(alignment: .leading, spacing: 0) {
                    ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
                }
            }
        }

        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        return SwiftUI.DisclosureGroup(title, isExpanded: expandedBinding) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
