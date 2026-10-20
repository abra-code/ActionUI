// SwiftUI rendering of LazyVStack; its portable part is in Core/Elements/LazyVStack.swift.

import SwiftUI

extension LazyVStack: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let spacing = CGFloat(props.spacing)
        let alignment: HorizontalAlignment = {
            switch props.alignment {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }()

        // Template mode: render one template instance per row in states["content"]
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            logger.log("LazyVStack(id:\(element.id)) template mode — template type: \(template.type), rows: \(rows.count)", .debug)
            let parentID = element.id
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.LazyVStack(alignment: alignment, spacing: spacing) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
        }

        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        return SwiftUI.LazyVStack(alignment: alignment, spacing: spacing) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
