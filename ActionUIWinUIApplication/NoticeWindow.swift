// ActionUIWinUIApplication/NoticeWindow.swift
/*
 A prepared window made a notice (makeNotice): a small window with no title bar on an acrylic background,
 always on top, out of the taskbar and Alt+Tab. Its host places it (frame, workArea, move) before it shows it
 (show, without taking the focus) and closes it; a tap or click anywhere in it runs onTapped.

 - It is built as presentWindow(prepared:) builds a window, at its content's size (or the options'), without
   the menu bar: the JSON's commands do not join the application's menus. As a window, it shows cloaked
   until its content has loaded and it has its size (WinUIWindow.fit); show's `sized` runs then, before the
   user sees it, for the host to place it again at that size.
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
    public final class NoticeWindow {
        /// A rectangle in screen pixels.
        public struct Frame: Sendable, Equatable {
            public var x: Int32
            public var y: Int32
            public var width: Int32
            public var height: Int32
        }

        private let window: WinUIObject
        private let tree: WinUIWindow
        private let wanted: (width: Int, height: Int)?
        private var isShown = false
        private var isClosed = false

        fileprivate init(window: WinUIObject, tree: WinUIWindow, wanted: (width: Int, height: Int)?) {
            self.window = window
            self.tree = tree
            self.wanted = wanted
        }

        /// The notice's frame on the screen; nil once closed or when it cannot be read.
        public var frame: Frame? {
            guard !isClosed else { return nil }
            var frame = Frame(x: 0, y: 0, width: 0, height: 0)
            guard actionUIWinUIWindowFrame(window.pointer, &frame.x, &frame.y, &frame.width, &frame.height) else { return nil }
            return frame
        }

        /// The work area (the monitor without the taskbar) of the monitor the notice is on, else the
        /// primary monitor's; nil once closed or when it cannot be read.
        public var workArea: Frame? {
            guard !isClosed else { return nil }
            var area = Frame(x: 0, y: 0, width: 0, height: 0)
            guard actionUIWinUIWindowWorkArea(window.pointer, &area.x, &area.y, &area.width, &area.height) else { return nil }
            return area
        }

        /// Puts the notice's top-left corner at x, y (screen pixels).
        public func move(x: Int32, y: Int32) {
            guard !isClosed else { return }
            if !actionUIWinUIWindowMove(window.pointer, x, y) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("moving a notice"))", .warning)
            }
        }

        /// Shows the notice where it is, without activating it: the focus stays where it is. It stays
        /// cloaked until its content has loaded and it is sized to it; `sized` runs then, before it shows,
        /// so the host can place it again. Once.
        public func show(sized: @escaping @MainActor () -> Void = {}) {
            guard !isClosed, !isShown else { return }
            isShown = true
            tree.fit(window, wanted: wanted, cloaks: true, fitted: sized)
            if !actionUIWinUIWindowShowInactive(window.pointer) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("showing a notice"))", .error)
            }
        }

        /// Runs `action` each time the user taps or clicks the notice, until it is closed.
        public func onTapped(_ action: @escaping @MainActor () -> Void) {
            guard !isClosed else { return }
            _ = WinUIEvents.connect(window, actionUIWinUIWindowOnTapped, "a notice's tap", action)
        }

        /// Takes the notice down: its nodes leave the tree, as for a closed window.
        public func close() {
            guard !isClosed else { return }
            isClosed = true
            tree.detach()
            if !actionUIWinUIWindowClose(window.pointer) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("closing a notice"))", .error)
            }
        }

        isolated deinit {
            close()
        }
    }

    /// Builds a prepared window as presentWindow(prepared:) would, at its content's size (the options'
    /// contentSize when given), as a notice (NoticeWindow) not shown yet, for its host to place and show.
    /// nil, and logged, when the application has not started or the JSON could not be loaded. Each prepared
    /// window shows once.
    public func makeNotice(prepared: PreparedWindow, title: String?, options: WindowOptions = WindowOptions()) -> NoticeWindow? {
        let logger = ActionUIModel.shared.logger
        guard !prepared.isUsed else {
            logger.log("Window \(prepared.windowUUID): a prepared window shows once; prepare it again", .error)
            return nil
        }
        prepared.isUsed = true
        guard hasStarted else {
            logger.log("Window \(prepared.windowUUID): the application has not started; nothing to show a notice with", .error)
            return nil
        }
        guard prepared.error == nil else {
            logger.log("Window \(prepared.windowUUID): the ActionUI JSON could not be loaded; no notice", .error)
            return nil
        }
        let windowUUID = prepared.windowUUID
        let tree: WinUIWindow
        do {
            tree = try WinUIWindow.showing(windowUUID: windowUUID)
        } catch {
            logger.log("WinUIApplication: notice \(windowUUID) could not be built: \(error)", .error)
            return nil
        }
        guard let content = tree.view, let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
            logger.log("WinUIApplication: \(WinUIError.last("making the notice for \(windowUUID)"))", .error)
            tree.detach()
            return nil
        }
        // From here on, closing it detaches the tree and closes the WinUI window.
        let notice = NoticeWindow(window: window, tree: tree, wanted: options.contentSize)
        // Its title names it in accessibility tools; no title bar shows it. A first size here, its
        // content's own once it has loaded (show).
        guard actionUIWinUIWindowMakeNotice(window.pointer),
              actionUIWinUIWindowSetTitle(window.pointer, title ?? name ?? "ActionUI"),
              actionUIWinUIWindowSetContent(window.pointer, content.pointer),
              case let size = tree.openingSize(wanted: options.contentSize),
              actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height) else {
            logger.log("WinUIApplication: \(WinUIError.last("setting up the notice for \(windowUUID)"))", .error)
            notice.close()
            return nil
        }
        return notice
    }
}
