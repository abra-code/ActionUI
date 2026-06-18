// Common/ToastOverlayView.swift

import SwiftUI

// A transient, top-pinned toast / snackbar. WindowModalView renders this as a top overlay on the
// window root whenever windowModel.windowToast is set. Top placement is deliberate: it follows the
// Apple transient-banner idiom (notification-style banners slide from the top on iOS/macOS), rather
// than the Material snackbar's bottom placement (which the Android renderer uses). It owns the
// cross-cutting toast details that are easy to get wrong per-host: the auto-dismiss timer and the
// VoiceOver/TalkBack announcement. The reduce-motion-aware insertion transition is applied by the
// parent (which owns the conditional insertion/removal needed for SwiftUI transitions to run).
@MainActor
struct ToastOverlayView: SwiftUI.View {
    let toast: WindowToast
    let windowUUID: String

    var body: some SwiftUI.View {
        SwiftUI.HStack(spacing: 12) {
            SwiftUI.Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let action = toast.action {
                SwiftUI.Spacer(minLength: 8)
                SwiftUI.Button(action.title) {
                    ActionUIModel.shared.actionHandler(action.actionID, windowUUID: windowUUID, viewID: 0, viewPartID: 0)
                    ActionUIModel.shared.dismissToast(windowUUID: windowUUID)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            SwiftUI.RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwiftUI.Color(white: 0.15))
                .shadow(radius: 8, y: 2)
        )
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // Treat the whole card as one a11y element so VoiceOver reads message then action.
        .accessibilityElement(children: .combine)
        .task(id: toast.id) {
            announce(toast.message)
            let nanos = UInt64(max(0, toast.duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if !Task.isCancelled {
                ActionUIModel.shared.dismissToast(windowUUID: windowUUID)
            }
        }
    }

    // Post a non-visual announcement so the toast is conveyed under VoiceOver / TalkBack even
    // though it is a transient, non-focusable element.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
