// Sources/Runtime/UpdateGuard.swift
/*
 Tells user input from a renderer's own changes. GTK emits a widget's signals also when code
 changes the widget ("changed" from gtk_editable_set_text, "notify::active" from
 gtk_switch_set_active), synchronously, inside the call. SwiftUI fires an element's actions only
 for the user's changes, so every renderer update runs inside `applying`, and the handlers that
 connectUserSignal connects return at once while it runs.

 Signals that libadwaita emits later, after an animation (a navigation page popped, a dialog
 closed), arrive when `applying` has long returned; their handlers compare the widget with the
 model instead.
*/

@MainActor enum UpdateGuard {
    private static var depth = 0

    /// True while a renderer applies the model to widgets.
    static var isApplying: Bool { depth > 0 }

    /// Runs `body` as a renderer update. Nests: an update that syncs a child counts once.
    static func applying<T>(_ body: () throws -> T) rethrows -> T {
        depth += 1
        defer { depth -= 1 }
        return try body()
    }
}
