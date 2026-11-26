// ActionUIWinUIApplication/OffscreenWindow.swift
/*
 A prepared window drawn where the user never sees it (renderOffscreen), for a host that captures
 ActionUI JSON as an image before showing it, as on Linux.

 - The window is a WinUI window shown without activation past every monitor's edge, out of the
   taskbar and Alt+Tab: WinUI draws only a window that is shown, and the focus stays where it is.
 - It is built as presentWindow(prepared:) builds a window, at the same size, without the menu bar:
   the JSON's commands do not join the application's menus. Windows keeps a window no larger than about
   the screen, so a larger size asked for is cut to that, as on Linux.
 - A WebView's page is drawn as a shown window's capture draws it (the shim adds each page from the
   WebView's own capture).
 - It is not among the application's windows: no windowWillClose, and its closing never ends the
   application. Its model stays the host's to remove, as for a prepared window.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
import CWinUI

extension WinUIApplication {
    @MainActor
    public final class OffscreenWindow {
        private let window: WinUIObject
        private let tree: WinUIWindow
        private var isClosed = false

        fileprivate init(window: WinUIObject, tree: WinUIWindow) {
            self.window = window
            self.tree = tree
        }

        /// Saves what the window draws as a PNG file at `path`, scaled down so that neither side is larger
        /// than `maxPixels`. Asynchronous: `completion` says whether the file was written; false when the
        /// window is closed, or not drawn yet (a window shown a moment ago).
        public func capturePNG(path: String, maxPixels: Int, completion: @escaping @MainActor (Bool) -> Void) {
            guard !isClosed else {
                completion(false)
                return
            }
            let box = Unmanaged.passRetained(PNGCompletion(completion)).toOpaque()
            if !actionUIWinUIWindowRenderToPNGWithin(window.pointer, path, UInt32(clamping: max(0, maxPixels)), pngRendered, box) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("capturing \(path)"))", .error)
                Unmanaged<PNGCompletion>.fromOpaque(box).release()
                completion(false)
            }
        }

        /// Takes the window down: its nodes leave the tree, as for a closed window. A capture after it
        /// is false.
        public func close() {
            guard !isClosed else { return }
            isClosed = true
            tree.detach()
            if !actionUIWinUIWindowClose(window.pointer) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("closing an offscreen window"))", .error)
            }
        }

        isolated deinit {
            close()
        }
    }

    /// Builds a prepared window as presentWindow(prepared:) would, titled `title`, and shows it where
    /// the user never sees it (OffscreenWindow). nil, and logged, when the application has not started
    /// or the JSON could not be loaded. Each prepared window shows or renders once.
    public func renderOffscreen(prepared: PreparedWindow, title: String?, options: WindowOptions = WindowOptions()) -> OffscreenWindow? {
        let logger = ActionUIModel.shared.logger
        guard !prepared.isUsed else {
            logger.log("Window \(prepared.windowUUID): a prepared window shows once; prepare it again", .error)
            return nil
        }
        prepared.isUsed = true
        guard hasStarted else {
            logger.log("Window \(prepared.windowUUID): the application has not started; nothing to render with", .error)
            return nil
        }
        guard prepared.error == nil else {
            logger.log("Window \(prepared.windowUUID): the ActionUI JSON could not be loaded; nothing to render", .error)
            return nil
        }
        let windowUUID = prepared.windowUUID
        let tree: WinUIWindow
        do {
            tree = try WinUIWindow.showing(windowUUID: windowUUID)
        } catch {
            logger.log("WinUIApplication: window \(windowUUID) could not be rendered: \(error)", .error)
            return nil
        }
        guard let content = tree.view, let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
            logger.log("WinUIApplication: \(WinUIError.last("making the offscreen window for \(windowUUID)"))", .error)
            tree.detach()
            return nil
        }
        // From here on, closing it detaches the tree and closes the WinUI window.
        let offscreen = OffscreenWindow(window: window, tree: tree)
        let shownTitle = title ?? tree.groupTitle ?? name ?? "ActionUI"
        let fullTitle = options.subtitle.flatMap { $0.isEmpty ? nil : "\($0) - \(shownTitle)" } ?? shownTitle
        // The options' content size, side by side, else the content's own, as presentWindow sizes it.
        var size = tree.openingSize()
        if let wanted = options.contentSize {
            if wanted.width > 0 { size.width = Double(wanted.width) }
            if wanted.height > 0 { size.height = Double(wanted.height) }
        }
        // Placed before it is sized: the size is in the pixels of the monitor nearest its place.
        guard actionUIWinUIWindowPlaceOffscreen(window.pointer),
              actionUIWinUIWindowSetTitle(window.pointer, fullTitle),
              actionUIWinUIWindowSetContent(window.pointer, content.pointer),
              actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height),
              actionUIWinUIWindowShowInactive(window.pointer) else {
            logger.log("WinUIApplication: \(WinUIError.last("setting up the offscreen window for \(windowUUID)"))", .error)
            offscreen.close()
            return nil
        }
        return offscreen
    }
}
