// SwiftUI rendering of Grid; its portable part is in Core/Elements/Grid.swift.

import SwiftUI

extension Grid: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let rows = (element.subviews?["rows"] as? [[any ActionUIElementBase]]) ?? []
        let props = Props(properties)
        let horizontalSpacing = props.horizontalSpacing.map { CGFloat($0) }
        let verticalSpacing = props.verticalSpacing.map { CGFloat($0) }
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
        
        return SwiftUI.Grid(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(rows.indices, id: \.self) { rowIndex in
                SwiftUI.GridRow {
                    ForEach(rows[rowIndex], id: \.id) { child in
                        if let childModel = windowModel?.viewModels[child.id] {
                            ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                        }
                    }
                }
            }
        }
    }
}
