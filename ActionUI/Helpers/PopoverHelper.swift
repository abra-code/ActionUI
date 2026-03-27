// Helpers/PopoverHelper.swift

import SwiftUI

// Helper view that applies .popover modifier with a binding to the parent model's states["popoverVisible"]
// For non-Button views, adds an onTapGesture to toggle visibility. Button handles its own toggle in its action.
// Fires popoverActionID when the popover is shown.
@MainActor
struct PopoverModifierView<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let popoverElement: any ActionUIElementBase
    @ObservedObject var popoverModel: ViewModel
    @ObservedObject var parentModel: ViewModel
    let windowUUID: String
    let elementID: Int
    let arrowEdge: Edge
    let popoverActionID: String?
    let addTapGesture: Bool

    var body: some SwiftUI.View {
        let isPresented = Binding<Bool>(
            get: { parentModel.states["popoverVisible"] as? Bool ?? false },
            set: { parentModel.states["popoverVisible"] = $0 }
        )
        if addTapGesture {
            content
                .onTapGesture {
                    let willShow = !(parentModel.states["popoverVisible"] as? Bool ?? false)
                    parentModel.states["popoverVisible"] = willShow
                    if willShow, let actionID = popoverActionID {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0)
                    }
                }
                .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                    ActionUIView(element: popoverElement, model: popoverModel, windowUUID: windowUUID)
                }
        } else {
            content
                .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                    ActionUIView(element: popoverElement, model: popoverModel, windowUUID: windowUUID)
                }
        }
    }
}
