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
 - A window holds a UI from ActionUI JSON, its root element's box as the window's content. It opens at
   the UI's size (WinUIWindow.openingSize: its measured size, no wider than 900 unless its
   minimum needs more, at least 418 tall when it grows vertically, 480 x 320 when too small to say).
   Its title is the one given, else the application's name.
 - A file's ActionUI JSON is loaded as from that file, so it is the app's own only inside the app's
   resources (JSONContentOrigin); JSON the host passes is the host's own. ActionUI JSON at an http or https
   address loads first (RemoteFetch: the cap on ActionUI JSON, 120 seconds, redirects only to http and
   https) and its window appears once it has, judged by the address it finally came from, as on Linux;
   closing the UUID meanwhile drops it, presenting it again replaces the load. ActionUI JSON that cannot
   be loaded is logged and shown as its error text in the window, as on Apple.
 - Closing a window (by the user or closeWindow) fires windowWillClose, then its model is removed.
   The user closing the last window (none other loading from a server) asks shouldTerminate (false
   keeps the window open), then ends the application; the host closing it (closeWindow) does not, so a host can close one window before
   opening the next, as on Apple and Linux. Presenting a window
   again under the same UUID replaces it, with no windowWillClose, as on Linux.
 - renderOffscreen builds a prepared window as presentWindow(prepared:) does and draws it where the user
   never sees it (OffscreenWindow).
 - terminate() asks shouldTerminate, then closes every window (each firing windowWillClose) and ends
   the run; willTerminate fires as the run ends.

 - An alert or a file panel (AppPanels) opens over the active window, else the one presented last, and
   returns nil when that window closes under it or the application terminates.

 - A WindowGroup at the root of a window's ActionUI JSON is read as on Linux (WinUIWindow): its title is
   the window's when the host gives none, and its commands, when the JSON is the app's own, join the menu
   bar with its first window and leave with its last.
 - Commands the host loads (loadMenuBar) show in a menu bar across the top of every window, made for
   each window (AppCommands on WinUI); a window presented after the load opens that much taller, so its
   content keeps its size. Exit terminates (asking shouldTerminate), About shows the application's name
   in an alert.

 Not yet: the become and resign active handlers are kept but not fired; the icon is kept but not
 shown; a window that is already open when commands are first loaded keeps its size, so its content
 gives the bar its room; window sizes are not limited to the screen.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
import CWinUI
import Dispatch
import WinSDK

@MainActor
public final class WinUIApplication {
    public static let shared = WinUIApplication()

    /// Removes the current folder from the places Windows searches for a DLL loaded by name, for the whole
    /// process, so a file named like a DLL in the folder the program was started in is never loaded. Call
    /// it first in a program's start; ActionUI never changes the process's DLL search on its own.
    @discardableResult
    public static func removeCurrentFolderFromDLLSearch() -> Bool {
        actionUIWinUIRemoveCurrentFolderFromDLLSearch()
    }

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
    /// For a host with work to do when no window is open, such as a server: the application goes on when
    /// the user closes the last window, until terminate. As on Linux.
    public var keepsRunningWithoutWindows = false

    /// Whether windows can show here: the process is in a window station the user sees (not a service's or
    /// a remote shell's, where WinUI's windows have no desktop).
    public var hasDisplay: Bool {
        guard let station = GetProcessWindowStation() else { return false }
        var flags = USEROBJECTFLAGS()
        var needed: DWORD = 0
        guard GetUserObjectInformationW(UnsafeMutableRawPointer(station), Int32(UOI_FLAGS), &flags,
                                        DWORD(MemoryLayout<USEROBJECTFLAGS>.size), &needed) else { return false }
        return flags.dwFlags & DWORD(WSF_VISIBLE) != 0
    }

    /// How a prepared window shows (presentWindow(prepared:)), as on Linux.
    public struct WindowOptions: Sendable {
        /// A line shown first in the title bar, before the window's title, whatever its JSON does; nil or
        /// empty: none.
        public var subtitle: String?
        /// The size of the window's content; nil opens it at its content's own size. A width or height of
        /// zero or less keeps the content's own size for that side.
        public var contentSize: (width: Int, height: Int)?
        /// Whether the user can resize the window.
        public var isResizable = true

