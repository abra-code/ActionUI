// Helpers/SheetHelper.swift

import SwiftUI

// Helper view that applies .sheet modifier bound to the parent model's states["sheetVisible"].
// Fires sheetOnDismissActionID when the sheet is dismissed.
// Unlike popover, no tap gesture is added — sheets are opened programmatically via setElementState
// or by a Button that declares a "sheet" subview (Button.swift sets sheetVisible = true on tap).
@MainActor
struct SheetModifierView<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let sheetElement: any ActionUIElementBase
    @ObservedObject var sheetModel: ViewModel
    @ObservedObject var parentModel: ViewModel
    let windowUUID: String
    let elementID: Int
    let onDismissActionID: String?

    var body: some SwiftUI.View {
        let isPresented = Binding<Bool>(
            get: { parentModel.states["sheetVisible"] as? Bool ?? false },
            set: { parentModel.states["sheetVisible"] = $0 }
        )
        content
            .sheet(isPresented: isPresented, onDismiss: {
                if let actionID = onDismissActionID {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0)
                }
            }) {
                ActionUIView(element: sheetElement, model: sheetModel, windowUUID: windowUUID)
            }
    }
}

// Helper view that applies .fullScreenCover on iOS (unavailable on macOS; falls back to .sheet).
// Fires fullScreenCoverOnDismissActionID when dismissed.
@MainActor
struct FullScreenCoverModifierView<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let coverElement: any ActionUIElementBase
    @ObservedObject var coverModel: ViewModel
    @ObservedObject var parentModel: ViewModel
    let windowUUID: String
    let elementID: Int
    let onDismissActionID: String?

    var body: some SwiftUI.View {
        let isPresented = Binding<Bool>(
            get: { parentModel.states["fullScreenCoverVisible"] as? Bool ?? false },
            set: { parentModel.states["fullScreenCoverVisible"] = $0 }
        )
        let dismissAction = {
            if let actionID = onDismissActionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0)
            }
        }
        let coverContent = ActionUIView(element: coverElement, model: coverModel, windowUUID: windowUUID)
#if os(iOS)
        content
            .fullScreenCover(isPresented: isPresented, onDismiss: dismissAction) {
                coverContent
            }
#else
        // macOS: fullScreenCover unavailable — fall back to sheet
        content
            .sheet(isPresented: isPresented, onDismiss: dismissAction) {
                coverContent
            }
#endif
    }
}
