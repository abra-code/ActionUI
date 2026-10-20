// SwiftUI rendering of Button; its portable part is in Core/Elements/Button.swift.

import SwiftUI

extension Button: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Builds the Button view, relying on ActionUIRegistry.build for state initialization
    // Design decision: No value state is initialized, as Button has no stateful value (valueType is Void)
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title
        let systemImage = props.systemImage
        let assetImage  = props.assetImage
        let actionID = props.actionID
        
        var buttonRole: ButtonRole?
        switch props.role {
        case .destructive: buttonRole = .destructive
        case .cancel: buttonRole = .cancel
        case nil: break
        }
        
        // Scale
        var imgScale = SwiftUI.Image.Scale.medium
        switch props.imageScale {
        case .small:  imgScale = .small
        case .medium: imgScale = .medium
        case .large:  imgScale = .large
        case nil: break
        }
        
        @ViewBuilder
        func makeLabel() -> some SwiftUI.View {
            if let assetName = assetImage, !assetName.isEmpty {
                if title.isEmpty {
                    SwiftUI.Image(assetName)
                        .imageScale(imgScale)
                } else {
                    SwiftUI.Label(title, image: assetName)
                        .imageScale(imgScale)
                }
            } else if let imgName = systemImage, !imgName.isEmpty {
                if title.isEmpty {
                    SwiftUI.Image(systemName: imgName)
                        .imageScale(imgScale)
                } else {
                    SwiftUI.Label(title, systemImage: imgName)
                        .imageScale(imgScale)
                }
            } else {
                SwiftUI.Text(title)
            }
        }
        
        let hasPopover = element.subviews?["popover"] != nil
        let hasSheet = element.subviews?["sheet"] != nil
        let hasFullScreenCover = element.subviews?["fullScreenCover"] != nil
        let popoverActionID = props.popoverActionID
        // Template-aware action dispatch: use parentID/rowIndex when rendering inside a template
        let actionViewID = model.templateContext?.parentID ?? element.id
        let actionViewPartID = model.templateContext?.rowIndex ?? 0
        return SwiftUI.Button(
            role: buttonRole,
            action: {
                if hasPopover {
                    let willShow = !(model.states["popoverVisible"] as? Bool ?? false)
                    model.states["popoverVisible"] = willShow
                    if willShow, let popoverActionID = popoverActionID {
                        ActionUIModel.shared.actionHandler(popoverActionID, windowUUID: windowUUID, viewID: actionViewID, viewPartID: 0)
                    }
                }
                // Sheets/covers are opened (not toggled) by a Button tap — dismissed via swipe or explicit setElementState
                if hasSheet {
                    model.states["sheetVisible"] = true
                }
                if hasFullScreenCover {
                    model.states["fullScreenCoverVisible"] = true
                }
                if let actionID = actionID {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: actionViewID, viewPartID: actionViewPartID)
                }
            },
            label: {
                AnyView(makeLabel())
            }
        )
    }
}
