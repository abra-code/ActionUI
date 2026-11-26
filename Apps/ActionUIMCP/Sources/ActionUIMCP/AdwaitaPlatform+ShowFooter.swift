// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AdwaitaPlatform+ShowFooter.swift - the bottom bar of a `show` window on Linux, as on macOS
// (AppKitPlatform+ShowFooter.swift): where the content came from (a file, with a button that shows
// it in the file manager, or a web address), when the window was shown, and a Save button (Copy URL
// for content from the network). It is one of the window's own bars
// (AdwaitaApplication.WindowOptions.bottomBar), outside the ActionUI JSON, so the agent can neither
// change it nor press its buttons; it keeps working in a kept window after the session ends.

#if os(Linux)
import FoundationEssentials
import Glibc
import CAdwaita
import ActionUIAdwaitaApplication
import MCPStdio

@MainActor
enum LinuxShowFooter {
    static let height: Int32 = 26
    /// Dark text on the yellow, light or dark style alike, as macOS draws it.
    private static let css = """
        .actionui-mcp-bar {
          min-height: \(height)px;
          padding: 0 10px;
          background-image: linear-gradient(to bottom, rgb(252, 240, 97), rgb(216, 185, 74));
          color: #262626;
        }
        .actionui-mcp-bar label { color: #262626; font-size: smaller; }
        .actionui-mcp-bar label selection { background-color: rgba(0, 0, 0, 0.2); color: #262626; }
        .actionui-mcp-bar button {
          min-height: 18px;
          margin: 3px 0;
          padding: 0 8px;
          color: #262626;
          background: rgba(255, 255, 255, 0.6);
          border-radius: 5px;
          box-shadow: none;
          font-size: smaller;
        }
        .actionui-mcp-bar button:hover { background: rgba(255, 255, 255, 0.85); }
        .actionui-mcp-bar button.flat { background: none; padding: 0 4px; }
        .actionui-mcp-bar button.flat:hover { background: rgba(0, 0, 0, 0.08); }
        """
    private static var styled = false

    /// A new bar for `footer` in the window `windowID`.
    static func widget(_ footer: ShowFooter, windowID: String) -> UnsafeMutableRawPointer {
        installStyle()
        let bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
        gtk_widget_add_css_class(bar, "actionui-mcp-bar")
        var filled = false
        if let source = footer.path ?? footer.url {
            let label = gtk_label_new(ShowFooter.shownSource(source))!
            gtk_label_set_ellipsize(OpaquePointer(label), PANGO_ELLIPSIZE_MIDDLE)
            gtk_label_set_single_line_mode(OpaquePointer(label), 1)
            gtk_label_set_selectable(OpaquePointer(label), 1)
            gtk_label_set_xalign(OpaquePointer(label), 0)
            // Its natural width is then next to nothing: it shows as much as the bar leaves it.
            gtk_label_set_max_width_chars(OpaquePointer(label), 1)
            gtk_widget_set_hexpand(label, 1)
            gtk_widget_set_tooltip_text(label, source)
            append(bar, label)
            filled = true
        }
        if let path = footer.path {
            let button = gtk_button_new_from_icon_name("folder-symbolic")!
            gtk_widget_add_css_class(button, "flat")
            gtk_widget_set_tooltip_text(button, "Show in Files")
            gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
            onClicked(button) { reveal(path, from: button) }
            append(bar, button)
        }
        if !filled {
            let spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
            gtk_widget_set_hexpand(spacer, 1)
            append(bar, spacer)
        }
        let shown = gtk_label_new(shownTime(footer.shownAt))!
        gtk_widget_set_tooltip_text(shown, "When the window was shown")
        append(bar, shown)
        if let save = footer.save {
            let button = gtk_button_new_with_label("Save\u{2026}")!
            gtk_widget_set_tooltip_text(button, "Save a copy of what the window shows")
            gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
            onClicked(button) { saveCopy(save, windowID: windowID, from: button) }
            append(bar, button)
            #if DEBUG
            scheduleTestSave(save, windowID: windowID)
            #endif
        } else if let url = footer.url {
            let button = gtk_button_new_with_label("Copy URL")!
            gtk_widget_set_tooltip_text(button, "Copy the web address")
            gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
            onClicked(button) { gdk_clipboard_set_text(gtk_widget_get_clipboard(button), url) }
            append(bar, button)
        }
        return UnsafeMutableRawPointer(bar)
    }

    private static func append(_ box: UnsafeMutablePointer<GtkWidget>, _ child: UnsafeMutablePointer<GtkWidget>) {
        gtk_box_append(UnsafeMutableRawPointer(box).assumingMemoryBound(to: GtkBox.self), child)
    }

