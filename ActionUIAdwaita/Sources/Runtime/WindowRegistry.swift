// Sources/Runtime/WindowRegistry.swift
/*
 The windows showing ActionUI documents, by window UUID: the GTK window and its render tree. The
 renderer finds a window's content, its presentations and the active window here, whoever made the
 window: ActionUI's own application (AdwaitaApplication) registers each window it presents, and a
 host that makes its own windows registers those it fills. So nothing in the renderer depends on
 ActionUI's application, as on macOS, where the elements do not know which app shows them.

 The active window is the active window of the application in use: the one AppCommands was started
 with (ActionUI's own), else the process's default GApplication (a host's own application, found
 as AppKit code finds NSApp), mapped back to its UUID here; "" when it shows no ActionUI document.

 Registering also makes sure main-actor work runs under GTK's main loop (MainLoopBridge), as every
 window showing a document needs it. A window destroyed is forgotten by itself ("destroy"), so a
 host that does not unregister one leaves no pointer to a freed window behind.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
package final class WindowRegistry {
    package static let shared = WindowRegistry()

    /// A window showing a document: its GTK window and its render tree (nil while it shows why its
    /// document could not be loaded).
    final class Entry {
        let window: UnsafeMutablePointer<GtkWindow>
        let renderTree: AdwaitaWindow?
        /// The height of the bars above the content (WindowAssembly.assemble), 0 when not measured.
        let barsHeight: Int32
        /// The window's "destroy" handler, which forgets it.
        var destroyHandler: gulong = 0

        init(window: UnsafeMutablePointer<GtkWindow>, renderTree: AdwaitaWindow?, barsHeight: Int32) {
            self.window = window
            self.renderTree = renderTree
            self.barsHeight = barsHeight
        }
    }

    private var entries: [String: Entry] = [:]

    /// A separate instance for tests; the renderer uses `shared`.
    init() {}

    /// Registers `window` as the one showing `windowUUID`, in place of any before it; `barsHeight`
    /// is the height of the bars above its content, as WindowAssembly.assemble measured it.
    package func register(_ windowUUID: String, window: UnsafeMutablePointer<GtkWindow>, renderTree: AdwaitaWindow?,
                          barsHeight: Int32 = 0) {
        MainLoopBridge.install()
        if let old = entries[windowUUID] {
            Self.disconnect(old)
        }
        let entry = Entry(window: window, renderTree: renderTree, barsHeight: barsHeight)
        entry.destroyHandler = connectSignal(UnsafeMutableRawPointer(window), "destroy", .instanceOnly) { [weak self] in
            self?.unregister(windowUUID, window: window)
        }
        entries[windowUUID] = entry
    }

    /// Forgets the window showing `windowUUID`, if it is `window` (a newer window under the same
    /// UUID stays registered).
    package func unregister(_ windowUUID: String, window: UnsafeMutablePointer<GtkWindow>) {
        guard let entry = entries[windowUUID], entry.window == window else { return }
        Self.disconnect(entry)
        entries[windowUUID] = nil
    }

    /// Forgets every window.
    func removeAll() {
        entries.values.forEach(Self.disconnect)
        entries = [:]
    }

    /// Disconnects an entry's "destroy" handler, which a window being destroyed has run already.
    private static func disconnect(_ entry: Entry) {
        if entry.destroyHandler != 0, g_signal_handler_is_connected(UnsafeMutableRawPointer(entry.window), entry.destroyHandler) != 0 {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(entry.window), entry.destroyHandler)
        }
        entry.destroyHandler = 0
    }

    /// The GTK window showing `windowUUID`, if it is registered.
    func gtkWindow(_ windowUUID: String) -> UnsafeMutablePointer<GtkWindow>? {
        entries[windowUUID]?.window
    }

    /// The height of the bars above the content of the window showing `windowUUID` (its header bar
    /// and subtitle line), nil when no window shows it. A host adds it to a size below the bars to
    /// get the window's size (actionUIGetWindowBarsHeight).
    package func barsHeight(_ windowUUID: String) -> Int32? {
        entries[windowUUID]?.barsHeight
    }

    /// The document's content in the window showing `windowUUID`: the root element's widget,
    /// without the window's header bar and toast overlay.
    func contentWidget(_ windowUUID: String) -> WidgetPointer? {
        entries[windowUUID]?.renderTree?.contentWidget
    }

    /// The modals, dialogs and toasts of the window showing `windowUUID`.
    func presenter(_ windowUUID: String) -> WindowPresenter? {
        entries[windowUUID]?.renderTree?.presenter
    }

    /// The UUID `window` is registered under, "" when none.
    func windowUUID(of window: UnsafeMutablePointer<GtkWindow>?) -> String {
        guard let window else { return "" }
        return entries.first { $0.value.window == window }?.key ?? ""
    }

    /// The UUIDs registered.
    var windowUUIDs: [String] { Array(entries.keys) }

    /// The active window of `application` (a GtkApplication), nil when there is none.
    static func activeWindow(of application: OpaquePointer?) -> UnsafeMutablePointer<GtkWindow>? {
        guard let application else { return nil }
        return gtk_application_get_active_window(typed(application))
    }

    /// The UUID of `application`'s active window, "" when it shows no registered document.
    func activeWindowUUID(of application: OpaquePointer?) -> String {
        windowUUID(of: Self.activeWindow(of: application))
    }
}
