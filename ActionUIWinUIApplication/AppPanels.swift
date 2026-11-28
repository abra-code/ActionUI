// ActionUIWinUIApplication/AppPanels.swift
/*
 The application's standalone alert and its file panels, behind the synchronous C calls
 actionUIAppRunAlert, actionUIAppRunOpenPanel and actionUIAppRunSavePanel: a WinUI ContentDialog and the
 system's file dialogs (IFileOpenDialog, IFileSaveDialog). The alert returns once the user answers. Until then a nested message loop keeps the
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
 terminates.

 File panels, from the macOS JSON as well: title, prompt (the accept button), directoryURL (a path or a
 file URL), nameFieldStringValue (save), allowedContentTypes (filename extensions, MIME types, or the
 common uniform type identifiers), allowsMultipleSelection, canChooseFiles, canChooseDirectories,
 allowsOtherFileTypes. Windows' dialog chooses files or folders, not both, so an open panel that allows
 both chooses files, as on Linux. A saved name gets the first allowed extension when it has none of them,
 as NSSavePanel does. message, identifier, showsHiddenFiles, treatsFilePackagesAsDirectories and
 canCreateDirectories have no counterpart and are ignored. A panel is modal to the active window, else the
 one presented last, else to none; it runs its own message loop, so the application runs underneath, and
 it is canceled (nil) when its window closes or the application terminates.

 beginOpenPanel and beginSavePanel do not wait, for a host that serves other work meanwhile, as
 NSOpenPanel's begin does: they return at once and a closure gets the answer. Each dialog runs on a thread
 of its own, with no owner window, so nothing nests: several can be up at a time and each answers when its
 user does. They are canceled when the application terminates.

 Called before the application runs, each logs why and answers nil.
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

/// A file panel as the JSON describes it, in the Windows dialog's terms.
struct FilePanelRequest: Equatable {
    enum Mode: Equatable {
        case open, openFolders, save
    }

    var mode: Mode
    var multiple: Bool
    var title: String?
    var acceptLabel: String?
    var initialFolder: String?
    var initialName: String?
    /// The allowed extensions, lowercased, without the dot; empty: any file.
    var extensions: [String]
    var allowsOtherTypes: Bool

    init(json: String?, saving: Bool) {
        let config = AppPanels.dictionary(json)
        title = config["title"] as? String
        acceptLabel = config["prompt"] as? String
        initialFolder = (config["directoryURL"] as? String).map(Self.path(directoryURL:))
        initialName = saving ? config["nameFieldStringValue"] as? String : nil
        allowsOtherTypes = config["allowsOtherFileTypes"] as? Bool ?? false
        let entries = config["allowedContentTypes"] as? [String] ?? []
        let resolved = entries.map(Self.extensions)
        // An entry of any file ("public.data", "*/*") lifts the restriction.
        if resolved.contains(where: { $0 == nil }) {
            extensions = []
        } else {
            var unique: [String] = []
            for found in resolved.compactMap({ $0 }).joined() where !unique.contains(found) {
                unique.append(found)
            }
            extensions = unique
        }
        if saving {
            mode = .save
            multiple = false
        } else {
            multiple = config["allowsMultipleSelection"] as? Bool ?? false
            let files = config["canChooseFiles"] as? Bool ?? true
            let folders = config["canChooseDirectories"] as? Bool ?? false
            mode = folders && !files ? .openFolders : .open
        }
    }

    /// macOS reads directoryURL as a path; a file URL is taken too, as the path Windows writes.
    static func path(directoryURL: String) -> String {
        guard directoryURL.lowercased().hasPrefix("file:"), let url = URL(string: directoryURL) else { return directoryURL }
        return url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? directoryURL
    }

    /// The extensions one allowedContentTypes entry allows: itself ("json"), those of a MIME type
    /// ("image/png", "image/*") or of a uniform type identifier ("public.image"). nil: any file (an
    /// identifier or MIME type of no particular type); empty: an entry not known, which allows nothing.
    static func extensions(_ entry: String) -> [String]? {
        let lowered = entry.lowercased()
        if lowered.contains("/") {
            return extensionsForMIMEType[lowered] ?? []
        }
        if !lowered.contains(".") {
            return lowered.isEmpty ? [] : [lowered]
        }
        return extensionsForIdentifier[lowered] ?? []
    }

    private static let images = ["png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "heic", "webp", "svg"]
    private static let audio = ["mp3", "m4a", "aac", "wav", "flac", "wma", "ogg"]
    private static let video = ["mp4", "m4v", "mov", "avi", "wmv", "mkv", "webm"]

    /// The common uniform type identifiers, by their extensions (nil: any file).
    static let extensionsForIdentifier: [String: [String]?] = [
        "public.data": nil,
        "public.item": nil,
        "public.content": nil,
        "public.image": images,
        "public.jpeg": ["jpg", "jpeg"],
        "public.png": ["png"],
        "public.tiff": ["tif", "tiff"],
        "public.heic": ["heic"],
        "com.compuserve.gif": ["gif"],
        "org.webmproject.webp": ["webp"],
        "com.microsoft.bmp": ["bmp"],
        "public.svg-image": ["svg"],
        "public.text": ["txt", "md", "csv", "json", "xml", "html", "htm"],
        "public.plain-text": ["txt"],
        "public.utf8-plain-text": ["txt"],
        "public.json": ["json"],
        "public.xml": ["xml"],
        "public.html": ["html", "htm"],
        "public.comma-separated-values-text": ["csv"],
        "public.python-script": ["py"],
        "com.adobe.pdf": ["pdf"],
        "public.audio": audio,
        "public.movie": video,
        "public.video": video,
        "public.mpeg-4": ["mp4"],
        "public.zip-archive": ["zip"],
    ]

    /// The common MIME types, by their extensions (nil: any file).
    static let extensionsForMIMEType: [String: [String]?] = [
        "*/*": nil,
        "application/octet-stream": nil,
        "image/*": images,
        "image/png": ["png"],
        "image/jpeg": ["jpg", "jpeg"],
        "image/gif": ["gif"],
        "image/tiff": ["tif", "tiff"],
        "image/heic": ["heic"],
        "image/webp": ["webp"],
        "image/bmp": ["bmp"],
        "image/svg+xml": ["svg"],
        "text/*": ["txt", "md", "csv", "json", "xml", "html", "htm"],
        "text/plain": ["txt"],
        "text/csv": ["csv"],
        "text/html": ["html", "htm"],
        "text/xml": ["xml"],
        "application/xml": ["xml"],
        "application/json": ["json"],
        "application/pdf": ["pdf"],
        "application/zip": ["zip"],
        "text/x-python": ["py"],
        "audio/*": audio,
        "video/*": video,
        "video/mp4": ["mp4"],
    ]

    /// The dialog's filters: one with every allowed extension, the default; and, for a save panel that
    /// allows other types (the only panel macOS applies that key to), one for any file. None: any file.
    var filters: [(name: String, pattern: String)] {
        guard !extensions.isEmpty, mode != .openFolders else { return [] }
        var filters = [(name: extensions.joined(separator: ", "), pattern: extensions.map { "*." + $0 }.joined(separator: ";"))]
        if mode == .save && allowsOtherTypes {
            filters.append((name: "All files", pattern: "*.*"))
        }
        return filters
    }

    /// The shim's kind of dialog for the mode.
    var dialogKind: ActionUIWinUIFileDialogKind {
        switch mode {
        case .open: ActionUIWinUIFileDialogKindOpen
        case .openFolders: ActionUIWinUIFileDialogKindOpenFolder
        case .save: ActionUIWinUIFileDialogKindSave
        }
    }

    /// Extensions forced on a saved name when only the allowed types may be saved.
    var strictTypes: Bool {
        mode == .save && !allowsOtherTypes && !extensions.isEmpty
    }

    /// The paths in the shim's answer (one per line), saved paths with their extension (savedPath); nil
    /// when there are none.
    func paths(chosen: String) -> [String]? {
        let paths = chosen.split(separator: "\n").map(String.init)
        guard !paths.isEmpty else { return nil }
        return mode == .save ? paths.map(savedPath) : paths
    }

    /// The saved path with the first allowed extension added when it has none of them, as NSSavePanel
    /// does; unchanged when other types are allowed or any file is.
    func savedPath(_ path: String) -> String {
        guard mode == .save, !allowsOtherTypes, let first = extensions.first else { return path }
        let name = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? path
        let lowered = name.lowercased()
        if extensions.contains(where: { lowered.hasSuffix("." + $0) }) {
            return path
        }
        return path + "." + first
    }
}