    private static func installStyle() {
        guard !styled, let display = gdk_display_get_default() else { return }
        styled = true
        let provider = gtk_css_provider_new()!
        gtk_css_provider_load_from_string(provider, css)
        gtk_style_context_add_provider_for_display(display, OpaquePointer(provider), UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
    }

    /// The date and time in the user's locale, as GLib writes them.
    private static func shownTime(_ date: Date) -> String {
        guard let time = g_date_time_new_from_unix_local(gint64(date.timeIntervalSince1970)) else { return "" }
        defer { g_date_time_unref(time) }
        guard let text = g_date_time_format(time, "%x %X") else { return "" }
        defer { g_free(text) }
        return String(cString: text)
    }

    /// Selects the file in a file manager window; never opens it. A file that is gone rings the bell.
    private static func reveal(_ path: String, from button: UnsafeMutablePointer<GtkWidget>) {
        guard FileManager.default.fileExists(atPath: path) else {
            gtk_widget_error_bell(button)
            return
        }
        guard let file = g_file_new_for_path(path) else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(file)) }
        guard let launcher = gtk_file_launcher_new(file) else { return }
        // The launch keeps the launcher until it is done.
        defer { g_object_unref(UnsafeMutableRawPointer(launcher)) }
        gtk_file_launcher_open_containing_folder(launcher, window(of: button), nil, nil, nil)
    }

    private static func window(of widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWindow>? {
        guard let root = gtk_widget_get_root(widget) else { return nil }
        return UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
    }

    /// Asks where with a save panel, then writes there; the panel confirms replacing a file.
    /// Nothing is written anywhere else.
    private static func saveCopy(_ save: ShowSave, windowID: String, from button: UnsafeMutablePointer<GtkWidget>) {
        let settings = JSONValue.object(["title": .string("Save a Copy"), "nameFieldStringValue": .string(save.suggestedName)])
        // The panel is modal to no window, which can close under it: the button lives until the
        // panel answers, and an error then shows over the window only while the button is in one.
        g_object_ref(UnsafeMutableRawPointer(button))
        AppPanels.beginSavePanel(json: settings.serialized()) { path in
            defer { g_object_unref(UnsafeMutableRawPointer(button)) }
            guard let path else { return }
            do {
                try write(save.content, to: path, windowID: windowID)
            } catch {
                showError("The copy could not be saved.", String(describing: error), over: gtk_widget_get_root(button) != nil ? button : nil)
            }
        }
    }

    private static func write(_ content: ShowSave.Content, to destination: String, windowID: String) throws {
        if case .file(let path) = content {
            // Saving a file onto itself: it is already there, and replacing it first would lose it.
            let source = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            if source == URL(fileURLWithPath: destination).resolvingSymlinksInPath().standardizedFileURL { return }
            // Copied beside the destination, then renamed over it: the destination, or a link
            // there, is replaced whole or not at all.
            let target = URL(fileURLWithPath: destination)
            let staged = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString)").path
            do {
                try FileManager.default.copyItem(atPath: path, toPath: staged)
                guard rename(staged, destination) == 0 else {
                    throw MCPToolError("could not write \(destination): \(String(cString: strerror(errno)))")
                }
            } catch {
                try? FileManager.default.removeItem(atPath: staged)
                throw error
            }
            return
        }
        guard let data = try ShowSave.bytes(of: content, windowID: windowID, chartPNG: { try chartPNG(windowID) }) else { return }
        try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    /// The window's content, between its bars, as a PNG.
    private static func chartPNG(_ windowID: String) throws -> Data {
        let file = HostSupport.sessionFolder.appendingPathComponent("chart-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        guard AdwaitaApplication.shared.capturePNG(windowUUID: windowID, path: file.path, contentOnly: true) != nil else {
            throw MCPToolError("the chart could not be drawn")
        }
        return try Data(contentsOf: file)
    }

    /// An alert over the window of `widget`; with none, a window of its own.
    private static func showError(_ heading: String, _ body: String, over widget: UnsafeMutablePointer<GtkWidget>?) {
        guard let dialog = adw_alert_dialog_new(heading, body) else { return }
        adw_alert_dialog_add_response(UnsafeMutableRawPointer(dialog).assumingMemoryBound(to: AdwAlertDialog.self), "ok", "OK")
        adw_dialog_present(dialog, widget)
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_SAVE_DIR=<folder>: for the live test, 1.5 seconds after the window opens,
    /// save as the Save button does, into that folder under the offered name, with no panel.
    private static func scheduleTestSave(_ save: ShowSave, windowID: String) {
        guard let folder = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_SAVE_DIR"] else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            do {
                try write(save.content, to: URL(fileURLWithPath: folder).appendingPathComponent(save.suggestedName).path, windowID: windowID)
            } catch {
                HostSupport.logLine("[actionui-mcp] test save failed: \(error)")
            }
        }
    }
    #endif

    // MARK: Clicks

    /// A click handler, kept by GLib while the button lives. GLib calls it on the main thread only.
    private final class Handler: @unchecked Sendable {
        let run: @MainActor () -> Void
        init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    }

    private static let clicked: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
        guard let data else { return }
        let handler = Unmanaged<Handler>.fromOpaque(data).takeUnretainedValue()
        MainActor.assumeIsolated { handler.run() }
    }

    private static let release: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
        guard let data else { return }
        Unmanaged<Handler>.fromOpaque(data).release()
    }

    private static func onClicked(_ button: UnsafeMutablePointer<GtkWidget>, _ run: @escaping @MainActor () -> Void) {
        let data = Unmanaged.passRetained(Handler(run)).toOpaque()
        let id = g_signal_connect_data(UnsafeMutableRawPointer(button), "clicked", unsafeBitCast(clicked, to: GCallback.self),
                                       data, release, GConnectFlags(rawValue: 0))
        if id == 0 {
            Unmanaged<Handler>.fromOpaque(data).release()
        }
    }
}
#endif