        public init(subtitle: String? = nil, contentSize: (width: Int, height: Int)? = nil, isResizable: Bool = true) {
            self.subtitle = subtitle
            self.contentSize = contentSize
            self.isResizable = isResizable
        }
    }

    /// ActionUI JSON loaded into its window's model and not shown yet: what loaded it said is in `error`
    /// (nil when it loaded), so a host can refuse it before any WinUI object is made. Shows once.
    public final class PreparedWindow {
        public let windowUUID: String
        public let error: String?
        /// The error `error` says, shown in the window as a load error is (not its text again).
        fileprivate let failure: (any Error)?
        var isUsed = false

        fileprivate init(windowUUID: String, error: String?, failure: (any Error)?) {
            self.windowUUID = windowUUID
            self.error = error
            self.failure = failure
        }
    }
    /// The folder of the app's resources (ActionUIResourceFolder): set before the first window loads,
    /// as the configuration it is part of is fixed then.
    public var resourceFolder: String? {
        get { ActionUIResourceFolder.path }
        set { ActionUIResourceFolder.path = newValue }
    }

    /// One window on screen: its WinUI window and the tree of its ActionUI JSON.
    private final class Shown {
        let window: WinUIObject
        let tree: WinUIWindow
        /// False when the window shows the error its ActionUI JSON could not be loaded with.
        let showsContent: Bool
        /// When it was presented, among the windows: the latest is the largest.
        let order: Int
        /// The WindowGroup whose commands this window brought to the menu bar, if any: they go when the
        /// group's last window does.
        var commandsKey: String?

        init(window: WinUIObject, tree: WinUIWindow, showsContent: Bool, order: Int) {
            self.window = window
            self.tree = tree
            self.showsContent = showsContent
            self.order = order
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
    /// The windows loading from a server, by UUID: the load's number, so a newer load, or a close,
    /// makes an older one's result go unused.
    private var loading: [String: Int] = [:]
    private var loadCount = 0
    private var presentCount = 0
    private var isRunning = false
    /// From just before the waiting windows appear (after willFinishLaunching) until the run ends.
    private(set) var hasStarted = false
    /// Whether a run has begun in this process: WinUI's Application starts once.
    private var hasRun = false

    private init() {
        let commands = AppCommands.shared
        commands.appName = { [weak self] in self?.name ?? ProcessInfo.processInfo.processName }
        commands.exitHandler = { [weak self] in self?.terminate() }
        commands.aboutHandler = { name in
            // After the click has been handled: the alert waits for its answer. Posted to the UI thread's
            // own queue, not DispatchQueue.main: inside a main-queue block libdispatch runs no other
            // main-queue work (its drain does not re-enter), so main-actor work and other threads' calls
            // would wait until the alert is answered.
            let box = Unmanaged.passRetained(AboutRequest(name)).toOpaque()
            if !actionUIWinUIPostDelayed(0, showAbout, box) {
                Unmanaged<AboutRequest>.fromOpaque(box).release()
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("showing About"))", .error)
            }
        }
        commands.changed = { [weak self] in self?.showMenuBars() }
    }

    // MARK: Commands

    /// Adds the CommandMenu and CommandGroup elements in `json` (an array of them) to the menu bar every
    /// window shows; nil only makes the bar show. False, logged, for JSON that is not such an array.
    @discardableResult
    public func loadMenuBar(json: String?) -> Bool {
        AppCommands.shared.load(json: json)
    }

    /// A window that has left `windows` (or never got in): its WindowGroup's commands (under `key`) leave
    /// the menu bar with the group's last window.
    private func releaseCommands(_ key: String?) {
        guard let key, !windows.values.contains(where: { $0.commandsKey == key }) else { return }
        AppCommands.shared.removeWindowGroup(key)
    }

