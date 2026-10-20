// SwiftUI rendering of Canvas; its portable part is in Core/Elements/Canvas.swift.

import SwiftUI

extension Canvas: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let ops = props.operations
        let bg = ColorHelper.resolveColor(props.backgroundColor) ?? .clear
        let coord = props.coordinateMode.rawValue
        let actionID = props.actionID
        
        return SwiftUI.Canvas { context, size in
            if bg != .clear {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            }
            
            var mutableContext = context
            CanvasRenderer.draw(ops, into: &mutableContext, size: size, coordMode: coord, logger: logger)
        }
        .onTapGesture {
            if let id = actionID {
                ActionUIModel.shared.actionHandler(id, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }
    }
}
