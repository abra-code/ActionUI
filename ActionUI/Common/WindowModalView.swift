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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Window content plus the top-pinned toast overlay. Top placement follows the Apple
    // transient-banner idiom (banners slide from the top on iOS/macOS), not the Material snackbar's
    // bottom placement. The conditional insertion lives here (not inside ToastOverlayView) so SwiftUI
    // runs the transition; reduce-motion swaps the slide for a plain fade. Keyed on the toast id so a
    // replacing toast re-runs the transition.
    //
    // The fill frame is what makes "top" mean the top of the window rather than the top of the
    // content: an overlay is laid out within its host's bounds, and a root element that sizes to its
    // intrinsic content (e.g. a centered VStack) would otherwise pin the banner to the middle of the
    // window. Expanding to fill anchors the overlay's top edge to the window's safe area on iOS /
    // the content area below the title bar on macOS. The default .center alignment of the frame
    // leaves the wrapped content visually where SwiftUI already placed it (root content is centered),
    // so this does not change how existing windows lay out their content.
    private var decoratedContent: some SwiftUI.View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let toast = windowModel.windowToast {
                    ToastOverlayView(toast: toast, windowUUID: windowUUID)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: windowModel.windowToast?.id)
    }

    var body: some SwiftUI.View {
#if os(iOS)
        decoratedContent
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
        decoratedContent
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
            set: { if $0 == nil { DispatchQueue.main.async { ActionUIModel.shared.dismissModal(windowUUID: windowUUID) } } }
        )
    }

    private var fullCoverBinding: Binding<WindowModal?> {
        Binding(
            get: { windowModel.windowModal?.style == .fullScreenCover ? windowModel.windowModal : nil },
            set: { if $0 == nil { DispatchQueue.main.async { ActionUIModel.shared.dismissModal(windowUUID: windowUUID) } } }
        )
    }
#else
    // macOS: both sheet and fullScreenCover styles use the single .sheet modifier
    private var anyModalBinding: Binding<WindowModal?> {
        Binding(
            get: { windowModel.windowModal },
            set: { if $0 == nil { DispatchQueue.main.async { ActionUIModel.shared.dismissModal(windowUUID: windowUUID) } } }
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
            set: { if !$0 { DispatchQueue.main.async { ActionUIModel.shared.dismissDialog(windowUUID: windowUUID) } } }
        )
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { windowModel.windowDialog?.style == .confirmationDialog },
            set: { if !$0 { DispatchQueue.main.async { ActionUIModel.shared.dismissDialog(windowUUID: windowUUID) } } }
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