    /// Gives each window a menu bar made anew from the commands (AppCommands).
    private func showMenuBars() {
        for (windowUUID, shown) in windows {
            let bar = AppCommands.shared.makeMenuBar(windowUUID: windowUUID)
            if !actionUIWinUIWindowSetMenuBar(shown.window.pointer, bar?.pointer) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("showing the menu bar of \(windowUUID)"))", .error)
            }
        }
    }

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
        loading = [:]
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
        // An alert waiting for an answer returns nil, as the process ends with it up on macOS.
        AppPanels.dismissAll()
        for uuid in Array(windows.keys) {
            closeWindow(uuid)
        }
        actionUIWinUIQuit()
    }

    // MARK: Windows

    /// Loads the ActionUI JSON at `url` (a file URL or a path) into a new window showing `windowUUID`, titled
    /// `title`, else the file's name.
    public func presentWindow(url text: String, windowUUID: String, title: String?) {
        // A file URL, an http or https address, else a path (a one-letter scheme is a drive,
        // "C:\docs\a.json", so a path); another scheme is not loaded.
        let fileURL: URL?
        if let parsed = URL(string: text), let scheme = parsed.scheme?.lowercased(), scheme.count > 1 {
            if scheme == "http" || scheme == "https" {
                presentRemote(parsed, windowUUID: windowUUID, title: title)
                return
            }
            fileURL = parsed.isFileURL ? parsed : nil
        } else {
            fileURL = URL(fileURLWithPath: text)
        }
        guard let fileURL else {
            present(windowUUID: windowUUID, title: title ?? text) {
                throw ActionUIError("only files and http and https addresses are loaded (\(text))")
            }
            return
        }
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        present(windowUUID: windowUUID, title: title, defaultTitle: fileName, fileName: fileURL.lastPathComponent) {
            try WinUIWindow.load(file: fileURL, windowUUID: windowUUID, readsWindowGroup: true)
        }
    }

    /// Fetches the ActionUI JSON at the http or https `url`, then presents it in a new window showing
    /// `windowUUID` (titled `title`, else the address's last part), judged by the address it finally
    /// came from; before the start it waits, as other windows do.
    private func presentRemote(_ url: URL, windowUUID: String, title: String?) {
        guard hasStarted else {
            pending.append((windowUUID, { [weak self] in self?.presentRemote(url, windowUUID: windowUUID, title: title) }))
            return
        }
        loadCount += 1
        let number = loadCount
        loading[windowUUID] = number
        // "https://example.com/" has the last part "/": the whole address then, as for none.
        let lastPart = url.deletingPathExtension().lastPathComponent
        let addressTitle = lastPart.isEmpty || lastPart == "/" ? url.absoluteString : lastPart
        let started = RemoteFetch.start(url.absoluteString) { [weak self] data, finalURL, failure in
            // Only the newest load of a UUID still wanted (not closed, not presented again since).
            guard let self, self.loading[windowUUID] == number else { return }
            self.loading[windowUUID] = nil
            self.present(windowUUID: windowUUID, title: title, defaultTitle: addressTitle) {
                guard let data else {
                    throw ActionUIError("\(url.absoluteString) could not be loaded: \(failure ?? "the request failed")")
                }
                return try WinUIWindow.load(data: data, from: url, finalURL: finalURL, windowUUID: windowUUID,
                                            readsWindowGroup: true)
            }
        }
        if !started {
            loading[windowUUID] = nil
            let why = WinUIError.last("fetching \(url.absoluteString)")
            present(windowUUID: windowUUID, title: title, defaultTitle: addressTitle) { throw ActionUIError("\(why)") }
        }
    }

    /// Loads `json` into the model of `windowUUID` without showing it: no WinUI object is made, so nothing
    /// in it starts (a WebView's page, an image's fetch). The JSON is the host's. A failed load is logged as
    /// an error, as on Linux, so a host that collects the log sees it.
    public func prepareWindow(json: Data, windowUUID: String) -> PreparedWindow {
        // Its model is in use again: a removal queued by an earlier window's closing must not take it.
        queuedModelRemovals.remove(windowUUID)
        do {
            try WinUIWindow.loadModel(json: json, windowUUID: windowUUID)
            return PreparedWindow(windowUUID: windowUUID, error: nil, failure: nil)
        } catch {
            ActionUIModel.shared.logger.log("Window \(windowUUID): the JSON could not be loaded: \(error)", .error)
            return PreparedWindow(windowUUID: windowUUID, error: WinUIWindow.loadErrorText(error, fileName: nil),
                                  failure: error)
        }
    }

    /// Shows a prepared window, titled `title` (else the application's name) with `options`.
    public func presentWindow(prepared: PreparedWindow, title: String?, options: WindowOptions = WindowOptions()) {
        guard !prepared.isUsed else {
            ActionUIModel.shared.logger.log("Window \(prepared.windowUUID): a prepared window shows once; prepare it again", .error)
            return
        }
        prepared.isUsed = true
        let failure = prepared.failure
        let windowUUID = prepared.windowUUID
        present(windowUUID: windowUUID, title: title, options: options) {
            if let failure {
                throw failure
            }
            return try WinUIWindow.showing(windowUUID: windowUUID)
        }
    }

    /// Loads the ActionUI JSON in `json` (the host's own) into a new window showing `windowUUID`, titled
    /// `title`, else the application's name.
    public func presentWindow(json: String, windowUUID: String, title: String?) {
        present(windowUUID: windowUUID, title: title) {
            try WinUIWindow.load(json: json, windowUUID: windowUUID, readsWindowGroup: true)
        }
    }

    /// Presents the tree `load` makes in a new window (or the error it throws, as text), at once when the
    /// application has started, else when it starts. A window already showing `windowUUID` is
    /// replaced, with no windowWillClose (as on Linux).
    private func present(windowUUID: String, title: String?, defaultTitle: String? = nil, fileName: String? = nil,
                         options: WindowOptions? = nil, _ load: @escaping @MainActor () throws -> WinUIWindow) {
        guard hasStarted else {
            pending.append((windowUUID, { [weak self] in
                self?.present(windowUUID: windowUUID, title: title, defaultTitle: defaultTitle, fileName: fileName,
                              options: options, load)
            }))
            return
        }
        // A newer presentation replaces a load still under way.
        loading[windowUUID] = nil
        let logger = ActionUIModel.shared.logger
        // The replaced window's tree leaves the model before the new ActionUI JSON loads into it (the
        // same WindowModel); its WinUI window closes only once the new one is up, so the application
        // never has no window in between, which would end it. Out of `windows`, its Closed does nothing.
        let replaced = windows.removeValue(forKey: windowUUID)
        replaced?.tree.detach()
        releaseCommands(replaced?.commandsKey)
        defer {
            if let replaced {
                AppPanels.windowClosing(replaced.window)
            }
            if let replaced, !actionUIWinUIWindowClose(replaced.window.pointer) {
                logger.log("WinUIApplication: \(WinUIError.last("closing the replaced window for \(windowUUID)"))", .error)
            }
        }
        // Its model is in use again.
        queuedModelRemovals.remove(windowUUID)
        handlers.windowWillPresent?(windowUUID)
        let tree: WinUIWindow
        var loaded = true
        do {
            tree = try load()
        } catch {
            loaded = false
            logger.log("WinUIApplication: window \(windowUUID) could not be loaded: \(error)", .error)
            guard let errorTree = WinUIWindow.loadError(error, fileName: fileName, windowUUID: windowUUID) else { return }
            tree = errorTree
        }
        guard let content = tree.view, let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
            logger.log("WinUIApplication: \(WinUIError.last("making the window for \(windowUUID)"))", .error)
            tree.detach()
            ActionUIModel.shared.removeWindow(windowUUID)
            return
        }
        // A WindowGroup's commands join the menu bar before the window's bar is made (once per group).
        let commandsKey = loaded ? tree.groupCommands.map { commands -> String in
            AppCommands.shared.load(json: commands.json, once: commands.key)
            return commands.key
        } : nil
        // The menu bar, when there are commands, above the content: the window opens that much taller, so
        // the content keeps its size.
        let bar = AppCommands.shared.makeMenuBar(windowUUID: windowUUID)
        // Measured once the content is in the window, where the controls have their styles.
        // A subtitle (a prepared window's) shows before the title: Windows' title bar has one line and cuts
        // a long one at its end, so a long title cannot push the subtitle out of view or come first.
        let shownTitle = title ?? tree.groupTitle ?? defaultTitle ?? name ?? "ActionUI"
        let fullTitle = options?.subtitle.flatMap { $0.isEmpty ? nil : "\($0) - \(shownTitle)" } ?? shownTitle
        // The options' content size, side by side, else the content's own.
        var size = tree.openingSize()
        if let wanted = options?.contentSize {
            if wanted.width > 0 { size.width = Double(wanted.width) }
            if wanted.height > 0 { size.height = Double(wanted.height) }
        }
        guard actionUIWinUIWindowSetTitle(window.pointer, fullTitle),
              actionUIWinUIWindowSetContent(window.pointer, content.pointer),
              actionUIWinUIWindowSetMenuBar(window.pointer, bar?.pointer),
              case let barHeight = actionUIWinUIWindowMenuBarHeight(window.pointer), barHeight >= 0,
              actionUIWinUIWindowSetContentSize(window.pointer, size.width, size.height + barHeight) else {
            logger.log("WinUIApplication: \(WinUIError.last("setting up the window for \(windowUUID)"))", .error)
            tree.detach()
            ActionUIModel.shared.removeWindow(windowUUID)
            // Its group's commands, loaded above, leave too: no window would ever release them.
            releaseCommands(commandsKey)
            return
        }
        if options?.isResizable == false, !actionUIWinUIWindowSetResizable(window.pointer, false) {
            logger.log("WinUIApplication: \(WinUIError.last("fixing the size of \(windowUUID)"))", .warning)
        }
        presentCount += 1
        let shown = Shown(window: window, tree: tree, showsContent: loaded, order: presentCount)
        shown.commandsKey = commandsKey
        windows[windowUUID] = shown
        WinUIEvents.connect(window, actionUIWinUIWindowOnClosed, "a window's closing") { [weak self, weak shown] in
            guard let self, let shown else { return }
            self.closed(windowUUID, shown)
        }
        // The user closing the last window asks shouldTerminate first, as on Apple and Linux.
        let decider = Unmanaged.passRetained(CloseBox { [weak self] in
            self?.userMayClose(windowUUID) ?? true
        }).toOpaque()
        if !actionUIWinUIWindowOnClosing(window.pointer, decideClose, decider, releaseClose) {
            logger.log("WinUIApplication: \(WinUIError.last("watching the user's closing of \(windowUUID)"))", .error)
        }
        if !actionUIWinUIWindowActivate(window.pointer) {
            logger.log("WinUIApplication: \(WinUIError.last("showing the window for \(windowUUID)"))", .error)
        }
    }

    /// Whether the user may close the window showing `windowUUID`: when it is the last one (no other
    /// window loading from a server either, as on Linux), the shouldTerminate handler decides, as
    /// closing it ends the application.
    private func userMayClose(_ windowUUID: String) -> Bool {
        // The host's own closing (closeWindow, terminate) never asks, should WinUI report it as the user's.
        guard !closingByHost.contains(windowUUID), windows.count == 1, windows[windowUUID] != nil,
              loading.keys.allSatisfy({ $0 == windowUUID }),
              let shouldTerminate = handlers.shouldTerminate else { return true }
        return shouldTerminate()
    }

    /// The window an alert or a file panel opens over, with its content (where the alert is shown): the
    /// active window, else the one presented last; nil when no window is open.
    func panelOwner() -> (window: WinUIObject, content: WinUIObject)? {
        let shown = windows.values.first { actionUIWinUIWindowIsActive($0.window.pointer) }
            ?? windows.values.max { $0.order < $1.order }
        guard let shown, let content = shown.tree.view else { return nil }
        return (shown.window, content)
    }

    /// Whether the window showing `windowUUID` shows its ActionUI JSON (false: it shows the error the
    /// ActionUI JSON could not be loaded with, or there is no such window), as on Linux.
    public func showsContent(_ windowUUID: String) -> Bool {
        windows[windowUUID]?.showsContent ?? false
    }

    /// Saves the window showing `windowUUID` to a PNG at `path` as savePNG does, scaled down so that neither
    /// side is larger than `maxPixels`. Asynchronous; `completion` says whether the file was written.
    public func capturePNG(windowUUID: String, path: String, maxPixels: Int,
                           completion: @escaping @MainActor (Bool) -> Void) {
        guard let shown = windows[windowUUID] else {
            completion(false)
            return
        }
        let box = Unmanaged.passRetained(PNGCompletion(completion)).toOpaque()
        if !actionUIWinUIWindowRenderToPNGWithin(shown.window.pointer, path, UInt32(clamping: max(0, maxPixels)), pngRendered, box) {
            ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("capturing \(path)"))", .error)
            Unmanaged<PNGCompletion>.fromOpaque(box).release()
            completion(false)
        }
    }

    /// Saves what the window showing `windowUUID` shows below its title bar, popups open over it
    /// included, as a PNG file at `path`, drawn by WinUI itself (no screen capture). Asynchronous on
    /// Windows: `completion` runs on the main thread with whether the file was written; false at once
    /// when there is no such window.
    public func savePNG(windowUUID: String, path: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard let shown = windows[windowUUID] else {
            completion(false)
            return
        }
        let box = Unmanaged.passRetained(PNGCompletion(completion)).toOpaque()
        if !actionUIWinUIWindowRenderToPNG(shown.window.pointer, path, pngRendered, box) {
            ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("saving \(path)"))", .error)
            Unmanaged<PNGCompletion>.fromOpaque(box).release()
            completion(false)
        }
    }

    /// Closes the window showing `windowUUID` (its windowWillClose handler fires as it closes).
    public func closeWindow(_ windowUUID: String) {
        // A window still waiting for the start, or for its ActionUI JSON from a server, is dropped, as on Linux.
        pending.removeAll { $0.windowUUID == windowUUID }
        loading[windowUUID] = nil
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
        // An alert over it returns nil, as on Linux.
        AppPanels.windowClosing(shown.window)
        // Only the window still showing the UUID: a replaced one's closing is its own.
        guard windows[windowUUID] === shown else { return }
        let byHost = closingByHost.remove(windowUUID) != nil
        // Out of `windows` before the handler: a closeWindow of the UUID from it finds nothing to
        // close again, and a present of it opens a new window.
        windows[windowUUID] = nil
        // The UUID is closed: a load replacing its window is dropped, as on Linux.
        loading[windowUUID] = nil
        handlers.windowWillClose?(windowUUID)
        shown.tree.detach()
        releaseCommands(shown.commandsKey)
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
        // A window still loading from a server keeps it running: that window appears once loaded.
        if windows.isEmpty, loading.isEmpty, isRunning, !byHost, !keepsRunningWithoutWindows {
            actionUIWinUIQuit()
        }
    }
}

