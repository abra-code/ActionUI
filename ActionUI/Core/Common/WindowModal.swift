// Core/Common/WindowModal.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Public types (used in ActionUIModel public API)

/// Presentation style for window-level modal.
public enum ModalStyle: Sendable {
    case sheet
    case fullScreenCover
}

/// The role of a dialog button. A renderer maps it to its own (SwiftUI: ButtonRole).
public enum DialogButtonRole: Sendable {
    case cancel
    case destructive
}

/// A button descriptor for window-level alerts and confirmation dialogs.
public struct DialogButton: Sendable {
    public let title: String
    public let role: DialogButtonRole?    // nil = default, .destructive, .cancel
    public let actionID: String?    // action fired on tap; nil = dismiss only

    public init(title: String, role: DialogButtonRole? = nil, actionID: String? = nil) {
        self.title = title
        self.role = role
        self.actionID = actionID
    }
}

// MARK: - Internal model types

/// Differentiates alert from confirmationDialog inside WindowDialog.
enum DialogStyle {
    case alert
    case confirmationDialog
}

/// Holds a loaded element and its presentation style for window-level sheet / fullScreenCover.
/// Created by ActionUIModel.presentModal; dismissed by ActionUIModel.dismissModal.
@MainActor
struct WindowModal: Identifiable {
    let id = UUID()
    let element: ActionUIElement
    let style: ModalStyle
    let onDismissActionID: String?
    /// IDs of all ViewModels loaded for this modal — removed from WindowModel on dismiss.
    let loadedViewIDs: Set<Int>
}

/// Holds pure data for a window-level alert or confirmationDialog.
/// No ViewModels are allocated — content is title, message, and buttons only.
struct WindowDialog: Identifiable {
    let id = UUID()
    let style: DialogStyle
    let title: String
    let message: String?
    let buttons: [DialogButton]
}
