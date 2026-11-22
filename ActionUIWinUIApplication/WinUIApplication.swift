// ActionUIWinUIApplication/WinUIApplication.swift
/*
 The application on Windows: WinUI's Application, its windows and its lifecycle, which the
 actionUIApp* C functions drive (on Apple ActionUIAppKitApplication does this with NSApplication, on
 Linux AdwaitaApplication with an AdwApplication). Public, for them and for Swift programs.

 - run() attaches the Windows App SDK runtime, starts WinUI on the calling thread (with
   MainLoopBridge, so main-actor work runs) and returns when the application ends. It runs once in a
   process (WinUI starts once); a second run is refused and logged.
 - Windows presented before the application has started wait, and appear when it starts, after the
   willFinishLaunching handler and before didFinishLaunching, as on Linux.
 - A window holds an ActionUI document, its root element's box as the window's content. It opens at
   the document's size (WinUIWindow.openingSize: its measured size, no wider than 900 unless its
   minimum needs more, at least 418 tall when it grows vertically, 480 x 320 when too small to say).
   Its title is the one given, else the application's name.
 - A file's document is loaded as from that file, so it is the app's own only inside the app's
   resources (JSONContentOrigin); JSON the host passes is the host's own. A document that cannot be
   loaded is logged and shown as its error text in the window, as on Apple.
 - Closing a window (by the user or closeWindow) fires windowWillClose, then its model is removed.
   The user closing the last window ends the application; the host closing it (closeWindow) does not,
   so a host can close one window before opening the next, as on Apple and Linux. Presenting a window
   again under the same UUID replaces it, with no windowWillClose, as on Linux.
 - terminate() asks shouldTerminate, then closes every window (each firing windowWillClose) and ends
   the run; willTerminate fires as the run ends.

 Not yet: shouldTerminate is not asked when the user closes the last window (only by terminate);
 the become and resign active handlers are kept but not fired; the icon is kept but not
 shown; documents at an http or https address; the menu bar, the alert and the file panels; the
 remote server; window sizes are not limited to the screen.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
import CWinUI
import Dispatch

@MainActor
public final class WinUIApplication {
    public static let shared = WinUIApplication()

    /// The host's lifecycle handlers (actionUIAppSet...Handler).
    public struct Handlers {
        public var willFinishLaunching: (() -> Void)?
        public var didFinishLaunching: (() -> Void)?
        public var willBecomeActive: (() -> Void)?
        public var didBecomeActive: (() -> Void)?
        public var willResignActive: (() -> Void)?
        public var didResignActive: (() -> Void)?
        public var willTerminate: (() -> Void)?
        public var shouldTerminate: (() -> Bool)?
        public var windowWillClose: ((String) -> Void)?
        public var windowWillPresent: ((String) -> Void)?

        public init() {}
    }

    public var handlers = Handlers()
    /// The application's name: a window's title when none is given.
    public var name: String?
    /// The windows' icon (a path): kept, not shown yet.
    public var icon: String?
    /// The folder of the app's resources (ActionUIResourceFolder): set before the first window loads,
    /// as the configuration it is part of is fixed then.
    public var resourceFolder: String? {
        get { ActionUIResourceFolder.path }
        set { ActionUIResourceFolder.path = newValue }
    }

    /// One window on screen: its WinUI window and its document's tree.
    private final class Shown {
        let window: WinUIObject
        let tree: WinUIWindow

        init(window: WinUIObject, tree: WinUIWindow) {
            self.window = window
            self.tree = tree
        }
    }

    private var windows: [String: Shown] = [:]
    /// Windows asked for before the application started, presented when it starts; closeWindow drops
    /// one.
    private var pending: [(windowUUID: String, present: () -> Void)] = []
    /// The closed windows whose models go after this turn of the main loop (closed); presenting the
    /// UUID again takes it out, as its model is in use again.
    private var queuedModelRemovals: Set<String> = []
    /// The windows closeWindow is closing: their closing does not end the application.
    private var closingByHost: Set<String> = []
    private var isRunning = false
    private var hasStarted = false
    /// Whether a run has begun in this process: WinUI's Application starts once.
    private var hasRun = false

    private init() {}

    // MARK: Running

    /// Runs the application on the calling thread (the main thread) until it ends; false when it could
    /// not start (logged), or when it is already running.
    @discardableResult
    public func run() -> Bool {
        let logger = ActionUIModel.shared.logger
        guard !isRunning else {
            logger.log("WinUIApplication: run() while the application runs; refused", .error)
            return false
        }
        guard !hasRun else {
            logger.log("WinUIApplication: run() after the application ended; refused (WinUI starts once in a process)", .error)
            return false
        }
        // A host that runs its own WinUI application fills its own windows (actionUILoadIntoHostWindow...):
        // a process has one Application, which is the host's.
        guard !actionUIWinUIApplicationExists() else {
            logger.log("WinUIApplication: run() while the host's own WinUI application runs; refused (fill the host's windows instead)", .error)
            return false
        }
        guard actionUIWinUIInitialize() else {
            logger.log("WinUIApplication: \(WinUIError.last("attaching the Windows App SDK runtime"))", .error)
            return false
        }
        isRunning = true
        hasRun = true
        let ran = actionUIWinUIRun({ _ in
            MainActor.assumeIsolated { WinUIApplication.shared.launched() }
        }, nil)
        if !ran {
            logger.log("WinUIApplication: \(WinUIError.last("running WinUI"))", .error)
        }
        handlers.willTerminate?()
        for (uuid, shown) in windows {
            shown.tree.detach()
            ActionUIModel.shared.removeWindow(uuid)
        }
        windows = [:]
        // The main queue does not run after the run: the removals still queued happen here.
        for uuid in queuedModelRemovals {
            ActionUIModel.shared.removeWindow(uuid)
        }
        queuedModelRemovals = []
        closingByHost = []
        pending = []
        hasStarted = false
        isRunning = false
        // The shim dropped its watch of the main queue as the run ended: a next run installs it again.
        MainLoopBridge.runEnded()
        actionUIWinUIShutdown()
        return ran
    }

    /// WinUI is ready: main-actor work starts to run, the waiting windows appear.
    private func launched() {
        MainLoopBridge.install()
        handlers.willFinishLaunching?()
        hasStarted = true
        let waiting = pending
        pending = []
        for window in waiting {
            window.present()
        }
        handlers.didFinishLaunching?()
    }

    /// Ends the application, unless the shouldTerminate handler says no: every window closes (each
    /// firing windowWillClose), then the run ends. Before the run, nothing.
    public func terminate() {
        guard isRunning else { return }
        if let shouldTerminate = handlers.shouldTerminate, !shouldTerminate() {
            return
        }
        for uuid in Array(windows.keys) {
            closeWindow(uuid)
        }
        actionUIWinUIQuit()
    }

    // MARK: Windows

    /// Loads the document at `url` (a file URL or a path) into a new window showing `windowUUID`, titled
    /// `title`, else the file's name.
    public func presentWindow(url text: String, windowUUID: String, title: String?) {
        // A file URL, else a path; an address of another scheme (a one-letter scheme is a drive,
        // "C:\docs\a.json", so a path) is not loaded yet.
        let fileURL: URL?
        if let parsed = URL(string: text), let scheme = parsed.scheme, scheme.count > 1 {
            fileURL = parsed.isFileURL ? parsed : nil
        } else {
            fileURL = URL(fileURLWithPath: text)
        }
        guard let fileURL else {
            present(windowUUID: windowUUID, title: title ?? text) {
                throw ActionUIError("\(text) cannot be loaded: only files are loaded on Windows yet")
            }
            return
        }
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        present(windowUUID: windowUUID, title: title ?? fileName) {
            try WinUIWindow.load(file: fileURL, windowUUID: windowUUID)
        }
    }

    /// Loads the document in `json` (the host's own) into a new window showing `windowUUID`, titled
    /// `title`, else the application's name.
    public func presentWindow(json: String, windowUUID: String, title: String?) {
        present(windowUUID: windowUUID, title: title) {
            try WinUIWindow.load(json: json, windowUUID: windowUUID)
        }
    }

    /// Presents the tree `load` makes in a new window (or the error it throws, as text), at once when the
    /// application has started, else when it starts. A window already showing `windowUUID` is
    /// replaced, with no windowWillClose (as on Linux).
    private func present(windowUUID: String, title: String?, _ load: @escaping @MainActor () throws -> WinUIWindow) {
        guard hasStarted else {
            pending.append((windowUUID, { [weak self] in self?.present(windowUUID: windowUUID, title: title, load) }))
            return
        }
        let logger = ActionUIModel.shared.logger
        // The replaced window's tree leaves the model before the new document loads into it (the
        // same WindowModel); its WinUI window closes only once the new one is up, so the application
        // never has no window in between, which would end it. Out of `windows`, its Closed does nothing.
        let replaced = windows.removeValue(forKey: windowUUID)
        replaced?.tree.detach()
        defer {
            if let replaced, !actionUIWinUIWindowClose(replaced.window.pointer) {
                logger.log("WinUIApplication: \(WinUIError.last("closing the replaced window for \(windowUUID)"))", .error)
            }
        }
        // Its model is in use again.
        queuedModelRemovals.remove(windowUUID)
        handlers.windowWillPresent?(windowUUID)
        let tree: WinUIWindow
        do {
            tree = try load()
        } catch {
            logger.log("WinUIApplication: window \(windowUUID) could not be loaded: \(error)", .error)
            let message = String(describing: error)
            let errorJSON = (try? ActionUIJSON.string(from: ["type": "Text", "id": 1,
                                                             "properties": ["text": message, "padding": 20]] as [String: Any]))
                ?? #"{"type": "Text", "id": 1, "properties": {"text": "The document could not be loaded"}}"#
            guard let errorTree = try? WinUIWindow.load(json: errorJSON, windowUUID: windowUUID) else { return }
            tree = errorTree
        }
        guard let content = tree.view, let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
            logger.log("WinUIApplication: \(WinUIError.last("making the window for \(windowUUID)"))", .error)
            tree.detach()
            ActionUIModel.shared.removeWindow(windowUUID)
            return
        }
        // Measured once the content is in the window, where the controls have their styles.
        guard actionUIWinUIWindowSetTitle(window.pointer, title ?? name ?? "ActionUI"),
              actionUIWinUIWindowSetContent(window.pointer, content.pointer),
              case let size = tree.openingSize(),
              actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height) else {
            logger.log("WinUIApplication: \(WinUIError.last("setting up the window for \(windowUUID)"))", .error)
            tree.detach()
            ActionUIModel.shared.removeWindow(windowUUID)
            return
        }
        let shown = Shown(window: window, tree: tree)
        windows[windowUUID] = shown
        WinUIEvents.connect(window, actionUIWinUIWindowOnClosed, "a window's closing") { [weak self, weak shown] in
            guard let self, let shown else { return }
            self.closed(windowUUID, shown)
        }
        if !actionUIWinUIWindowActivate(window.pointer) {
            logger.log("WinUIApplication: \(WinUIError.last("showing the window for \(windowUUID)"))", .error)
        }
    }

    /// Closes the window showing `windowUUID` (its windowWillClose handler fires as it closes).
    public func closeWindow(_ windowUUID: String) {
        // A window still waiting for the start is dropped, as on Linux.
        pending.removeAll { $0.windowUUID == windowUUID }
        guard let shown = windows[windowUUID] else { return }
        closingByHost.insert(windowUUID)
        if !actionUIWinUIWindowClose(shown.window.pointer) {
            ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("closing the window for \(windowUUID)"))", .error)
            closed(windowUUID, shown)
        }
    }

    /// A window closed: its handler fires (its values still readable), then its model is removed; with
    /// no window left after the user closed it, the application ends.
    private func closed(_ windowUUID: String, _ shown: Shown) {
        // Only the window still showing the UUID: a replaced one's closing is its own.
        guard windows[windowUUID] === shown else { return }
        let byHost = closingByHost.remove(windowUUID) != nil
        // Out of `windows` before the handler: a closeWindow of the UUID from it finds nothing to
        // close again, and a present of it opens a new window.
        windows[windowUUID] = nil
        handlers.windowWillClose?(windowUUID)
        shown.tree.detach()
        // The model goes after the handler and after the disappear actions the detach queued on the
        // main queue (NodeAppearance), which read the values too, as on Linux; not when a window under
        // the UUID is on screen again by then.
        queuedModelRemovals.insert(windowUUID)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let application = WinUIApplication.shared
                guard application.queuedModelRemovals.remove(windowUUID) != nil, application.windows[windowUUID] == nil else { return }
                ActionUIModel.shared.removeWindow(windowUUID)
            }
        }
        if windows.isEmpty, isRunning, !byHost {
            actionUIWinUIQuit()
        }
    }
}
