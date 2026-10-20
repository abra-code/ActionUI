// SwiftUI rendering of DisclosureGroup; its portable part is in Core/Elements/DisclosureGroup.swift.

import SwiftUI

extension DisclosureGroup: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title
        
        // Hoisted out of the binding: its main-actor closures capture only this Sendable String?,
        // not the non-Sendable [String: Any] properties payload.
        let valueChangeActionID = props.valueChangeActionID
        let expandedBinding = mainActorBinding(
            get: { model.states["isExpanded"] as? Bool ?? false },
            set: { newValue in
                guard model.states["isExpanded"] as? Bool != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.states["isExpanded"] = newValue
                    if let valueChangeActionID {
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
