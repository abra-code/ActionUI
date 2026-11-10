// Sources/Runtime/WindowSubtitle.swift
/*
 A window's subtitle (AdwaitaApplication.WindowOptions), the line a host counts on being there
 whatever the document does. It is a line of its own, not part of a header bar: a document can put
 its own items in place of a header bar's title (principal toolbar items) and brings its own header
 bars with a navigation container at its root.

 A sheet or a fullScreenCover can cover the whole window, this line included (libadwaita puts every
 AdwDialog in the window's dialog host, above the window's content), so each shows the line too.
 The subtitle is kept on the GTK window for them to find.

 A document sets how large a window or a sheet gets: a toolbar item makes the header bar taller than
 the screen, and a sheet can be wider and taller than its window, which then shows only the sheet's
 top left corner (measured with libadwaita 1.9). So the line is the first of the bars, above any
 header bar, and starts at the left: centered, it would be in the middle of a sheet 2000 wide, out
 of the window's sight.

 One line, however narrow its window or sheet, and it never sets their width: what does not fit is
 in its tooltip. It moves the window when dragged, as a header bar does.
*/

import CAdwaita

@MainActor
package enum WindowSubtitle {
    private final class Text {
        let value: String
        init(_ value: String) { self.value = value }
    }

    private static let key = AttachKey<Text>("actionui-window-subtitle")

    /// Keeps `subtitle` on `window`, for the sheets presented over it.
    package static func set(_ subtitle: String, on window: UnsafeMutablePointer<GtkWindow>) {
        attach(Text(subtitle), to: UnsafeMutableRawPointer(window), key: key)
    }

    /// The subtitle kept on `window`, nil when it has none.
    package static func subtitle(of window: UnsafeMutablePointer<GtkWindow>) -> String? {
        attached(on: UnsafeMutableRawPointer(window), key: key)?.value
    }

    /// The line to show in a sheet presented from `widget`, nil when its window has no subtitle.
    static func line(overWindowOf widget: WidgetPointer) -> WidgetPointer? {
        guard let root = gtk_widget_get_root(widget),
              let text = attached(on: UnsafeMutableRawPointer(root), key: key) else { return nil }
        return line(text.value)
    }

    /// The line showing `subtitle`.
    package static func line(_ subtitle: String) -> WidgetPointer {
        let label = gtk_label_new(subtitle)!
        gtk_label_set_ellipsize(opaque(label), PANGO_ELLIPSIZE_END)
        gtk_label_set_single_line_mode(opaque(label), 1)
        // Its natural width is then next to nothing, and it shows as much as its place allows.
        gtk_label_set_max_width_chars(opaque(label), 1)
        // At the left in every language: a sheet too large for its window starts there too.
        gtk_widget_set_direction(label, GTK_TEXT_DIR_LTR)
        gtk_label_set_xalign(opaque(label), 0)
        gtk_widget_set_tooltip_text(label, subtitle)
        Gtk.Widget(label).setCSSClass("caption", true)
        Gtk.Widget(label).setCSSClass("dim-label", true)
        gtk_widget_set_margin_start(label, 12)
        gtk_widget_set_margin_end(label, 12)
        gtk_widget_set_margin_top(label, 6)
        gtk_widget_set_margin_bottom(label, 6)
        let handle = gtk_window_handle_new()!
        gtk_window_handle_set_child(opaque(handle), label)
        return handle
    }
}