// MARK: - Running them

/// A file panel on screen, from AppPanels.beginOpenPanel or beginSavePanel.
@MainActor
public final class FilePanel {
    /// The shim's dialog; nil once the panel has answered (or never showed).
    fileprivate var task: OpaquePointer?
    fileprivate let request: FilePanelRequest
    private var completion: (@MainActor ([String]?) -> Void)?

    fileprivate init(request: FilePanelRequest, completion: @escaping @MainActor ([String]?) -> Void) {
        self.request = request
        self.completion = completion
    }

    /// Closes the panel unanswered: its closure runs with nil, from the main loop. Nothing happens once the
    /// panel has answered.
    public func cancel() {
        if let task {
            actionUIWinUIFileDialogCancel(task)
        }
    }

    /// The answer: frees the dialog's handle and runs the closure, once.
    fileprivate func finish(_ paths: [String]?) {
        if let task {
            actionUIWinUIFileDialogRelease(task)
            self.task = nil
        }
        AppPanels.forget(self)
        let completion = self.completion
        self.completion = nil
        completion?(paths)
    }
}

@MainActor
public enum AppPanels {
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

    /// actionUIAppRunOpenPanel: the chosen paths, or nil when the panel was canceled.
    static func runOpenPanel(json: String?) -> [String]? {
        runFilePanel(FilePanelRequest(json: json, saving: false))
    }

