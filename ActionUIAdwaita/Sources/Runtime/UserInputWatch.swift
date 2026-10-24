// Sources/Runtime/UserInputWatch.swift
/*
 Tells a selection the user made from one GTK made itself. A list box or column view selects on
 the user's click or key press, and also when it moves focus onto a row (the first one when the
 window gives the list its first focus), or when its rows change; SwiftUI fires actions only for
 the user's choices. The watch sees the widget's clicks and key presses in the capture phase,
 before the widget handles them, and marks the time until the main loop runs after them as the
 user's. Shared by List and Table.
*/

import CAdwaita

@MainActor
final class UserInputWatch {
    /// True from a click in the widget until the main loop runs after the click ends, and from a
    /// key press until the main loop runs after it: a selection made then is the user's.
    var isActive = false
    /// Counts the presses: the end of an earlier one does not end a later one.
    private var serial = 0

    /// Watches `widget`'s clicks (until the main loop runs after the gesture ends: released or
    /// canceled; "stopped" also comes while the button is down: the double-click timer, a press
    /// away from the last click, a small drag) and key presses (until the main loop runs after the
    /// press: the widget selects while handling it; a key that moves focus out sends its release
    /// elsewhere).
    init(watching widget: WidgetPointer) {
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, 0)
        gtk_event_controller_set_propagation_phase(click, GTK_PHASE_CAPTURE)
        connectSignal(UnsafeMutableRawPointer(click), "pressed", .press) { [weak self] in self?.begin() }
        connectSignal(UnsafeMutableRawPointer(click), "end", .instanceAndArgument) { [weak self] in self?.end() }
        gtk_widget_add_controller(widget, click)
        let keys = gtk_event_controller_key_new()!
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE)
        connectKeyPressed(UnsafeMutableRawPointer(keys)) { [weak self] _ in
            self?.begin()
            self?.end()
            return false
        }
        gtk_widget_add_controller(widget, keys)
    }

    private func begin() {
        isActive = true
        serial &+= 1
    }

    /// After the event's handlers (a list selects on a click's release) have run, unless another
    /// press came first.
    private func end() {
        let serial = serial
        runAfter(milliseconds: 0) { [weak self] in
            guard let self, self.serial == serial else { return }
            self.isActive = false
        }
    }
}
