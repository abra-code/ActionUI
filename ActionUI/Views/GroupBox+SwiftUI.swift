// SwiftUI rendering of GroupBox; its portable part is in Core/Elements/GroupBox.swift.

import SwiftUI

extension GroupBox: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title

        // Template mode: render one template instance per row in states["content"]
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            logger.log("GroupBox(id:\(element.id)) template mode — template type: \(template.type), rows: \(rows.count)", .debug)
            let parentID = element.id
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            if let title = title {
                return SwiftUI.GroupBox(title) {
                    ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
                }
            } else {
                return SwiftUI.GroupBox {
                    ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
                }
            }
        }

        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        if let title = title {
            return SwiftUI.GroupBox(title) {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        } else {
            return SwiftUI.GroupBox {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        }
    }
}