    /// actionUIAppRunSavePanel: the chosen path, or nil when the panel was canceled.
    static func runSavePanel(json: String?) -> String? {
        runFilePanel(FilePanelRequest(json: json, saving: true))?.first
    }

    /// Whether `entry` names a file type the panels know: an extension, a MIME type or a common uniform type
    /// identifier (one of any file counts).
    public nonisolated static func knowsFileType(_ entry: String) -> Bool {
        FilePanelRequest.extensions(entry) != []
    }

    /// Shows an open panel and returns at once. `completion` runs from the main loop with the chosen
    /// paths, or nil when the panel was canceled (or could not be shown: logged). If the application
    /// terminates, the panel is canceled and `completion` runs only if the main loop runs again.
    @discardableResult
    public static func beginOpenPanel(json: String?, completion: @escaping @MainActor ([String]?) -> Void) -> FilePanel {
        beginFilePanel(FilePanelRequest(json: json, saving: false), completion: completion)
    }

    /// Shows a save panel and returns at once. `completion` gets the chosen path, as in beginOpenPanel.
    @discardableResult
    public static func beginSavePanel(json: String?, completion: @escaping @MainActor (String?) -> Void) -> FilePanel {
        beginFilePanel(FilePanelRequest(json: json, saving: true)) { completion($0?.first) }
    }

    /// The panels begun and not answered yet, canceled when the application terminates.
    private static var begun: [FilePanel] = []

    fileprivate static func forget(_ panel: FilePanel) {
        begun.removeAll { $0 === panel }
    }

    static func beginFilePanel(_ request: FilePanelRequest, completion: @escaping @MainActor ([String]?) -> Void) -> FilePanel {
        let panel = FilePanel(request: request, completion: completion)
        let logger = ActionUIModel.shared.logger
        let function = request.mode == .save ? "beginSavePanel" : "beginOpenPanel"
        guard WinUIApplication.shared.hasStarted else {
            logger.log("\(function): call it while the application runs (from didFinishLaunching on)", .error)
            Task { @MainActor in panel.finish(nil) }
            return panel
        }
        let filters = request.filters
        let names = CStrings(filters.map(\.name))
        let patterns = CStrings(filters.map(\.pattern))
        let context = Unmanaged.passRetained(panel).toOpaque()
        let task = withExtendedLifetime((names, patterns)) {
            names.pointers.withUnsafeBufferPointer { nameBuffer in
                patterns.pointers.withUnsafeBufferPointer { patternBuffer in
                    actionUIWinUIFileDialogBegin(request.dialogKind, request.multiple, request.title, request.acceptLabel,
                                                 request.initialFolder, request.initialName, nameBuffer.baseAddress,
                                                 patternBuffer.baseAddress, Int32(filters.count),
                                                 request.mode == .save ? request.extensions.first : nil,
                                                 request.strictTypes, fileDialogAnswered, context)
                }
            }
        }
        guard let task else {
            Unmanaged<FilePanel>.fromOpaque(context).release()
            logger.log("\(function): \(WinUIError.last("showing the file dialog"))", .error)
            Task { @MainActor in panel.finish(nil) }
            return panel
        }
        panel.task = task
        begun.append(panel)
        return panel
    }

