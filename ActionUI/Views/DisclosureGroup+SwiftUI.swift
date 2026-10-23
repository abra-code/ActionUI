// SwiftUI rendering of DisclosureGroup; its portable part is in Core/Elements/DisclosureGroup.swift.

import SwiftUI

extension DisclosureGroup: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title
        
        // The binding's main-actor closures capture the Sendable Props, not the non-Sendable
        // [String: Any] properties payload.
        let expandedBinding = mainActorBinding(
            get: { model.states["isExpanded"] as? Bool ?? false },
            set: { newValue in
                guard model.states["isExpanded"] as? Bool != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    DisclosureGroup.userSetExpanded(newValue, element: element, model: model, windowUUID: windowUUID, props: props)
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