/// The decider of a window's closing by the user, held by the shim (actionUIWinUIWindowOnClosing).
@MainActor private final class CloseBox {
    let decide: @MainActor () -> Bool

    init(_ decide: @escaping @MainActor () -> Bool) {
        self.decide = decide
    }
}

/// The box behind the decider's context, taken before entering the main actor (the raw pointer may not
/// cross).
private func closeBox(_ context: UnsafeMutableRawPointer?) -> CloseBox? {
    context.map { Unmanaged<CloseBox>.fromOpaque($0).takeUnretainedValue() }
}

private let decideClose: ActionUIWinUIWindowCloseDecider = { context in
    let box = closeBox(context)
    return MainActor.assumeIsolated { box?.decide() ?? true }
}

// Gives back the reference passRetained took, once the shim lets go of the decider.
private let releaseClose: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<CloseBox>.fromOpaque(context).release()
}

/// The name the About alert shows, held by the shim until the UI thread runs showAbout.
@MainActor private final class AboutRequest {
    let name: String

    init(_ name: String) {
        self.name = name
    }
}

// The About item's alert: on the UI thread, once; gives back the box's reference.
private let showAbout: ActionUIWinUICallback = { context in
    guard let context else { return }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let name = Unmanaged<AboutRequest>.fromOpaque(pointer).takeRetainedValue().name
        let request = (try? ActionUIJSON.string(from: ["title": "About \(name)", "message": name, "buttons": ["OK"]])) ?? "{}"
        _ = AppPanels.runAlert(json: request)
    }
}

/// savePNG's completion, held by the shim until the PNG is written.
@MainActor final class PNGCompletion {
    let completion: @MainActor (Bool) -> Void

    init(_ completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
    }
}

// The shim's completion: on the UI thread, once; gives back the box's reference.
let pngRendered: ActionUIWinUICompletion = { context, succeeded in
    guard let context else { return }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<PNGCompletion>.fromOpaque(pointer).takeRetainedValue().completion(succeeded)
    }
}
