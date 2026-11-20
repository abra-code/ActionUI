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

    /// The command rows around the root, when the document declares a toolbar outside a navigation
    /// container (WindowCommandBar).
    private var commandBar: WindowCommandBar?

    /// The window's content: the command bar holding the root's box, or the root's box (its WinUI
    /// object with its padding and frame).
    package var view: WinUIObject? { commandBar?.panel.object ?? root?.outerView }

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
        // Before the first sync, in which the toolbars show their items.
        if Self.declaresWindowToolbar(element), let content = root.outerView {
            do {
                let bar = try WindowCommandBar(content: content)
                commandBar = bar
                WindowCommandBar.register(bar, windowUUID: windowModel.windowUUID)
            } catch {
                ActionUIModel.shared.logger.log("WinUIWindow: \(error); the toolbars are not shown", .error)
            }
        }
        root.sync()
    }

    /// Whether `element` or an element under it, outside a navigation container, declares a toolbar.
    private static func declaresWindowToolbar(_ element: any ActionUIElementBase) -> Bool {
        if !ToolbarHelper.screenToolbarItems(of: element).isEmpty { return true }
        guard !ToolbarHelper.isNavigationContainer(element.type) else { return false }
        for value in (element.subviews ?? [:]).values {
            switch value {
            case let one as any ActionUIElementBase:
                if declaresWindowToolbar(one) { return true }
            case let list as [any ActionUIElementBase]:
                if list.contains(where: declaresWindowToolbar) { return true }
            case let rows as [[any ActionUIElementBase]]:
                if rows.joined().contains(where: declaresWindowToolbar) { return true }
            default:
                break
            }
        }
        return false
    }

    /// The window is going away: its nodes leave the tree.
    package func detach() {
        root?.detach()
        // Only its own: another window may have taken the id since.
        if let commandBar, WindowCommandBar.of(windowUUID: windowModel.windowUUID) === commandBar {
            WindowCommandBar.register(nil, windowUUID: windowModel.windowUUID)
        }
    }

    isolated deinit {
        root?.detach()
    }
}
