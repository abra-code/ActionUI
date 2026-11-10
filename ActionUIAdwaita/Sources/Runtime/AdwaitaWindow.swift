// Sources/Runtime/AdwaitaWindow.swift
/*
 The render tree of one ActionUI window: the root node built from the window model's loaded
 element, and, once the window is on screen, its window-level presentations (WindowPresenter).
 Presenting it in a GTK window comes with the application runtime.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
package final class AdwaitaWindow {
    let windowModel: WindowModel
    /// The root element's node; nil when the window model has no element loaded.
    package private(set) var root: RenderNode?
    /// The window's modals, dialogs and toasts, once the window is on screen.
    package private(set) var presenter: WindowPresenter?

    var windowUUID: String { windowModel.windowUUID }

    /// The window's content: the root node's box.
    package var contentWidget: WidgetPointer? { root?.outerWidget }

    /// The tree for the document loaded under `windowUUID`, nil when none is loaded: for the
    /// application module, which cannot see the model's internal window models.
    package static func forWindow(_ windowUUID: String) -> AdwaitaWindow? {
        ActionUIModel.shared.windowModels[windowUUID].map { AdwaitaWindow(windowModel: $0) }
    }

    /// Builds and syncs the tree for the element loaded into `windowModel`.
    init(windowModel: WindowModel) {
        self.windowModel = windowModel
        guard let element = windowModel.element else {
            ActionUIModel.shared.logger.log("AdwaitaWindow: window \(windowModel.windowUUID) has no element loaded", .error)
            return
        }
        guard let model = windowModel.viewModels[element.id] else {
            ActionUIModel.shared.logger.log("AdwaitaWindow: no view model for the root element \(element.id) in window \(windowModel.windowUUID)", .error)
            return
        }
        let root = RenderNode(element: element, model: model, windowModel: windowModel, parent: nil)
        root.isWindowRoot = true
        self.root = root
        root.sync()
    }

    /// Element types whose renderer shows header bars of its own, so the window shows none when the
    /// document is one of them.
    static let headerBarTypes: Set<String> = ["NavigationStack", "NavigationSplitView"]

    /// Whether the document brings its own header bars (its root is a navigation container).
    package var showsOwnHeaderBars: Bool {
        root.map { Self.headerBarTypes.contains($0.element.type) } ?? false
    }

    /// Starts showing the window model's modals, dialogs and toasts: dialogs over `parent`'s
    /// window, toasts in `toastOverlay` (an AdwToastOverlay).
    package func startPresenting(over parent: WidgetPointer, toastOverlay: OpaquePointer) {
        presenter?.stop()
        presenter = WindowPresenter(windowModel: windowModel, parent: parent, toastOverlay: toastOverlay)
    }

    /// The window is going away: its nodes leave the tree and its presentations come down.
    package func detach() {
        presenter?.stop()
        presenter = nil
        root?.detach()
    }

    // A flush queued before the window went away holds its nodes; detached, they are skipped.
    isolated deinit {
        presenter?.stop()
        root?.detach()
    }
}

@MainActor
extension ActionUIModel {
    /// Loads a window's document into the model under `windowUUID` (loadDescription), for the
    /// application module: Core is also built for Apple, where it takes no package access.
    package func loadWindowDocument(_ data: Data, format: String, windowUUID: String) throws {
        _ = try loadDescription(from: data, format: format, windowUUID: windowUUID)
    }
}
