// Common/WindowToast.swift

import SwiftUI

// MARK: - Public types (used in ActionUIModel public API)

/// An optional inline action shown alongside a toast (for example "Undo").
/// Tapping it fires `actionID` and dismisses the toast.
public struct ToastAction: Sendable {
    public let title: String
    public let actionID: String

    public init(title: String, actionID: String) {
        self.title = title
        self.actionID = actionID
    }
}

// MARK: - Internal model type

/// Holds pure data for a window-level toast / snackbar.
/// No ViewModels are allocated: content is a message, an auto-dismiss duration, and an optional
/// inline action. Created by ActionUIModel.presentToast; cleared by ActionUIModel.dismissToast.
/// Rendered top-pinned by ToastOverlayView (attached via WindowModalView).
@MainActor
struct WindowToast: Identifiable {
    let id = UUID()
    let message: String
    let duration: TimeInterval
    let action: ToastAction?
}
