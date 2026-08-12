// Sources/Views/VStack.swift
/*
 Sample JSON for VStack:
 {
   "type": "VStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
   },
   "children": [         // Static children — mutually exclusive with "template"
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ],
   // OR data-driven mode
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
      "type": "Label",
      "properties": { "title": "$2", "systemImage": "$1" }
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
   // Note: These properties are specific to VStack. Baseline View properties (padding, hidden,
   // foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   //
   // "actionID" is the exception. A VStack carrying one becomes tappable as a WHOLE - the
   // rich-cell idiom: one tap target for an avatar + name + status line, instead of a small
   // Button wedged inside the cell. It is wired by ContainerAction.apply
   // (Helpers/ContainerActionHelper.swift), called from ActionUIRegistry.applyViewModifiers
   // AFTER the baseline modifiers, so the target covers the container's FINAL box - frame,
   // padding and background included. Inside a template row it dispatches with the owning
   // container's id as viewID and the row index as viewPartID, exactly as a Button in that
   // row does; outside one, with its own id and viewPartID 0. The innermost action wins: a
   // nested Button, a nested tappable container, or an enclosing List row's selection never
   // fire alongside it. The cell is also announced as a single button to VoiceOver. A blank
   // actionID is ignored, and a disabled container (or one inside a disabled ancestor) is
   // inert.
 }
*/

import SwiftUI

struct VStack: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if validatedProperties["spacing"] != nil, validatedProperties.cgFloat(forKey: "spacing") == nil {
            logger.log("VStack spacing must be numeric; ignoring", .warning)
            validatedProperties["spacing"] = nil
        }
        
        if let alignment = validatedProperties["alignment"] as? String {
            if !["leading", "center", "trailing"].contains(alignment) {
                logger.log("VStack alignment '\(alignment)' invalid; defaulting to nil", .warning)
                validatedProperties["alignment"] = nil
            }
        } else if validatedProperties["alignment"] != nil {
            logger.log("VStack alignment must be 'leading', 'center', or 'trailing'; ignoring", .warning)
            validatedProperties["alignment"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let spacing = properties.cgFloat(forKey: "spacing") ?? 0.0
        let alignmentString = properties["alignment"] as? String
        let alignment: HorizontalAlignment = {
            switch alignmentString {
            case "leading": return .leading
            case "trailing": return .trailing
            default: return .center
            }
        }()

        // Data-driven template container mode: render one template instance per row.
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            logger.log("VStack(id:\(element.id)) template mode — template type: \(template.type), rows: \(rows.count)", .debug)
            let parentID = element.id
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.VStack(alignment: alignment, spacing: spacing) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
        }

        // Children mode
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        if let tc = model.templateContext {
            // Template child mode: this VStack is inside a template, children are blueprints
            let childViews: [AnyView] = children.map { child in
                TemplateHelper.buildTemplateView(
                    template: child, row: tc.row, rowIndex: tc.rowIndex,
                    parentID: tc.parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.VStack(alignment: alignment, spacing: spacing) {
                ForEach(childViews.indices, id: \.self) { i in childViews[i] }
            }
        } else {
            // Normal mode: children have registered ViewModels
            return SwiftUI.VStack(alignment: alignment, spacing: spacing) {
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
