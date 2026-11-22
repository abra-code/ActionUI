// ActionUIWinUIApplication/AppPanels.swift
/*
 The application's standalone alert, behind the synchronous C call actionUIAppRunAlert: a WinUI
 ContentDialog. The call returns once the user answers. Until then a nested message loop keeps the
 application running underneath, as NSAlert.runModal does on macOS and a nested GLib loop on Linux:
 windows redraw and handlers run. The work of DispatchQueue.main waits when the call itself came through
 it (a call from another thread), as a serial queue does on macOS.

 The configuration is the macOS JSON, read key by key (a key of the wrong type is ignored): title,
 message, style, buttons. The first button is the default (Enter); a button titled "Cancel" answers
 Escape, as in AppKit, and so does a single button. The buttons stand in Fluent's order, the default
 first (leftmost), not AppKit's. ContentDialog has no style icon, so style is ignored, as on Linux.

 The alert opens over the active window, else the one presented last. With no window, or when that
 window shows a dialog already (a sheet, another alert: WinUI shows one at a time in a window), it opens
 in a small window of its own. It answers nil when its window closes under it or the application
 terminates. Called before the application runs, it logs why and answers nil.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
import CWinUI

// MARK: - The request, read from the JSON

/// An alert as the JSON describes it.
struct AlertRequest: Equatable {
    var title: String?
    var message: String?
    /// Button titles in the JSON's order; the first is the default.
    var buttons: [String]
    /// The button Escape answers, or nil when Escape does nothing.
    var escapeButton: Int?

    init(json: String?) {
        let config = AppPanels.dictionary(json)
        title = config["title"] as? String
        message = config["message"] as? String
        let titles = config["buttons"] as? [String] ?? []
        buttons = titles.isEmpty ? ["OK"] : titles
        if let cancel = buttons.firstIndex(of: "Cancel") {
            escapeButton = cancel
        } else {
            escapeButton = buttons.count == 1 ? 0 : nil
        }
    }
}

// MARK: - Running it

@MainActor
enum AppPanels {
    /// An alert waiting for its answer.
    @MainActor private final class OpenAlert {
        /// The window it is over (its own, or an ActionUI window).
        let window: WinUIObject
        var dialog: WinUIObject?
        /// The alert's own window was closed (by the user): nothing to close after the answer.
        var windowClosed = false
        /// Read by the nested loop; set with the answer.
        let done = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        var index: Int32 = -1

        init(window: WinUIObject) {
            self.window = window
            done.initialize(to: false)
        }

        isolated deinit {
            done.deallocate()
        }

        func dismiss() {
            if let dialog, !done.pointee, !actionUIWinUIAlertDismiss(dialog.pointer) {
                ActionUIModel.shared.logger.log("AppPanels: \(WinUIError.last("closing an alert"))", .error)
            }
        }
    }

    /// The alerts waiting for an answer, innermost last.
    private static var open: [OpenAlert] = []

    /// The size of the content of the window an alert opens in when no window can take it: room for
    /// WinUI's dialog (at most 548 wide) and a few lines of message.
    private static let ownWindowSize = (width: 600.0, height: 360.0)

    /// actionUIAppRunAlert: the chosen button's title, or nil when the alert closed unanswered.
    static func runAlert(json: String?) -> String? {
        runAlert(AlertRequest(json: json))
    }

    /// The JSON's top-level object; empty for nil or anything else.
    nonisolated static func dictionary(_ json: String?) -> [String: Any] {
        guard let json, let parsed = try? ActionUIJSON.value(from: json) as? [String: Any] else { return [:] }
        return parsed
    }

    /// The alerts over `window` answer nil: it is closing.
    static func windowClosing(_ window: WinUIObject) {
        for alert in open where alert.window === window {
            alert.dismiss()
        }
    }

    /// Every alert waiting answers nil: the application is terminating.
    static func dismissAll() {
        for alert in open {
            alert.dismiss()
        }
    }

    static func runAlert(_ request: AlertRequest) -> String? {
        let logger = ActionUIModel.shared.logger
        guard WinUIApplication.shared.hasStarted else {
            logger.log("actionUIAppRunAlert: call it while the application runs (from didFinishLaunching on)", .error)
            return nil
        }
        var alert: OpenAlert?
        var ownWindow: WinUIObject?
        if let owner = WinUIApplication.shared.panelOwner() {
            let over = OpenAlert(window: owner.window)
            over.dialog = show(request, over: owner.content, for: over)
            if over.dialog != nil {
                alert = over
            }
        }
        if alert == nil {
            guard let (window, content) = makeOwnWindow() else {
                logger.log("AppPanels: \(WinUIError.last("making a window for an alert"))", .error)
                return nil
            }
            ownWindow = window
            let over = OpenAlert(window: window)
            over.dialog = show(request, over: content, for: over)
            guard over.dialog != nil else {
                logger.log("AppPanels: \(WinUIError.last("showing an alert"))", .error)
                _ = actionUIWinUIWindowClose(window.pointer)
                return nil
            }
            // The user closing it answers nil.
            WinUIEvents.connect(window, actionUIWinUIWindowOnClosed, "an alert window's closing") { [weak over] in
                over?.windowClosed = true
                over?.dismiss()
            }
            alert = over
        }
        guard let alert else { return nil }
        open.append(alert)
        if !actionUIWinUIRunNestedLoop(alert.done) {
            // The application is quitting (or the loop failed): the alert goes unanswered.
            alert.dismiss()
        }
        open.removeAll { $0 === alert }
        if let ownWindow, !alert.windowClosed, !actionUIWinUIWindowClose(ownWindow.pointer) {
            logger.log("AppPanels: \(WinUIError.last("closing an alert's window"))", .error)
        }
        let index = Int(alert.index)
        return request.buttons.indices.contains(index) ? request.buttons[index] : nil
    }

    /// The alert over the window `content` is in; nil when it cannot be shown there (no error logged:
    /// the caller tries a window of the alert's own).
    private static func show(_ request: AlertRequest, over content: WinUIObject, for alert: OpenAlert) -> WinUIObject? {
        // The titles as C strings, for the call.
        let titles: [UnsafeMutablePointer<CChar>] = request.buttons.map { title in
            let bytes = Array(title.utf8CString)
            let copy = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
            copy.initialize(from: bytes, count: bytes.count)
            return copy
        }
        defer { titles.forEach { $0.deallocate() } }
        let pointers: [UnsafePointer<CChar>?] = titles.map { UnsafePointer($0) }
        let context = Unmanaged.passUnretained(alert).toOpaque()
        let dialog = pointers.withUnsafeBufferPointer { buffer in
            actionUIWinUIAlertShow(content.pointer, request.title, request.message, buffer.baseAddress,
                                   Int32(buffer.count), Int32(request.escapeButton ?? -1), alertAnswered, context)
        }
        return WinUIObject(adopting: dialog)
    }

    /// A small window for an alert, titled with the application's name, shown; with its content.
    private static func makeOwnWindow() -> (window: WinUIObject, content: WinUIObject)? {
        guard let window = WinUIObject(adopting: actionUIWinUIWindowCreate()),
              let content = WinUIObject(adopting: actionUIWinUITextBlockCreate()),
              actionUIWinUIWindowSetTitle(window.pointer, WinUIApplication.shared.name ?? "ActionUI"),
              actionUIWinUIWindowSetContent(window.pointer, content.pointer),
              actionUIWinUIWindowSetContentSize(window.pointer, ownWindowSize.width, ownWindowSize.height),
              actionUIWinUIWindowActivate(window.pointer) else { return nil }
        return (window, content)
    }

    /// The shim's answer: on the UI thread, once per alert, while runAlert waits for it (the alert is
    /// alive: runAlert dismisses it, which answers at once, before it returns).
    private static let alertAnswered: ActionUIWinUIAlertCompletion = { context, index in
        guard let context else { return }
        let alert = Unmanaged<OpenAlert>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            alert.index = index
            alert.done.pointee = true
        }
    }
}
