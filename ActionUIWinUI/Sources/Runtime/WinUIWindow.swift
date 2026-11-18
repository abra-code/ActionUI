// Sources/Runtime/WinUIWindow.swift
/*
 The render tree of one ActionUI window on WinUI: the root node built from the window model's
 loaded element (Linux: AdwaitaWindow). `view` is what goes into a WinUI window's content.
 Presenting it in an application window, with its title, size and menus, comes with the
 application layer.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
package final class WinUIWindow {
    let windowModel: WindowModel
    /// The root element's node; nil when the window model has no element loaded.
    package private(set) var root: RenderNode?

    package var windowUUID: String { windowModel.windowUUID }

    /// The WinUI object of the root element: the window's content.
    package var view: WinUIObject? { root?.view }

    /// Loads `json` (an ActionUI document) into the window model `windowUUID` and builds its tree.
    package static func load(json: String, windowUUID: String) throws -> WinUIWindow {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            throw ActionUIError("WinUIWindow: no window model for \(windowUUID) after loading")
        }
        return WinUIWindow(windowModel: windowModel)
    }

    /// Builds and syncs the tree for the element loaded into `windowModel`.
    init(windowModel: WindowModel) {
        self.windowModel = windowModel
        guard let element = windowModel.element else {
            ActionUIModel.shared.logger.log("WinUIWindow: window \(windowModel.windowUUID) has no element loaded", .error)
            return
        }
        guard let model = windowModel.viewModels[element.id] else {
            ActionUIModel.shared.logger.log("WinUIWindow: no view model for the root element \(element.id) in window \(windowModel.windowUUID)", .error)
            return
        }
        let root = RenderNode(element: element, model: model, windowModel: windowModel, parent: nil)
        self.root = root
        root.sync()
    }

    /// The window is going away: its nodes leave the tree.
    package func detach() {
        root?.detach()
    }

    isolated deinit {
        root?.detach()
    }
}
