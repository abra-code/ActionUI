// Sources/Runtime/WindowAssembly.swift
/*
 Fills a GTK window with a document as ActionUI shows one, whoever made the window: ActionUI's own
 application (AdwaitaApplication) for the windows it presents, and a host that makes its own
 windows (HostWindow, actionUILoadIntoHostWindow*). So a host's window and ActionUI's look the same:
 the subtitle line, the header bar with the document's toolbars and the primary menu, the toast
 overlay, scrolling for a document larger than the monitor, and the opening size.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
package enum WindowAssembly {
    /// Apple's fallback window size when the content reports almost none.
    package static let fallbackSize = (width: Int32(480), height: Int32(320))
    /// The widest a window opens unless its content's minimum needs more: SwiftUI's WindowGroup
    /// opens 900 points wide on macOS (measured on macOS 27, whatever the content), so a long
    /// line of text does not open a window as wide as the monitor.
    package static let openingWidth = 900
    /// The least a window opens tall when its content grows vertically (a List, a ScrollView, a
    /// Table, a Color): SwiftUI's WindowGroup gives its content 418 points (macOS 27), so an
    /// empty List waiting for its rows does not open as a strip.
    package static let openingHeight: Int32 = 418

    /// Fills `toolbar`, an AdwToolbarView already the content of `window` (so the bars have their
    /// style when measured): the subtitle line (none when nil or empty), the header bar with the
    /// document's toolbars and the primary menu unless the document brings its own header bars,
    /// and `content` below them, scrolled when its minimum is larger than the monitor. With
    /// `presents`, the document's modals, dialogs and toasts start showing. `contentSize` (below
    /// the bars; a side of zero or less keeps the document's) overrides the document's size.
    /// Returns the window's opening size, bars included, no larger than the monitor.
    package static func assemble(_ window: UnsafeMutablePointer<GtkWindow>, toolbar: WidgetPointer, content: WidgetPointer,
                                 renderTree: AdwaitaWindow?, windowUUID: String, subtitle: String?,
                                 contentSize: (width: Int, height: Int)?, presents: Bool) -> (width: Int32, height: Int32) {
        // First of the bars, where a document's toolbar items cannot push it away (WindowSubtitle).
        if let subtitle, !subtitle.isEmpty {
            WindowSubtitle.set(subtitle, on: window)
            let line = WindowSubtitle.line(subtitle)
            adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), line)
        }
        // A document that brings its own header bars (a NavigationStack's pages) gets none here.
        if renderTree?.showsOwnHeaderBars != true {
            let header = adw_header_bar_new()!
            adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
            // The primary menu at the end, outside the toolbars' items.
            adw_header_bar_pack_end(OpaquePointer(header), AppCommands.shared.makeMenuButton())
            // The document's toolbars show in it.
            renderTree?.root?.screenBar = ScreenBar(header: header, toolbarView: toolbar)
        } else {
            // The document's own header bars carry the primary menu.
            renderTree?.root?.showsPrimaryMenu = true
        }
        // Measured in the window, where the bars have their style, and together, as stacked bars
        // share their padding. The view has no content yet: this is the bars alone.
        let barsHeight = Int32(clamping: Gtk.Widget(toolbar).measure(GTK_ORIENTATION_VERTICAL).natural)
        let monitor = monitorSize()
        let (minimum, natural) = contentSizes(content, widthCap: monitor.width)
        // The window's minimum is the content's plus the bars'.
        // Toasts show over the content, below the bars.
        let toastOverlay = adw_toast_overlay_new()!
        adw_toolbar_view_set_content(OpaquePointer(toolbar), toastOverlay)
        if minimum.width > monitor.width || Int(minimum.height) + Int(barsHeight) > Int(monitor.height) {
            ActionUIModel.shared.logger.log("Window \(windowUUID): the document's minimum size \(minimum.width) x \(minimum.height) is larger than the screen; it scrolls", .warning)
            let scroller = gtk_scrolled_window_new()!
            gtk_scrolled_window_set_child(opaque(scroller), content)
            ViewportFocus.follow(scroller)
            adw_toast_overlay_set_child(OpaquePointer(toastOverlay), scroller)
        } else {
            adw_toast_overlay_set_child(OpaquePointer(toastOverlay), content)
        }
        if presents {
            renderTree?.startPresenting(over: toastOverlay, toastOverlay: OpaquePointer(toastOverlay))
        }

        let small = natural.width < 10 || natural.height < 10
        var width = small ? fallbackSize.width : natural.width
        let grows = gtk_widget_compute_expand(content, GTK_ORIENTATION_VERTICAL) != 0
        var height = max(small ? fallbackSize.height : natural.height, grows ? openingHeight : 0)
        if let size = contentSize {
            if size.width > 0 { width = Int32(clamping: size.width) }
            if size.height > 0 { height = Int32(clamping: size.height) }
        }
        let windowHeight = min(Int(height) + Int(barsHeight), Int(monitor.height))
        return (min(width, monitor.width), Int32(windowHeight))
    }

    /// A window's content when its document could not be loaded: the error, selectable.
    package static func errorContent(_ message: String) -> WidgetPointer {
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
    private static func contentSizes(_ content: WidgetPointer, widthCap: Int32) -> (minimum: (width: Int32, height: Int32), natural: (width: Int32, height: Int32)) {
        let minimumWidth = Gtk.Widget(content).measure(GTK_ORIENTATION_HORIZONTAL).minimum
        let natural = askingForScrolledContent(in: content) {
            let width = Gtk.Widget(content).measure(GTK_ORIENTATION_HORIZONTAL)
            let opening = max(min(width.natural, Int(widthCap), max(openingWidth, minimumWidth)), minimumWidth)
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
    private static func askingForScrolledContent<Result>(in content: WidgetPointer, _ measure: () -> Result) -> Result {
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
    private static func monitorSize() -> (width: Int32, height: Int32) {
        guard let display = gdk_display_get_default(), let monitors = gdk_display_get_monitors(display),
              g_list_model_get_n_items(monitors) > 0, let item = g_list_model_get_item(monitors, 0) else {
            return (8192, 8192)
        }
        let monitor = OwnedObject(adopting: item)
        var geometry = GdkRectangle()
        gdk_monitor_get_geometry(monitor.opaquePointer, &geometry)
        return (geometry.width, geometry.height)
    }
}
