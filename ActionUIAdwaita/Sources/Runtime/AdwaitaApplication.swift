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
   on Apple), never larger than the monitor: GTK's renderers fail on windows far larger than the
   screen. A document whose minimum is larger than the monitor scrolls.
 - A document that cannot be loaded is logged and shown as its error text in the window, as on
   Apple. Remote URLs load nowhere yet on Linux (no HTTP client without full Foundation).
 - Closing: GTK ends the application when its last window goes. Closing the last window by hand
   first asks the shouldTerminate handler, and false keeps it open; terminate() asks it too. A
   window closed by the host, or not the last one, just closes; windowWillClose fires for each.
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
    /// The reverse-DNS application ID; nil makes one from the name.
    public var applicationID: String?
    /// The windows' icon: an icon theme name, or the path of an image file.
    public var icon: String? {
        didSet { applyIcon() }
    }

    private var application: UnsafeMutablePointer<AdwApplication>?
    private(set) var hasStarted = false
    private var pendingWindows: [PendingWindow] = []
    private var windows: [String: PresentedWindow] = [:]
    private var isActive = false
    private var activeCheckQueued = false
    /// Whether the application is held open until its first window (GApplication ends with no
    /// window and no hold).
    private var holdsForFirstWindow = false
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
            presented.renderTree?.root?.detach()
            gtk_window_destroy(presented.window)
        }
        windows = [:]
        pendingWindows = []
        hasStarted = false
        isActive = false
        holdsForFirstWindow = false
        application = nil
        return status
    }

    /// Ends the application, unless the shouldTerminate handler says no.
    public func terminate() {
        guard let application else { return }
        if let shouldTerminate = handlers.shouldTerminate, !shouldTerminate() { return }
        g_application_quit(typed(application))
    }

    /// "activate": the application has started.
    private func started() {
        // GApplication activates again when a second instance is launched; nothing to do then.
        guard !hasStarted else { return }
        hasStarted = true
        applyIcon()
        handlers.willFinishLaunching?()
        let pending = pendingWindows
        pendingWindows = []
        for window in pending {
            present(window.source, windowUUID: window.windowUUID, title: window.title)
        }
        if let application, windows.isEmpty {
            holdsForFirstWindow = true
            g_application_hold(typed(application))
        }
        handlers.didFinishLaunching?()
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

    /// Loads a document from `urlString` (a file URL or path) and shows it in a new window titled
    /// `title`, else the file's name. Before the application starts, the window waits.
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
        if let existing = windows[windowUUID] {
            ActionUIModel.shared.logger.log("A window \(windowUUID) is already on screen; closing it for the new one", .warning)
            existing.closingByHost = true
            existing.renderTree?.root?.detach()
            gtk_window_destroy(existing.window)
        }
        let loaded = load(source, windowUUID: windowUUID)
        let renderTree = loaded.error == nil ? ActionUIModel.shared.windowModels[windowUUID].map { AdwaitaWindow(windowModel: $0) } : nil
        let content = renderTree?.contentWidget ?? errorContent(loaded.error ?? "The document has no content")

        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_application_window_new(typed(application))!)
        gtk_window_set_title(window, title ?? loaded.defaultTitle ?? name ?? ProcessInfo.processInfo.processName)
        let toolbar = adw_toolbar_view_new()!
        let header = adw_header_bar_new()!
        adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
        adw_application_window_set_content(typed(window), toolbar)
        // Measured in the window, where the header bar has its style.
        var headerHeight: Int32 = 0
        gtk_widget_measure(header, GTK_ORIENTATION_VERTICAL, -1, nil, &headerHeight, nil, nil)
        let monitor = monitorSize()
        let (minimum, natural) = contentSizes(content, widthCap: monitor.width)
        // The window's minimum is the content's plus the header bar's.
        if minimum.width > monitor.width || minimum.height + headerHeight > monitor.height {
            ActionUIModel.shared.logger.log("Window \(windowUUID): the document's minimum size \(minimum.width) x \(minimum.height) is larger than the screen; it scrolls", .warning)
            let scroller = gtk_scrolled_window_new()!
            gtk_scrolled_window_set_child(opaque(scroller), content)
            adw_toolbar_view_set_content(OpaquePointer(toolbar), scroller)
        } else {
            adw_toolbar_view_set_content(OpaquePointer(toolbar), content)
        }

        let small = natural.width < 10 || natural.height < 10
        let width = small ? Self.fallbackSize.width : natural.width
        let height = small ? Self.fallbackSize.height : natural.height
        gtk_window_set_default_size(window, min(width, monitor.width), min(height + headerHeight, monitor.height))

        let presented = PresentedWindow(window: window, renderTree: renderTree)
        windows[windowUUID] = presented
        connectBooleanSignal(window, "close-request") { [weak self, weak presented] in
            guard let self, let presented else { return false }
            return !self.windowWillClose(windowUUID, presented)
        }
        connectSignal(window, "destroy", .instanceOnly) { [weak self, weak presented] in
            guard let self, let presented, self.windows[windowUUID] === presented else { return }
            presented.renderTree?.root?.detach()
            self.windows[windowUUID] = nil
        }
        connectSignal(window, "notify::is-active", .instanceAndArgument) { [weak self] in
            self?.queueActiveCheck()
        }
        handlers.windowWillPresent?(windowUUID)
        gtk_window_present(window)
        if holdsForFirstWindow {
            // The window holds the application now.
            holdsForFirstWindow = false
            g_application_release(typed(application))
        }
    }

    /// Closes the window showing `windowUUID`; windowWillClose fires, shouldTerminate is not
    /// asked. A window still waiting for the application to start is dropped.
    public func closeWindow(_ windowUUID: String) {
        pendingWindows.removeAll { $0.windowUUID == windowUUID }
        guard let presented = windows[windowUUID] else { return }
        presented.closingByHost = true
        gtk_window_close(presented.window)
        // GTK closes nothing for a window not realized yet or already closing; a later close by
        // the user must ask again.
        if windows[windowUUID] === presented {
            presented.closingByHost = false
        }
    }

    /// "close-request": whether the window closes. The user's close of the last window asks
    /// shouldTerminate first.
    private func windowWillClose(_ windowUUID: String, _ presented: PresentedWindow) -> Bool {
        if !presented.closingByHost, windows.count == 1, let shouldTerminate = handlers.shouldTerminate, !shouldTerminate() {
            return false
        }
        if windows[windowUUID] === presented {
            windows[windowUUID] = nil
        }
        handlers.windowWillClose?(windowUUID)
        presented.renderTree?.root?.detach()
        return true
    }

    /// The document of a window: loaded into the model under `windowUUID`, or why it is not, and
    /// the title a file gives.
    private func load(_ source: WindowSource, windowUUID: String) -> (error: String?, defaultTitle: String?) {
        let logger = ActionUIModel.shared.logger
        switch source {
        case .json(let data):
            do {
                _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
                return (nil, nil)
            } catch {
                logger.log("Window \(windowUUID): the JSON could not be loaded: \(error)", .error)
                return ("The document could not be loaded: \(error)", nil)
            }
        case .url(let text):
            let url: URL
            if text.lowercased().hasPrefix("file://"), let fileURL = URL(string: text) {
                url = fileURL
            } else if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
                logger.log("Window \(windowUUID): remote documents cannot be loaded on Linux yet: \(text)", .error)
                return ("Remote documents cannot be loaded on Linux yet: \(text)", nil)
            } else {
                url = URL(fileURLWithPath: text)
            }
            let title = url.deletingPathExtension().lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                _ = try ActionUIModel.shared.loadDescription(from: data, format: ActionUIDocumentLoader.format(of: url), windowUUID: windowUUID)
                return (nil, title)
            } catch {
                logger.log("Window \(windowUUID): \(url.path) could not be loaded: \(error)", .error)
                return ("\(url.path) could not be loaded: \(error)", title)
            }
        }
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

    /// The content's minimum and natural size; the heights for the width the window will have
    /// (the natural width, at most `widthCap`), as text wraps taller in a narrower window.
    private func contentSizes(_ content: WidgetPointer, widthCap: Int32) -> (minimum: (width: Int32, height: Int32), natural: (width: Int32, height: Int32)) {
        var minimumWidth: Int32 = 0
        var naturalWidth: Int32 = 0
        gtk_widget_measure(content, GTK_ORIENTATION_HORIZONTAL, -1, &minimumWidth, &naturalWidth, nil, nil)
        var minimumHeight: Int32 = 0
        var naturalHeight: Int32 = 0
        gtk_widget_measure(content, GTK_ORIENTATION_VERTICAL, max(min(naturalWidth, widthCap), minimumWidth), &minimumHeight, &naturalHeight, nil, nil)
        return ((minimumWidth, minimumHeight), (naturalWidth, naturalHeight))
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