    /// A begun dialog's answer, on the UI thread, once: the context holds its panel (retained by
    /// beginFilePanel for the dialog).
    private static let fileDialogAnswered: ActionUIWinUIFileDialogCompletion = { context, chosen, failure in
        guard let context else { return }
        let panel = Unmanaged<FilePanel>.fromOpaque(context).takeRetainedValue()
        let text = chosen.map { String(cString: $0) }
        let problem = failure.map { String(cString: $0) }
        MainActor.assumeIsolated {
            if let problem {
                let function = panel.request.mode == .save ? "beginSavePanel" : "beginOpenPanel"
                ActionUIModel.shared.logger.log("\(function): showing the file dialog: \(problem)", .error)
            }
            panel.finish(text.flatMap { panel.request.paths(chosen: $0) })
        }
    }

    /// The JSON's top-level object; empty for nil or anything else.
    nonisolated static func dictionary(_ json: String?) -> [String: Any] {
        guard let json, let parsed = try? ActionUIJSON.value(from: json) as? [String: Any] else { return [:] }
        return parsed
    }

    /// The alerts and file panels over `window` answer nil: it is closing.
    static func windowClosing(_ window: WinUIObject) {
        for alert in open where alert.window === window {
            alert.dismiss()
        }
        actionUIWinUIFileDialogsClose(window.pointer)
    }

    /// Every alert and file panel waiting answers nil: the application is terminating.
    static func dismissAll() {
        for alert in open {
            alert.dismiss()
        }
        actionUIWinUIFileDialogsClose(nil)
        for panel in begun {
            panel.cancel()
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

    /// The chosen paths, or nil when the panel was canceled (or could not be shown: logged).
    static func runFilePanel(_ request: FilePanelRequest) -> [String]? {
        let logger = ActionUIModel.shared.logger
        let function = request.mode == .save ? "actionUIAppRunSavePanel" : "actionUIAppRunOpenPanel"
        guard WinUIApplication.shared.hasStarted else {
            logger.log("\(function): call it while the application runs (from didFinishLaunching on)", .error)
            return nil
        }
        let owner = WinUIApplication.shared.panelOwner()?.window
        let filters = request.filters
        let names = CStrings(filters.map(\.name))
        let patterns = CStrings(filters.map(\.pattern))
        var chosen: UnsafeMutablePointer<CChar>?
        let shown = withExtendedLifetime((names, patterns)) {
            names.pointers.withUnsafeBufferPointer { nameBuffer in
                patterns.pointers.withUnsafeBufferPointer { patternBuffer in
                    actionUIWinUIFileDialogRun(owner?.pointer, request.dialogKind, request.multiple, request.title,
                                               request.acceptLabel, request.initialFolder, request.initialName,
                                               nameBuffer.baseAddress, patternBuffer.baseAddress, Int32(filters.count),
                                               request.mode == .save ? request.extensions.first : nil, request.strictTypes,
                                               &chosen)
                }
            }
        }
        guard shown else {
            logger.log("\(function): \(WinUIError.last("showing the file dialog"))", .error)
            return nil
        }
        guard let chosen else { return nil }
        defer { actionUIWinUIFreeString(chosen) }
        return request.paths(chosen: String(cString: chosen))
    }

    /// The alert over the window `content` is in; nil when it cannot be shown there (no error logged:
    /// the caller tries a window of the alert's own).
    private static func show(_ request: AlertRequest, over content: WinUIObject, for alert: OpenAlert) -> WinUIObject? {
        let titles = CStrings(request.buttons)
        let context = Unmanaged.passUnretained(alert).toOpaque()
        let dialog = withExtendedLifetime(titles) {
            titles.pointers.withUnsafeBufferPointer { buffer in
                actionUIWinUIAlertShow(content.pointer, request.title, request.message, buffer.baseAddress,
                                       Int32(buffer.count), Int32(request.escapeButton ?? -1), 0, alertAnswered, context)
            }
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
