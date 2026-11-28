// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AdwaitaPlatform+HazardStrip.swift - the yellow and black mark under the header bar of every
// actionui-mcp window on Linux, as on macOS (AppKitPlatform+HazardStrip.swift): on `show` windows a
// bar holding where the content came from, when it was shown and Save (LinuxShowFooter), on the
// others a thin striped line. It is one of the window's own bars
// (AdwaitaApplication.WindowOptions.topBar), outside the widgets that show the ActionUI JSON, so
// nothing the agent writes can remove or restyle it. Who asked leads the window's title (windowTitle).
// The mark also gives its window Ctrl+W, which closes it (LinuxWindowMark.closesWindow).

#if os(Linux)
import FoundationEssentials
import CAdwaita

/// The mark's drawing: a yellow band, bright at the top and darker at the bottom like a bent
/// plastic tape, with black notches along its top edge that lean like a backslash; as a line,
/// black stripes across its whole height, as far apart as the strip's notches. The sizes and
/// colors are macOS's.
enum LinuxWindowMark {
    static let stripHeight: Int32 = 12
    static let lineHeight: Int32 = 3
    /// A `show` window's: the notches, then the row of LinuxShowFooter under them.
    static let barHeight: Int32 = 26
    // The notches in proportion to the strip's height; the line's stripes have the same width and spacing.
    private static let notchDepth = Double(stripHeight) * 0.4
    private static let notchWidth = Double(stripHeight) * 0.8
    private static let notchSpacing = Double(stripHeight) * 2.1
    // The yellow, bright at the top and darker at the bottom, in sRGB.
    static let bright = (red: 252.0 / 255, green: 240.0 / 255, blue: 97.0 / 255)
    static let dark = (red: 216.0 / 255, green: 185.0 / 255, blue: 74.0 / 255)

    /// A new mark widget, drawn for its current width so it follows the window as it resizes. A
    /// strip with a `show` window's `footer` is the taller bar, with the footer's row over its
    /// lower part, under the notches.
    @MainActor
    static func widget(_ mark: WindowMark, footer: ShowFooter?, windowID: String) -> UnsafeMutableRawPointer {
        let area = gtk_drawing_area_new()!
        let drawingArea = UnsafeMutableRawPointer(area).assumingMemoryBound(to: GtkDrawingArea.self)
        let height = mark == .line ? lineHeight : footer == nil ? stripHeight : barHeight
        gtk_drawing_area_set_content_height(drawingArea, height)
        gtk_widget_set_hexpand(area, 1)
        gtk_drawing_area_set_draw_func(drawingArea, mark == .strip ? drawStrip : drawLine, nil, nil)
        guard mark == .strip, let footer else { return UnsafeMutableRawPointer(area) }
        let overlay = gtk_overlay_new()!
        let overlayView = OpaquePointer(overlay)
        gtk_overlay_set_child(overlayView, area)
        let row = LinuxShowFooter.widget(footer, windowID: windowID).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_valign(row, GTK_ALIGN_END)
        gtk_widget_set_size_request(row, -1, barHeight - Int32(notchDepth.rounded()))
        gtk_overlay_add_overlay(overlayView, row)
        // Measured with the bar, as the bottom bar was: the window cannot get narrower than the
        // row, which GtkOverlay would otherwise give its minimum width past the window's edge.
        gtk_overlay_set_measure_overlay(overlayView, row, 1)
        return UnsafeMutableRawPointer(overlay)
    }

    /// Makes Ctrl+W, GNOME's key for closing a window, close the window `mark` is in, wherever its
    /// focus is, as the title bar's close button does (gtk_window_close, which asks close-request)
    /// and as Command-W does on macOS. Every actionui-mcp window has the mark, so every one closes
    /// this way, kept windows too. It is a shortcut of the window's own, not the application's, which
    /// GTK runs before any widget. The window's shortcuts run before its content's managed ones (a
    /// view's keyboardShortcut, ViewShortcut), so it leaves the key to the content when one of those
    /// that is enabled and mapped takes it, as a macOS window's views see Command-W before the menu:
    /// a `show_ui` window's own Ctrl+W control keeps it. Put on the window when the mark is first
    /// realized, as the runtime adds the mark to the window after this returns.
    @MainActor
    static func closesWindow(_ mark: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
        g_signal_connect_data(mark, "realize", unsafeBitCast(markRealized, to: GCallback.self), nil, nil, GConnectFlags(rawValue: 0))
        return mark
    }

    private static let closeShortcutKey = "actionui-mcp-close-shortcut"

