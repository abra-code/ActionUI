// SwiftUI rendering of LazyHGrid; its portable part is in Core/Elements/LazyHGrid.swift.

import SwiftUI

extension LazyHGrid: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let spacing = CGFloat(props.spacing)
        let alignment: VerticalAlignment = {
            switch props.alignment {
            case .top: return .top
            case .center: return .center
            case .bottom: return .bottom
            }
        }()

        let rows: [GridItem] = props.rows.map { row in
            switch row {
            case .fixed(let minimum): return GridItem(.fixed(CGFloat(minimum)))
            case .flexible: return GridItem(.flexible())
            }
        }

        // Template mode: render one template instance per row in states["content"];
        // each instance fills the next grid cell.
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let dataRows = (model.states["content"] as? [[String]]) ?? []
            logger.log("LazyHGrid(id:\(element.id)) template mode - template type: \(template.type), rows: \(dataRows.count)", .debug)
            let parentID = element.id
            let rowViews: [AnyView] = dataRows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: dataRows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }
            return SwiftUI.LazyHGrid(rows: rows, alignment: alignment, spacing: spacing) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
        }

        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []

        return SwiftUI.LazyHGrid(rows: rows, alignment: alignment, spacing: spacing) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
