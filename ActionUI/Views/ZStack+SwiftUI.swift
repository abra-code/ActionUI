// SwiftUI rendering of ZStack; its portable part is in Core/Elements/ZStack.swift.

import SwiftUI

extension ZStack: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
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

        // Data-driven template container mode: render one template instance per row.
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            let parentID = element.id
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.ZStack(alignment: alignment) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
        }

        // Children mode
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        if let tc = model.templateContext {
            // Template child mode: this ZStack is inside a template, children are blueprints
            let childViews: [AnyView] = children.map { child in
                TemplateHelper.buildTemplateView(
                    template: child, row: tc.row, rowIndex: tc.rowIndex,
                    parentID: tc.parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.ZStack(alignment: alignment) {
                ForEach(childViews.indices, id: \.self) { i in childViews[i] }
            }
        } else {
            // Normal mode: children have registered ViewModels
            return SwiftUI.ZStack(alignment: alignment) {
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