    private static let markRealized: @convention(c) (UnsafeMutablePointer<GtkWidget>?, gpointer?) -> Void = { mark, _ in
        guard let mark, let root = gtk_widget_get_root(mark) else { return }
        let window = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GObject.self)
        guard g_object_get_data(window, LinuxWindowMark.closeShortcutKey) == nil else { return }
        g_object_set_data(window, LinuxWindowMark.closeShortcutKey, UnsafeMutableRawPointer(window))
        guard let trigger = gtk_shortcut_trigger_parse_string("<Control>w") else { return }
        // Local and in the bubble phase, the defaults: the window's own key, after its children's.
        let controller = gtk_shortcut_controller_new()!
        let action = gtk_callback_action_new(LinuxWindowMark.closeWindow, UnsafeMutableRawPointer(controller), nil)
        gtk_shortcut_controller_add_shortcut(controller, gtk_shortcut_new(trigger, action))
        gtk_widget_add_controller(UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWidget.self), controller)
    }

    /// The shortcut's action: closes the window unless its content takes the key. False lets the
    /// key go on to the window's managed shortcuts.
    private static let closeWindow: GtkShortcutFunc = { window, _, controller in
        guard let window, let controller else { return 0 }
        if let event = gtk_event_controller_get_current_event(OpaquePointer(controller)),
           LinuxWindowMark.contentTakes(event, under: window) {
            return 0
        }
        gtk_window_close(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
        return 1
    }

    /// Whether a managed shortcut of a widget under `widget`, enabled and mapped, as GTK runs only
    /// those, answers `event`.
    private static func contentTakes(_ event: OpaquePointer, under widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if gtk_widget_is_sensitive(current) != 0, gtk_widget_get_mapped(current) != 0,
               hasShortcut(for: event, current) || contentTakes(event, under: current) {
                return true
            }
            child = gtk_widget_get_next_sibling(current)
        }
        return false
    }

    private static func hasShortcut(for event: OpaquePointer, _ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
        // A list GTK keeps up to date only while it is held: let go before returning.
        guard let controllers = gtk_widget_observe_controllers(widget) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            defer { g_object_unref(item) }
            guard g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_shortcut_controller_get_type()) != 0,
                  gtk_shortcut_controller_get_scope(OpaquePointer(item)) == GTK_SHORTCUT_SCOPE_MANAGED else { continue }
            let shortcuts = OpaquePointer(item)
            for position in 0..<g_list_model_get_n_items(shortcuts) {
                guard let shortcut = g_list_model_get_item(shortcuts, position) else { continue }
                defer { g_object_unref(shortcut) }
                // GTK's activate action (ViewShortcut's) fails, and lets the key go on, on a widget
                // with nothing to activate, as a keyboardShortcut on a Text: not taken then.
                if let trigger = gtk_shortcut_get_trigger(OpaquePointer(shortcut)),
                   gtk_shortcut_trigger_trigger(trigger, event, 0) != GDK_KEY_MATCH_NONE,
                   UnsafeRawPointer(gtk_shortcut_get_action(OpaquePointer(shortcut))) != UnsafeRawPointer(gtk_activate_action_get())
                    || activates(widget) {
                    return true
                }
            }
        }
        return false
    }

    /// Whether gtk_widget_activate does something for `widget`: its class has an activate signal.
    private static func activates(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
        guard let widgetClass = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self).pointee.g_class else { return false }
        return gtk_widget_class_get_activate_signal(UnsafeMutableRawPointer(widgetClass).assumingMemoryBound(to: GtkWidgetClass.self)) != 0
    }

    private static let drawStrip: GtkDrawingAreaDrawFunc = { _, cairo, width, height, _ in
        guard let cairo else { return }
        LinuxWindowMark.draw(cairo, width: Double(width), height: Double(height), depth: LinuxWindowMark.notchDepth)
    }

    private static let drawLine: GtkDrawingAreaDrawFunc = { _, cairo, width, height, _ in
        guard let cairo else { return }
        // 45 degrees: as far across as down, across the line's whole height.
        LinuxWindowMark.draw(cairo, width: Double(width), height: Double(height), depth: Double(height))
    }

    /// The gradient band, then the notches `depth` deep from the top edge.
    private static func draw(_ cairo: OpaquePointer, width: Double, height: Double, depth: Double) {
        fillGradient(cairo, width: width, height: height)
        cairo_set_source_rgb(cairo, 0.03, 0.03, 0.035)
        var x = -depth - notchSpacing
        while x < width {
            cairo_move_to(cairo, x, 0)
            cairo_line_to(cairo, x + notchWidth, 0)
            cairo_line_to(cairo, x + depth + notchWidth, depth)
            cairo_line_to(cairo, x + depth, depth)
            cairo_close_path(cairo)
            x += notchSpacing
        }
        cairo_fill(cairo)
    }

    /// The yellow, bright at the top and darker at the bottom, over the whole of `width` x `height`.
    static func fillGradient(_ cairo: OpaquePointer, width: Double, height: Double) {
        guard let gradient = cairo_pattern_create_linear(0, 0, 0, height) else { return }
        cairo_pattern_add_color_stop_rgb(gradient, 0, bright.red, bright.green, bright.blue)
        cairo_pattern_add_color_stop_rgb(gradient, 1, dark.red, dark.green, dark.blue)
        cairo_set_source(cairo, gradient)
        cairo_rectangle(cairo, 0, 0, width, height)
        cairo_fill(cairo)
        cairo_pattern_destroy(gradient)
    }
}
#endif
