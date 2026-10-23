// Core/Elements/DisclosureGroup.swift
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
   // foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension DisclosureGroup {
    /// DisclosureGroup's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = ""
        /// Whether the group starts expanded.
        var isExpanded = false
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            isExpanded = properties["isExpanded"] as? Bool ?? false
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }
    }

    /// What expanding or collapsing the group does, on every platform: states["isExpanded"] takes
    /// the new state and valueChangeActionID runs. The state it already has does nothing.
    static func userSetExpanded(_ expanded: Bool, element: any ActionUIElementBase, model: ViewModel, windowUUID: String, props: Props) {
        guard model.states["isExpanded"] as? Bool != expanded else { return }
        model.states["isExpanded"] = expanded
        if let actionID = props.valueChangeActionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
        }
    }
}

struct DisclosureGroup: ActionUIElementSpec {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]

    static var valueType: Any.Type = Void.self

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states: [String: Any] = model.states
        
        // Only initialize if states is empty (first-time setup)
        if states.isEmpty {
            let initialExpanded = Props(model.properties).isExpanded
            states["isExpanded"] = initialExpanded
        }
        
        return states
    }
}
