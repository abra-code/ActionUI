// Sources/Runtime/ViewShortcut.swift
/*
 A view's keyboardShortcut (a base modifier) on GTK: the key, pressed anywhere in the view's
 window, activates the element's widget, as SwiftUI's keyboardShortcut triggers a control from
 anywhere in its window. Activating does what the keyboard does to the control: a Button presses
 and fires its action (GTK's "clicked" after its press animation), a Toggle toggles, a Menu or
 Picker opens; a view with nothing to activate ignores it, as SwiftUI's do. A disabled control is
 not activated (GTK skips insensitive and unmapped widgets); a hidden one still is, since hidden
 keeps the widget mapped (transparent, not targetable). The controller goes on the control GTK
 activates (the renderer's accessibleWidget: a switch toggle's switch, not its box).

 The key and modifiers are read as the menu commands read theirs (AppCommands.accelerator):
 command and control are Ctrl, option Alt, shift Shift, an empty list the bare key.

 A button whose shortcut is the bare Return is also its window's default widget, as macOS makes
 it the default button: Return in a text field that leaves Return to the window (one without an
 action of its own) presses it too.
*/

import CAdwaita

@MainActor
enum ViewShortcut {
    /// The shortcut controller installed on a widget, with its accelerator.
    final class Installed {
        let controller: OpaquePointer
        let accelerator: String
        /// The "map" handler that makes a default button its window's default widget, 0 for none.
        var mapHandler: gulong = 0

        init(controller: OpaquePointer, accelerator: String) {
            self.controller = controller
            self.accelerator = accelerator
        }
    }

    static let installedKey = AttachKey<Installed>("actionui-view-shortcut")

    /// Makes `widget` (an element's widget) answer `shortcut`, replacing the shortcut it had; nil
    /// takes it away.
    static func apply(_ shortcut: BaseModifiers.KeyboardShortcut?, to widget: WidgetPointer) {
        let accelerator = shortcut.flatMap { AppCommands.accelerator(key: $0.key, modifiers: $0.modifiers) }
        let installed = attached(on: widget, key: installedKey)
        guard installed?.accelerator != accelerator else { return }
        if let installed {
            gtk_widget_remove_controller(widget, installed.controller)
            if installed.mapHandler != 0 {
                g_signal_handler_disconnect(UnsafeMutableRawPointer(widget), installed.mapHandler)
                if let window = rootWindow(widget), gtk_window_get_default_widget(window) == widget {
                    gtk_window_set_default_widget(window, nil)
                }
            }
            g_object_set_data(typed(OpaquePointer(widget)), installedKey.name, nil)
        }
        guard let accelerator, let trigger = gtk_shortcut_trigger_parse_string(accelerator) else { return }
        // The managed scope: the window handles the key wherever its focus is.
        let controller = gtk_shortcut_controller_new()!
        gtk_shortcut_controller_set_scope(controller, GTK_SHORTCUT_SCOPE_MANAGED)
        // gtk_activate_action_get is the shared action without a reference; the shortcut takes one.
        let action = gtk_activate_action_get()!
        g_object_ref(UnsafeMutableRawPointer(action))
        gtk_shortcut_controller_add_shortcut(controller, gtk_shortcut_new(trigger, action))
        gtk_widget_add_controller(widget, controller)
        let record = Installed(controller: controller, accelerator: accelerator)
        attach(record, to: UnsafeMutableRawPointer(widget), key: installedKey)
        if accelerator == "Return", Gtk.Widget(widget).isA(gtk_button_get_type()) {
            // The window's default widget once the button is in a window (and each time it shows
            // again, after another default button had the place).
            record.mapHandler = connectSignal(UnsafeMutableRawPointer(widget), "map", .instanceOnly) {
                makeDefault(widget)
            }
            if gtk_widget_get_mapped(widget) != 0 {
                makeDefault(widget)
            }
        }
    }

    private static func makeDefault(_ widget: WidgetPointer) {
        if let window = rootWindow(widget), gtk_window_get_default_widget(window) != widget {
            gtk_window_set_default_widget(window, widget)
        }
    }

    /// The window `widget` is in, if any.
    private static func rootWindow(_ widget: WidgetPointer) -> UnsafeMutablePointer<GtkWindow>? {
        guard let root = gtk_widget_get_root(widget) else { return nil }
        let rootWidget: WidgetPointer = typed(root)
        return Gtk.Widget(rootWidget).isA(gtk_window_get_type()) ? typed(root) : nil
    }
}
