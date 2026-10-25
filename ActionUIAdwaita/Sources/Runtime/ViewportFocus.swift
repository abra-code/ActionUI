// Sources/Runtime/ViewportFocus.swift
/*
 A scrolled view follows keyboard focus as GTK 4.20 makes it: a GtkViewport scrolls to the
 window's focus widget when focus moves inside it, but not when that widget is in a popover.
 Before 4.20, GTK also scrolled to a focused item of a popover parented inside the viewport (a
 Menu's, a Picker's, a context menu), so a list scrolled under the pointer when such a menu opened
 near its bottom edge and its item took the focus, and the next click missed. On those versions
 the viewport's own focus scrolling is turned off and replaced by the 4.20 rule: focus in another
 surface does not scroll it. On 4.20 and later GTK's own is kept.
*/

import CAdwaita

@MainActor
enum ViewportFocus {
    /// The window's focus handler while the viewport is mapped.
    @MainActor
    final class Follower {
        let viewport: WidgetPointer
        var root: UnsafeMutableRawPointer?
        var focusHandler: gulong = 0

        init(viewport: WidgetPointer) {
            self.viewport = viewport
        }

        isolated deinit {
            stop()
        }
    }

    static let followerKey = AttachKey<Follower>("actionui-viewport-focus")

    /// True when GTK scrolls a viewport to focus in a popover (before 4.20).
    static var gtkFollowsPopoverFocus: Bool {
        gtk_get_major_version() == 4 && gtk_get_minor_version() < 20
    }

    /// Makes the viewport GTK put around `scroller`'s child follow focus as GTK 4.20 does. Called
    /// after the child is set; nothing when the child scrolls itself (no viewport).
    static func follow(_ scroller: WidgetPointer) {
        guard gtkFollowsPopoverFocus, let viewport = gtk_scrolled_window_get_child(OpaquePointer(scroller)),
              Gtk.Widget(viewport).isA(gtk_viewport_get_type()) else { return }
        gtk_viewport_set_scroll_to_focus(OpaquePointer(viewport), 0)
        let follower = Follower(viewport: viewport)
        attach(follower, to: UnsafeMutableRawPointer(viewport), key: followerKey)
        // The window's focus while the viewport shows: a window outlives the widgets mapped in it.
        connectSignal(UnsafeMutableRawPointer(viewport), "map", .instanceOnly) { [weak follower] in
            guard let follower, follower.focusHandler == 0,
                  let root = gtk_widget_get_root(viewport) else { return }
            let window = UnsafeMutableRawPointer(root)
            follower.root = window
            follower.focusHandler = connectSignal(window, "notify::focus-widget", .instanceAndArgument) { [weak follower] in
                follower?.focusChanged()
            }
        }
        connectSignal(UnsafeMutableRawPointer(viewport), "unmap", .instanceOnly) { [weak follower] in
            follower?.stop()
        }
    }
}

extension ViewportFocus.Follower {
    /// GTK 4.20's focus_change_handler: scrolls to the focus widget when focus is inside the
    /// viewport and on its surface (a text field's GtkText is replaced by the field).
    func focusChanged() {
        guard let root,
              gtk_widget_get_state_flags(viewport).rawValue & GTK_STATE_FLAG_FOCUS_WITHIN.rawValue != 0,
              var focus = gtk_root_get_focus(OpaquePointer(root)) else { return }
        if Gtk.Widget(focus).isA(gtk_text_get_type()), let field = gtk_widget_get_parent(focus) {
            focus = field
        }
        guard gtk_widget_get_native(focus) == gtk_widget_get_native(viewport) else { return }
        gtk_viewport_scroll_to(OpaquePointer(viewport), focus, nil)
    }

    /// The viewport was unmapped: the window's handler goes.
    func stop() {
        if let root, focusHandler != 0 {
            g_signal_handler_disconnect(root, focusHandler)
        }
        focusHandler = 0
        root = nil
    }
}
