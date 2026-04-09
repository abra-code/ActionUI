// Common/WindowModalView.swift

import SwiftUI

// Transparent wrapper applied once at the root of each window (when isContentView == true in
// FileLoadableView / RemoteLoadableView). Attaches all window-level presentation modifiers.
//
// All modifiers must always be present in the view tree (SwiftUI static structure rule).
// Bindings return nil/false when inactive, so only the active presentation is ever shown.
//
// Sub-view instances (tabs, detail panes — isContentView == false) are NOT wrapped here.
// Wrapping every sub-view would attach redundant observers to each pane.
//
// fullScreenCover is iOS-only. On macOS it falls back to .sheet (same JSON works cross-platform).
@MainActor
struct WindowModalView: SwiftUI.View {
    @ObservedObject var windowModel: WindowModel
    let content: AnyView
    let windowUUID: String

    var body: some SwiftUI.View {
#if os(iOS)
        content
            .sheet(item: sheetBinding) { modal in modalContent(for: modal) }
            .fullScreenCover(item: fullCoverBinding) { modal in modalContent(for: modal) }
            .alert(
                windowModel.windowDialog?.title ?? "",
                isPresented: alertBinding,
                presenting: windowModel.windowDialog?.style == .alert ? windowModel.windowDialog : nil
            ) { dialog in
                dialogButtons(for: dialog)
            } message: { dialog in
                if let msg = dialog.message { SwiftUI.Text(msg) }
            }
            .confirmationDialog(
                windowModel.windowDialog?.style == .confirmationDialog ? windowModel.windowDialog?.title ?? "" : "",
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: windowModel.windowDialog?.style == .confirmationDialog ? windowModel.windowDialog : nil
            ) { dialog in
                dialogButtons(for: dialog)
            } message: { dialog in
                if let msg = dialog.message { SwiftUI.Text(msg) }
            }
#else
        // macOS: fullScreenCover unavailable — window-level fullScreenCover falls back to sheet
        content
            .sheet(item: anyModalBinding) { modal in modalContent(for: modal) }
            .alert(
                windowModel.windowDialog?.title ?? "",
                isPresented: alertBinding,
                presenting: windowModel.windowDialog?.style == .alert ? windowModel.windowDialog : nil
            ) { dialog in
                dialogButtons(for: dialog)
            } message: { dialog in
                if let msg = dialog.message { SwiftUI.Text(msg) }
            }
            .confirmationDialog(
                windowModel.windowDialog?.style == .confirmationDialog ? windowModel.windowDialog?.title ?? "" : "",
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: windowModel.windowDialog?.style == .confirmationDialog ? windowModel.windowDialog : nil
            ) { dialog in
                dialogButtons(for: dialog)
            } message: { dialog in
                if let msg = dialog.message { SwiftUI.Text(msg) }
            }
#endif
    }

    // MARK: - Modal bindings

#if os(iOS)
    private var sheetBinding: Binding<WindowModal?> {
        Binding(
            get: { windowModel.windowModal?.style == .sheet ? windowModel.windowModal : nil },
            set: { if $0 == nil { ActionUIModel.shared.dismissModal(windowUUID: windowUUID) } }
        )
    }

    private var fullCoverBinding: Binding<WindowModal?> {
        Binding(
            get: { windowModel.windowModal?.style == .fullScreenCover ? windowModel.windowModal : nil },
            set: { if $0 == nil { ActionUIModel.shared.dismissModal(windowUUID: windowUUID) } }
        )
    }
#else
    // macOS: both sheet and fullScreenCover styles use the single .sheet modifier
    private var anyModalBinding: Binding<WindowModal?> {
        Binding(
            get: { windowModel.windowModal },
            set: { if $0 == nil { ActionUIModel.shared.dismissModal(windowUUID: windowUUID) } }
        )
    }
#endif

    @ViewBuilder
    private func modalContent(for modal: WindowModal) -> some SwiftUI.View {
        if let vm = windowModel.viewModels[modal.element.id] {
            ActionUIView(element: modal.element, model: vm, windowUUID: windowUUID)
        }
    }

    // MARK: - Dialog bindings

    // isPresented is only true when the matching style is active
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { windowModel.windowDialog?.style == .alert },
            set: { if !$0 { windowModel.windowDialog = nil } }
        )
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { windowModel.windowDialog?.style == .confirmationDialog },
            set: { if !$0 { windowModel.windowDialog = nil } }
        )
    }

    // Builds SwiftUI Buttons from DialogButton descriptors.
    // SwiftUI dismisses the dialog after any button tap and calls the binding setter (which clears windowDialog).
    @ViewBuilder
    private func dialogButtons(for dialog: WindowDialog) -> some SwiftUI.View {
        ForEach(dialog.buttons.indices, id: \.self) { i in
            let btn = dialog.buttons[i]
            SwiftUI.Button(btn.title, role: btn.role) {
                if let actionID = btn.actionID {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: 0, viewPartID: 0)
                }
            }
        }
    }
}
