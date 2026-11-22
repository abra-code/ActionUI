// Sources/Runtime/WinUIWindow.swift
/*
 The render tree of one ActionUI window on WinUI: the root node built from the window model's
 loaded element (Linux: AdwaitaWindow). `view` is what goes into a WinUI window's content;
 openingSize is the size the application layer (ActionUIWinUIApplication) opens its window at.
*/

import CWinUI

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

    /// Loads the ActionUI JSON (or plist, by its extension) in the regular file at `url` into the
    /// window model `windowUUID`, as from that file: it is the app's own when it is in the app's
    /// resources, else less trusted (JSONContentOrigin), and builds its tree.
    package static func load(file url: URL, windowUUID: String) throws -> WinUIWindow {
        let data = try ActionUIDocumentLoader.readRegularFile(url)
        _ = try ActionUIDocumentLoader.load(data: data, format: ActionUIDocumentLoader.format(of: url), windowUUID: windowUUID,
                                            isContentView: true, parentID: 0, source: .file(url))
        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            throw ActionUIError("WinUIWindow: no window model for \(windowUUID) after loading")
        }
        return WinUIWindow(windowModel: windowModel)
    }

    /// Loads ActionUI JSON (or plist, by the address's extension) fetched from `url` into the window
    /// model `windowUUID`, as from `finalURL` (the address it finally came from after redirects; nil:
    /// `url`), which decides its trust (a trusted origin of the host's configuration, else less trusted),
    /// and builds its tree. A final address Foundation cannot read, or one with a backslash or a user name
    /// (where Windows' and Foundation's readings of the host could differ), is refused.
    package static func load(data: Data, from url: URL, finalURL finalText: String?, windowUUID: String) throws -> WinUIWindow {
        var source = url
        if let finalText {
            guard let read = URL(string: finalText), !finalText.contains("\\"), read.user == nil else {
                throw ActionUIError("\(url.absoluteString) was redirected to an address that cannot be read")
            }
            source = read
        }
        _ = try ActionUIDocumentLoader.load(data: data, format: ActionUIDocumentLoader.format(of: url), windowUUID: windowUUID,
                                            isContentView: true, parentID: 0, source: .remote(source))
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

    /// The size a window opens at when its content is too small to say: SwiftUI's default (macOS).
    package static let fallbackSize = ActionUIWinUISize(width: 480, height: 320)
    /// The widest a window opens unless its content's minimum needs more: SwiftUI's WindowGroup opens
    /// 900 points wide on macOS (measured on macOS 27, whatever the content), as on Linux.
    package static let openingWidth = 900.0
    /// The least a window opens tall when its content grows vertically (a List, a ScrollView, a Color):
    /// SwiftUI's WindowGroup gives its content 418 points (macOS 27), as on Linux.
    package static let openingHeight = 418.0

    /// The content size the window opens at, as on Linux: the content's size measured in the opening
    /// width (wider only when its minimum needs it), at least openingHeight tall when it grows
    /// vertically; fallbackSize when it measures under 10 by 10.
    package func openingSize() -> ActionUIWinUISize {
        guard let view else { return Self.fallbackSize }
        let measured = actionUIWinUIElementMeasure(view.pointer, ActionUIWinUISize(width: Self.openingWidth, height: .infinity))
        guard measured.width.isFinite, measured.height.isFinite, measured.width >= 10 || measured.height >= 10 else {
            return Self.fallbackSize
        }
        var height = measured.height.rounded(.up)
        if root?.expansion.contains(.vertical) == true {
            height = max(height, Self.openingHeight)
        }
        return ActionUIWinUISize(width: max(measured.width.rounded(.up), 1), height: max(height, 1))
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
