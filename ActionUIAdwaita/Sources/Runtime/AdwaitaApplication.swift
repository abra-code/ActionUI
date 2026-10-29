// Sources/Runtime/AdwaitaApplication.swift
/*
 The application on Linux: an AdwApplication, its windows and its lifecycle, which the
 actionUIApp* C functions drive (on Apple, ActionUIAppKitApplication does this with NSApplication).
 Public, for them and for Swift programs, which can use it directly.

 - run() starts GTK's main loop (with MainLoopBridge, so main-actor work runs) and returns when
   the application ends. It runs once at a time.
 - Windows presented before the application has started wait, and appear when it starts, after
   the willFinishLaunching handler and before didFinishLaunching, as the spike found GTK needs.
 - A window holds an ActionUI document: AdwApplicationWindow > AdwToolbarView (an AdwHeaderBar
   on top, with the title) > the root element's box. It opens at the document's ideal size (the
   root frame's ideal, else its content's natural size; 480 x 320 when that is under 10 x 10, as
   on Apple), no wider than 900 unless its minimum needs more (SwiftUI's WindowGroup opens 900
   wide), and never larger than the monitor: GTK's renderers fail on windows far larger than the
   screen. A document whose minimum is larger than the monitor scrolls.
 - A document that cannot be loaded is logged and shown as its error text in the window, as on
   Apple.
 - An http or https URL loads first (URLLoader, without blocking the main loop) and the window
   appears when it has loaded, at the document's size, or with the error when it could not be;
   Apple shows the window at once with a spinner, but a GTK window takes its size from its
   content. Closing the window (closeWindow, or by hand the one it replaces) while it loads drops
   it; presenting the UUID again replaces the load. A loading window keeps the application alive,
   and counts as a window when the user closes what may be the last one.
 - Resources: the app's bundle (resourceFolder, AppBundle) and each window's document folder, where
   LoadableView names and image resources are found.
 - A WindowGroup document (a SwiftUI app's window scene on Apple): its content is the window's
   document, its title the window's, and its commands join the primary menu (windowGroup).
 - Commands: the CommandMenu and CommandGroup elements loaded (loadMenuBar) in a primary menu at
   the end of the window's header bar, their shortcuts working in every window (AppCommands).
 - Presentations: each window shows its model's modal, alert, confirmation dialog and toast
   (WindowPresenter); toasts in an AdwToastOverlay around the content, below the header bar.
 - Closing: GTK ends an application when its last window goes, AppKit does not (an AppKit
   application with no window keeps running until it is told to terminate). ActionUI follows
   AppKit for the host and GTK for the user:
   - The host closing its last window (closeWindow, or dropping the load of its last document)
     leaves the application running, held open with no window until the host presents another
     or calls terminate(), which asks the shouldTerminate handler, as on Apple. A host may close
     one window before it presents the next (a wizard's steps, say); with GTK's rule the
     application would end in between.
   - The user closing the last window by hand ends the application, after asking the
     shouldTerminate handler (false keeps the window open). Here the platforms differ on
     purpose: an application with no window has no Dock icon or menu bar on Linux to quit it
     from, so it would be left running out of reach.
   A window that is not the last one just closes. windowWillClose fires for each window that
   closes.
   Presenting a window again under the same UUID replaces it, with no windowWillClose (on Apple
   nothing closes then). An application with no window yet when it has started waits for its
   first one, as on Apple, where a document may load later.
 - Active state: the application is active while one of its windows is. GTK has no "will"
   events, so willBecomeActive and willResignActive fire just before their "did" events. The
   state is settled after the main loop's current events, so moving between the application's
   own windows changes nothing.
 - The application ID (reverse DNS, as GApplication needs) is the one set, else one made from
   the name, as Apple's bundle identifier for an unbundled process is.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import Dispatch

@MainActor
public final class AdwaitaApplication {
    public static let shared = AdwaitaApplication()

    /// The lifecycle callbacks of the host, all optional.
    public struct Handlers {
        public var willFinishLaunching: (() -> Void)?
        public var didFinishLaunching: (() -> Void)?
        public var willBecomeActive: (() -> Void)?
        public var didBecomeActive: (() -> Void)?
        public var willResignActive: (() -> Void)?
        public var didResignActive: (() -> Void)?
        public var willTerminate: (() -> Void)?
        /// Asked before the application ends by the user's hand or terminate(); false cancels.
        public var shouldTerminate: (() -> Bool)?
        public var windowWillPresent: ((String) -> Void)?
        public var windowWillClose: ((String) -> Void)?
    }

    /// Apple's fallback window size when the content reports almost none.
    static let fallbackSize = (width: Int32(480), height: Int32(320))
    /// The widest a window opens unless its content's minimum needs more: SwiftUI's WindowGroup
    /// opens 900 points wide on macOS (measured on macOS 27, whatever the content), so a long
    /// line of text does not open a window as wide as the monitor.
    static let openingWidth = 900
    /// The least a window opens tall when its content grows vertically (a List, a ScrollView, a
    /// Table, a Color): SwiftUI's WindowGroup gives its content 418 points (macOS 27), so an
    /// empty List waiting for its rows does not open as a strip.
    static let openingHeight: Int32 = 418

    public var handlers = Handlers()
    /// The application's name: window titles default to it, and the default application ID.
    public var name: String? {
        didSet {
            // GLib keeps the first name a process sets and warns at every later one.
            if let name, !Self.glibNameSet {
                Self.glibNameSet = true
                g_set_application_name(name)
            }
        }
    }
    private static var glibNameSet = false
    /// The reverse-DNS application ID; nil: the bundle's Info.json gives it at run, else one is made
    /// from the name. The name and icon also come from Info.json when unset.
    public var applicationID: String?
    /// The folder of the app's resources (AppBundle): the running program's folder unless set (a
    /// host whose program is not in its bundle, such as python3, sets its own; nil: back to the
    /// program's, ActionUIResourceFolder). LoadableView names and Image resourceName and assetName
    /// are looked up there.
    public var resourceFolder: String? {
        get { AppBundle.folder }
        set { ActionUIResourceFolder.path = newValue }
    }
    /// The windows' icon: an icon theme name (an image of that name in the app's bundle counts),
    /// or the path of an image file.
    public var icon: String? {
        didSet { applyIcon() }
    }

    private var application: UnsafeMutablePointer<AdwApplication>?
    private(set) var hasStarted = false
    private var pendingWindows: [PendingWindow] = []
    private var windows: [String: PresentedWindow] = [:]
    /// The windows whose http or https document is loading, each with its load's number: a newer
    /// presentWindow or a closeWindow makes an older load drop its result. Each load holds the
    /// application, as the window it stands for would.
    private var remoteLoads: [String: Int] = [:]
    private var remoteLoadCounter = 0
    private var isActive = false
    private var activeCheckQueued = false
    /// Whether the application is held open while it has no window: until its first window, and
    /// after the host closed its last one, until its next (GApplication ends with no window and
    /// no hold). See "Closing" above.
    private var holdsWhileWindowless = false
    /// Icon folders already in the icon theme's search path.
    private var iconFolders: Set<String> = []

    /// A window asked for before the application started.
    private struct PendingWindow {
        let source: WindowSource
        let windowUUID: String
        let title: String?
    }

    /// Where a window's document comes from.
    enum WindowSource {
        case url(String)
        case json(Data)
        /// An http or https URL's document, loaded (nil: it could not be).
        case fetched(String, Data?)
    }

    /// A window on screen: its GTK window and its render tree.
    private final class PresentedWindow {
        let window: UnsafeMutablePointer<GtkWindow>
        let renderTree: AdwaitaWindow?
        /// Set while the host closes the window, which then asks no handler.
        var closingByHost = false

        init(window: UnsafeMutablePointer<GtkWindow>, renderTree: AdwaitaWindow?) {
            self.window = window
            self.renderTree = renderTree
        }
    }

    /// The UUIDs of the windows on screen.
    var windowUUIDs: [String] { Array(windows.keys) }

    /// The GTK window showing `windowUUID`, if it is on screen.
    func gtkWindow(_ windowUUID: String) -> UnsafeMutablePointer<GtkWindow>? {
        windows[windowUUID]?.window
    }

    /// The document's content in the window showing `windowUUID`, if it is on screen with its
    /// document: the root element's widget, without the window's header bar and toast overlay.
    func contentWidget(_ windowUUID: String) -> WidgetPointer? {
        windows[windowUUID]?.renderTree?.contentWidget
    }

    /// The modals, dialogs and toasts of the window showing `windowUUID`, if it is on screen with
    /// its document.
    func presenter(_ windowUUID: String) -> WindowPresenter? {
        windows[windowUUID]?.renderTree?.presenter
    }

    /// Whether the window showing `windowUUID` holds its document, false when it shows why the
    /// document could not be loaded (or is not on screen).
    public func showsDocument(_ windowUUID: String) -> Bool {
        windows[windowUUID]?.renderTree?.root != nil
    }

    /// Saves what the window showing `windowUUID` draws, header bar included, as a PNG file at
    /// `path`, drawn by the window's own renderer: no screen capture, so it needs no permission
    /// and works on a locked screen. False when the window is not on screen and drawn yet, or the
    /// file cannot be written.
    public func savePNG(windowUUID: String, path: String) -> Bool {
        guard let window = windows[windowUUID]?.window, gtk_widget_get_mapped(typed(window)) != 0 else { return false }
        let widget: WidgetPointer = typed(window)
        let width = gtk_widget_get_width(widget)
        let height = gtk_widget_get_height(widget)
        guard width > 0, height > 0, let renderer = gtk_native_get_renderer(OpaquePointer(window)) else { return false }
        let paintable = OwnedObject(adopting: gtk_widget_paintable_new(widget)!)
        let snapshot = gtk_snapshot_new()!
        gdk_paintable_snapshot(paintable.opaquePointer, snapshot, Double(width), Double(height))
        guard let node = gtk_snapshot_free_to_node(snapshot) else { return false }
        defer { gsk_render_node_unref(node) }
        var viewport = graphene_rect_t(origin: graphene_point_t(x: 0, y: 0),
                                       size: graphene_size_t(width: Float(width), height: Float(height)))
        guard let rendered = gsk_renderer_render_texture(renderer, node, &viewport) else { return false }
        let texture = OwnedObject(adopting: rendered)
        return gdk_texture_save_to_png(texture.opaquePointer, path) != 0
    }

    // MARK: Running

    /// Runs the application until it ends; returns GApplication's exit status. A second call
    /// while it runs is refused (logged, returns 1).
    @discardableResult
    public func run() -> Int32 {
        guard application == nil else {
            ActionUIModel.shared.logger.log("The application is already running; a second run is refused", .error)
            return 1
        }
        MainLoopBridge.install()
        applyBundleInfo()
        // Released when run returns, after the windows are gone.
        let app = OwnedObject(adopting: adw_application_new(resolvedApplicationID(), G_APPLICATION_NON_UNIQUE)!)
        application = app.typed()
        connectSignal(app.pointer, "activate", .instanceOnly) { [weak self] in self?.started() }
        connectSignal(app.pointer, "shutdown", .instanceOnly) { [weak self] in self?.handlers.willTerminate?() }
        let status = g_application_run(app.typed(), 0, nil)
        // An application that quits (terminate) leaves its windows open, each holding the
        // application; they go here, with no handler asked or told.
        for presented in Array(windows.values) {
            presented.closingByHost = true
            presented.renderTree?.detach()
            gtk_window_destroy(presented.window)
        }
        windows = [:]
        pendingWindows = []
        // A load still running is dropped; its hold went with the application.
        remoteLoads = [:]
        hasStarted = false
        isActive = false
        holdsWhileWindowless = false
        AppCommands.shared.stop()
        application = nil
        return status
    }

    /// Adds the CommandMenu and CommandGroup elements in `json` (a JSON array) to the
    /// application's primary menu (AppCommands); nil only makes sure the menu is there. Returns
    /// false for JSON that is not such an array.
    @discardableResult
    public func loadMenuBar(json: String?) -> Bool {
        AppCommands.shared.load(json: json)
    }

    /// The window a panel is modal to: the active one, nil when there is none.
    func activeWindow() -> UnsafeMutablePointer<GtkWindow>? {
        guard let application else { return nil }
        return gtk_application_get_active_window(typed(OpaquePointer(application)))
    }

    /// The UUID of the active window ("" when none of the application's windows is active), the
    /// window a menu command acts on.
    func activeWindowUUID() -> String {
        guard let application, let active = gtk_application_get_active_window(typed(OpaquePointer(application))) else { return "" }
        return windows.first { $0.value.window == active }?.key ?? ""
    }

    /// Ends the application, unless the shouldTerminate handler says no.
    public func terminate() {
        guard let application else { return }
        if let shouldTerminate = handlers.shouldTerminate, !shouldTerminate() { return }
        // An alert or file panel up runs a nested main loop, which quitting would not end: each
        // call returns nil, and the run ends after them.
        AppPanels.cancelAll()
        g_application_quit(typed(application))
    }

    /// "activate": the application has started.
    private func started() {
        // GApplication activates again when a second instance is launched; nothing to do then.
        guard !hasStarted else { return }
        hasStarted = true
        applyIcon()
        if let application {
            AppCommands.shared.start(application, name: name ?? ProcessInfo.processInfo.processName)
        }
        handlers.willFinishLaunching?()
        let pending = pendingWindows
        pendingWindows = []
        for window in pending {
            present(window.source, windowUUID: window.windowUUID, title: window.title)
        }
        if windows.isEmpty {
            holdWhileWindowless()
        }
        handlers.didFinishLaunching?()
    }

    /// Takes the name, application ID and icon the host did not set from the bundle's Info.json
    /// (AppBundle), as the bundle's Info.plist gives them on Apple.
    private func applyBundleInfo() {
        let folder = AppBundle.folder
        guard let info = AppBundle.info(in: folder) else { return }
        if name == nil, let infoName = info.name { name = infoName }
        if applicationID == nil { applicationID = info.applicationID }
        if icon == nil, let infoIcon = info.iconValue(in: folder) { icon = infoIcon }
    }

    /// The ID set, else "com.abracode.actionui." and the name made valid, else a fixed one.
    private func resolvedApplicationID() -> String {
        if let applicationID {
            if g_application_id_is_valid(applicationID) != 0 { return applicationID }
            ActionUIModel.shared.logger.log("'\(applicationID)' is not a valid application ID; using one made from the name", .warning)
        }
        let fallback = "com.abracode.actionui.app"
        guard let name, !name.isEmpty else { return fallback }
        let element = String(name.lowercased().unicodeScalars.map { scalar in
            (scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar))) ? Character(scalar) : "-"
        })
        let made = "com.abracode.actionui." + (element.first?.isNumber == true ? "app-" + element : element)
        return g_application_id_is_valid(made) != 0 ? made : fallback
    }

    /// The default icon of the application's windows: a file (a path, or a name a file has in
    /// the current folder, as on Apple, which takes a path) is found through its folder, added
    /// once to the icon theme's search path, and its name; anything else is a theme name. GTK
    /// reads unthemed icons from PNG and SVG files only.
    private func applyIcon() {
        guard let icon, let display = gdk_display_get_default() else { return }
        guard icon.contains("/") || g_file_test(icon, G_FILE_TEST_IS_REGULAR) != 0 else {
            // A theme name, or an image of that name in the app's bundle.
            AppBundle.addToIconTheme()
            gtk_window_set_default_icon_name(icon)
            return
        }
        guard let path = takeGString(g_canonicalize_filename(icon, nil)) else { return }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let folder = parts.dropLast().joined(separator: "/")
        var name = String(parts.last ?? "")
        // GTK matches the suffixes ".png" and ".svg" exactly: ".PNG" or none is not found.
        if !name.hasSuffix(".png") && !name.hasSuffix(".svg") {
            ActionUIModel.shared.logger.log("The icon \(path) does not end in .png or .svg, which GTK needs; it may not show", .warning)
        }
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            name = String(name[..<dot])
        }
        let searchFolder = folder.isEmpty ? "/" : folder
        if iconFolders.insert(searchFolder).inserted {
            gtk_icon_theme_add_search_path(gtk_icon_theme_get_for_display(display), searchFolder)
        }
        gtk_window_set_default_icon_name(name)
    }

    // MARK: Windows

    /// Loads a document from `urlString` (a file URL or path, or an http or https URL) and shows it
    /// in a new window titled `title`, else the file's name. Before the application starts, the
    /// window waits; an http or https document appears once it has loaded.
    public func presentWindow(url urlString: String, windowUUID: String, title: String?) {
        present(.url(urlString), windowUUID: windowUUID, title: title)
    }

    /// Loads the document in `json` and shows it in a new window titled `title`, else the
    /// application's name. Before the application starts, the window waits.
    public func presentWindow(json: Data, windowUUID: String, title: String?) {
        present(.json(json), windowUUID: windowUUID, title: title)
    }

    private func present(_ source: WindowSource, windowUUID: String, title: String?) {
        guard let application, hasStarted else {
            pendingWindows.append(PendingWindow(source: source, windowUUID: windowUUID, title: title))
            return
        }
        dropRemoteLoad(windowUUID)
        if case .url(let text) = source, Self.isRemote(text) {
            loadRemote(text, windowUUID: windowUUID, title: title, application: application)
            return
        }
        if let existing = windows[windowUUID] {
            ActionUIModel.shared.logger.log("A window \(windowUUID) is already on screen; closing it for the new one", .warning)
            existing.closingByHost = true
            existing.renderTree?.detach()
            gtk_window_destroy(existing.window)
        }
        let loaded = load(source, windowUUID: windowUUID)
        let renderTree = loaded.error == nil ? ActionUIModel.shared.windowModels[windowUUID].map { AdwaitaWindow(windowModel: $0) } : nil
        let content = renderTree?.contentWidget ?? errorContent(loaded.error ?? "The document has no content")

        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_application_window_new(typed(application))!)
        gtk_window_set_title(window, title ?? loaded.defaultTitle ?? name ?? ProcessInfo.processInfo.processName)
        let toolbar = adw_toolbar_view_new()!
        adw_application_window_set_content(typed(window), toolbar)
        // A document that brings its own header bars (a NavigationStack's pages) gets none here.
        var headerHeight: Int32 = 0
        if renderTree?.showsOwnHeaderBars != true {
            let header = adw_header_bar_new()!
            adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
            // The primary menu at the end, outside the toolbars' items.
            adw_header_bar_pack_end(OpaquePointer(header), AppCommands.shared.makeMenuButton())
            // The document's toolbars show in it.
            renderTree?.root?.screenBar = ScreenBar(header: header, toolbarView: toolbar)
            // Measured in the window, where the header bar has its style.
            headerHeight = Int32(clamping: Gtk.Widget(header).measure(GTK_ORIENTATION_VERTICAL).natural)
        } else {
            // The document's own header bars carry the primary menu.
            renderTree?.root?.showsPrimaryMenu = true
        }
        let monitor = monitorSize()
        let (minimum, natural) = contentSizes(content, widthCap: monitor.width)
        // The window's minimum is the content's plus the header bar's.
        // Toasts show over the content, below the header bar.
        let toastOverlay = adw_toast_overlay_new()!
        adw_toolbar_view_set_content(OpaquePointer(toolbar), toastOverlay)
        if minimum.width > monitor.width || minimum.height + headerHeight > monitor.height {
            ActionUIModel.shared.logger.log("Window \(windowUUID): the document's minimum size \(minimum.width) x \(minimum.height) is larger than the screen; it scrolls", .warning)
            let scroller = gtk_scrolled_window_new()!
            gtk_scrolled_window_set_child(opaque(scroller), content)
            ViewportFocus.follow(scroller)
            adw_toast_overlay_set_child(OpaquePointer(toastOverlay), scroller)
        } else {
            adw_toast_overlay_set_child(OpaquePointer(toastOverlay), content)
        }
        renderTree?.startPresenting(over: toastOverlay, toastOverlay: OpaquePointer(toastOverlay))

        let small = natural.width < 10 || natural.height < 10
        let width = small ? Self.fallbackSize.width : natural.width
        let grows = gtk_widget_compute_expand(content, GTK_ORIENTATION_VERTICAL) != 0
        let height = max(small ? Self.fallbackSize.height : natural.height, grows ? Self.openingHeight : 0)
        gtk_window_set_default_size(window, min(width, monitor.width), min(height + headerHeight, monitor.height))

        let presented = PresentedWindow(window: window, renderTree: renderTree)
        windows[windowUUID] = presented
        connectBooleanSignal(window, "close-request") { [weak self, weak presented] in
            guard let self, let presented else { return false }
            return !self.windowWillClose(windowUUID, presented)
        }
        connectSignal(window, "destroy", .instanceOnly) { [weak self, weak presented] in
            guard let self, let presented, self.windows[windowUUID] === presented else { return }
            presented.renderTree?.detach()
            self.windows[windowUUID] = nil
            AppBundle.setDocumentFolder(nil, window: windowUUID)
        }
        connectSignal(window, "notify::is-active", .instanceAndArgument) { [weak self] in
            self?.queueActiveCheck()
        }
        handlers.windowWillPresent?(windowUUID)
        gtk_window_present(window)
        if holdsWhileWindowless {
            // The window holds the application now.
            holdsWhileWindowless = false
            g_application_release(typed(application))
        }
    }

    /// Holds the application open with no window (see "Closing" above), once; presenting a window
    /// releases the hold.
    private func holdWhileWindowless() {
        guard !holdsWhileWindowless, let application else { return }
        holdsWhileWindowless = true
        g_application_hold(typed(application))
    }

    /// Brings the window showing `windowUUID` to the front; false when it is not on screen.
    @discardableResult
    public func showWindow(_ windowUUID: String) -> Bool {
        guard let window = windows[windowUUID]?.window else { return false }
        gtk_window_present(window)
        return true
    }

    /// Closes the window showing `windowUUID`; windowWillClose fires, shouldTerminate is not
    /// asked. A window still waiting for the application to start, or for its document to load, is
    /// dropped. The application keeps running when that was its last window (see "Closing" above).
    public func closeWindow(_ windowUUID: String) {
        pendingWindows.removeAll { $0.windowUUID == windowUUID }
        // The load was the last thing holding the application: it stays open without it.
        if hasStarted, windows.isEmpty, remoteLoads[windowUUID] != nil, remoteLoads.count == 1 {
            holdWhileWindowless()
        }
        dropRemoteLoad(windowUUID)
        guard let presented = windows[windowUUID] else { return }
        presented.closingByHost = true
        // AdwDialogHost answers a close request while a dialog is up by closing that dialog, not
        // the window (as for the user's close): the presentations come down first.
        presented.renderTree?.presenter?.stop()
        presented.renderTree?.root?.takeDownPresentations()
        gtk_window_close(presented.window)
        // GTK closes nothing for a window not realized yet or already closing; a later close by
        // the user must ask again, and the presentations (window-level and the elements') come back.
        if windows[windowUUID] === presented {
            presented.closingByHost = false
            presented.renderTree?.presenter?.resume()
            presented.renderTree?.root?.restorePresentations()
        }
    }

    /// "close-request": whether the window closes. The user's close of the last window (no other
    /// window loading either) asks shouldTerminate first, and ends the application; the host's
    /// close of the last window holds the application open instead (see "Closing" above). A load
    /// replacing the window is dropped.
    private func windowWillClose(_ windowUUID: String, _ presented: PresentedWindow) -> Bool {
        let isLast = windows.count == 1 && remoteLoads.keys.allSatisfy { $0 == windowUUID }
        if !presented.closingByHost, isLast, let shouldTerminate = handlers.shouldTerminate, !shouldTerminate() {
            return false
        }
        if presented.closingByHost, isLast {
            holdWhileWindowless()
        }
        if windows[windowUUID] === presented {
            windows[windowUUID] = nil
            dropRemoteLoad(windowUUID)
            AppBundle.setDocumentFolder(nil, window: windowUUID)
        }
        handlers.windowWillClose?(windowUUID)
        presented.renderTree?.detach()
        // The window's ActionUI model goes after the handler, which may read its values, and the
        // rest of this turn of the main loop; an app that opens and closes windows for a long time
        // would otherwise keep every one. Through the main queue, behind the disappear actions the
        // detach above queued there (NodeAppearance), which read the values too. Not when a window
        // under the same UUID is on screen or loading again by then (the client reopened it): that
        // window's model is in use.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.windows[windowUUID] == nil, self.remoteLoads[windowUUID] == nil,
                  !self.pendingWindows.contains(where: { $0.windowUUID == windowUUID }) else { return }
            ActionUIModel.shared.removeWindow(windowUUID)
        }
        return true
    }

    /// The document of a window: loaded into the model under `windowUUID`, or why it is not, and
    /// the title a file gives.
    private func load(_ source: WindowSource, windowUUID: String) -> (error: String?, defaultTitle: String?) {
        let logger = ActionUIModel.shared.logger
        // A file's folder is where its LoadableViews find their names; other documents have none.
        AppBundle.setDocumentFolder(nil, window: windowUUID)
        switch source {
        case .json(let data):
            let document = windowGroup(data, format: "json")
            do {
                try loadDocument(document, format: "json", windowUUID: windowUUID)
                return (nil, document.title)
            } catch {
                logger.log("Window \(windowUUID): the JSON could not be loaded: \(error)", .error)
                return ("The document could not be loaded: \(error)", document.title)
            }
        case .fetched(let text, let data):
            let url = URL(string: text)
            let title = url.map { $0.deletingPathExtension().lastPathComponent }.flatMap { $0.isEmpty || $0 == "/" ? nil : $0 }
            guard let url, let data else {
                logger.log("Window \(windowUUID): \(text) could not be loaded", .error)
                return ("\(text) could not be loaded", title)
            }
            let format = ActionUIDocumentLoader.format(of: url)
            let document = windowGroup(data, format: format)
            do {
                try loadDocument(document, format: format, windowUUID: windowUUID)
                return (nil, document.title ?? title)
            } catch {
                logger.log("Window \(windowUUID): \(text) could not be loaded: \(error)", .error)
                return ("\(text) could not be loaded: \(error)", document.title ?? title)
            }
        case .url(let text):
            let url: URL
            if text.lowercased().hasPrefix("file://"), let fileURL = URL(string: text) {
                url = fileURL
            } else {
                url = URL(fileURLWithPath: text)
            }
            var title = url.deletingPathExtension().lastPathComponent
            do {
                let format = ActionUIDocumentLoader.format(of: url)
                let document = windowGroup(try Data(contentsOf: url), format: format)
                title = document.title ?? title
                AppBundle.setDocumentFolder(url.deletingLastPathComponent().path, window: windowUUID)
                try loadDocument(document, format: format, windowUUID: windowUUID)
                return (nil, title)
            } catch {
                logger.log("Window \(windowUUID): \(url.path) could not be loaded: \(error)", .error)
                return ("\(url.path) could not be loaded: \(error)", title)
            }
        }
    }

    /// A WindowGroup document (on Apple, the window scene of a SwiftUI app) as a window: its content
    /// is the window's document and its title the window's default title, and its commands join the
    /// primary menu once it has loaded, once per group (by windowGroupID, else title, as Apple names
    /// the group); one with no content cannot be loaded, as Apple shows "No content provided". Any
    /// other document comes back as it is. JSON only: a property list has no WindowGroup scene.
    func windowGroup(_ data: Data, format: String) -> WindowDocument {
        guard format == "json",
              let parsed = (try? ActionUIJSON.value(from: String(decoding: data, as: UTF8.self))) as? [String: Any],
              parsed["type"] as? String == "WindowGroup" else { return WindowDocument(data: data) }
        // Its platform overrides ("title:linux" and the like) resolved first, as Core resolves them
        // in the whole document on Apple.
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: ActionUIModel.shared.logger)
        let root = filter.filter(parsed) as? [String: Any] ?? parsed
        let properties = root["properties"] as? [String: Any] ?? [:]
        let title = (properties["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var document = WindowDocument(data: data, title: title)
        if let commands = root["commands"] as? [Any], let json = try? ActionUIJSON.string(from: commands) {
            let key = (properties["windowGroupID"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title ?? json
            document.commands = (json, key)
        }
        guard let content = root["content"], let json = try? ActionUIJSON.string(from: content) else {
            // As Apple's WindowGroup shows "No content provided".
            document.error = "the WindowGroup has no content"
            return document
        }
        document.data = Data(json.utf8)
        return document
    }

    /// A window's document as windowGroup leaves it: what to load, its default title, the commands
    /// to add once it has loaded, or why it cannot be.
    struct WindowDocument {
        var data: Data
        var title: String? = nil
        var commands: (json: String, key: String)? = nil
        var error: String? = nil
    }

    private struct DocumentError: Error, CustomStringConvertible {
        let description: String
    }

    /// Loads `document` into the model under `windowUUID`, then adds its commands to the primary
    /// menu: a WindowGroup that fails to load brings none, as on Apple, where it has no scene.
    private func loadDocument(_ document: WindowDocument, format: String, windowUUID: String) throws {
        if let error = document.error {
            throw DocumentError(description: error)
        }
        _ = try ActionUIModel.shared.loadDescription(from: document.data, format: format, windowUUID: windowUUID)
        if let commands = document.commands {
            AppCommands.shared.load(json: commands.json, once: commands.key)
        }
    }

    /// Whether `text` is an http or https URL, which loads before its window appears.
    private static func isRemote(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    /// Loads an http or https document, then presents its window (with the error when it could not
    /// be loaded), unless a newer presentWindow or a closeWindow for the UUID came meanwhile.
    private func loadRemote(_ text: String, windowUUID: String, title: String?, application: UnsafeMutablePointer<AdwApplication>) {
        remoteLoadCounter &+= 1
        let load = remoteLoadCounter
        remoteLoads[windowUUID] = load
        g_application_hold(typed(application))
        URLLoader.fetch(text) { [weak self] bytes in
            guard let self, self.remoteLoads[windowUUID] == load else { return }
            // present drops the load and its hold, and the window holds the application.
            self.present(.fetched(text, bytes?.data), windowUUID: windowUUID, title: title)
        }
    }

    /// Ends `windowUUID`'s load, if one is running: its result is dropped, its hold released.
    private func dropRemoteLoad(_ windowUUID: String) {
        guard remoteLoads.removeValue(forKey: windowUUID) != nil, let application else { return }
        g_application_release(typed(application))
    }

    /// A window's content when its document could not be loaded: the error, selectable.
    private func errorContent(_ message: String) -> WidgetPointer {
        let label = gtk_label_new(message)!
        gtk_label_set_wrap(opaque(label), 1)
        gtk_label_set_selectable(opaque(label), 1)
        for side in [gtk_widget_set_margin_top, gtk_widget_set_margin_bottom, gtk_widget_set_margin_start, gtk_widget_set_margin_end] {
            side(label, 20)
        }
        return label
    }

    /// The content's minimum and natural size; the natural width at most `widthCap`, and at most
    /// the opening width unless the minimum needs more, and the heights for that width, as text
    /// wraps taller in a narrower window.
    private func contentSizes(_ content: WidgetPointer, widthCap: Int32) -> (minimum: (width: Int32, height: Int32), natural: (width: Int32, height: Int32)) {
        let minimumWidth = Gtk.Widget(content).measure(GTK_ORIENTATION_HORIZONTAL).minimum
        let natural = askingForScrolledContent(in: content) {
            let width = Gtk.Widget(content).measure(GTK_ORIENTATION_HORIZONTAL)
            let opening = max(min(width.natural, Int(widthCap), max(Self.openingWidth, minimumWidth)), minimumWidth)
            return (width: opening, height: Gtk.Widget(content).measure(GTK_ORIENTATION_VERTICAL, forSize: opening).natural)
        }
        // The minimum height at the opening width, where text wraps taller than on one line.
        let minimumHeight = Gtk.Widget(content).measure(GTK_ORIENTATION_VERTICAL, forSize: natural.width).minimum
        return ((Int32(clamping: minimumWidth), Int32(clamping: minimumHeight)),
                (Int32(clamping: natural.width), Int32(clamping: natural.height)))
    }

    /// Runs `measure` with every scrolled window in `content` asking for its content's natural
    /// size, then as before. A scrolled window asks for almost nothing along an axis it scrolls, so
    /// a document in a ScrollView (or holding a List) opened as a strip; it opens tall enough to
    /// show its content now, up to the monitor, as other documents do. The minimum stays the
    /// scrolled windows' own, so the window can still be made small. (SwiftUI's WindowGroup opens
    /// 900 x 418 whatever the content; Linux fits the content, the owner's choice.)
    private func askingForScrolledContent<Result>(in content: WidgetPointer, _ measure: () -> Result) -> Result {
        var changed: [(scroller: OpaquePointer, width: gboolean, height: gboolean)] = []
        func visit(_ widget: WidgetPointer) {
            if g_type_check_instance_is_a(widget.withMemoryRebound(to: GTypeInstance.self, capacity: 1) { $0 }, gtk_scrolled_window_get_type()) != 0 {
                let scroller = OpaquePointer(widget)
                let width = gtk_scrolled_window_get_propagate_natural_width(scroller)
                let height = gtk_scrolled_window_get_propagate_natural_height(scroller)
                if width == 0 || height == 0 {
                    changed.append((scroller, width, height))
                    gtk_scrolled_window_set_propagate_natural_width(scroller, 1)
                    gtk_scrolled_window_set_propagate_natural_height(scroller, 1)
                }
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                visit(current)
                child = gtk_widget_get_next_sibling(current)
            }
        }
        visit(content)
        defer {
            for (scroller, width, height) in changed {
                gtk_scrolled_window_set_propagate_natural_width(scroller, width)
                gtk_scrolled_window_set_propagate_natural_height(scroller, height)
            }
        }
        return measure()
    }

    /// The size of the display's first monitor; a large bound when there is none.
    private func monitorSize() -> (width: Int32, height: Int32) {
        guard let display = gdk_display_get_default(), let monitors = gdk_display_get_monitors(display),
              g_list_model_get_n_items(monitors) > 0, let item = g_list_model_get_item(monitors, 0) else {
            return (8192, 8192)
        }
        let monitor = OwnedObject(adopting: item)
        var geometry = GdkRectangle()
        gdk_monitor_get_geometry(monitor.opaquePointer, &geometry)
        return (geometry.width, geometry.height)
    }

    // MARK: Active state

    private func queueActiveCheck() {
        guard !activeCheckQueued else { return }
        activeCheckQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeCheckQueued = false
            let active = self.windows.values.contains { gtk_window_is_active($0.window) != 0 }
            guard active != self.isActive else { return }
            self.isActive = active
            if active {
                self.handlers.willBecomeActive?()
                self.handlers.didBecomeActive?()
            } else {
                self.handlers.willResignActive?()
                self.handlers.didResignActive?()
            }
        }
    }
}
