// Sources/Interop/GtkInterop.swift
/*
 Small helpers for calling GTK's C API from Swift: pointer conversions, signal handlers, Swift
 objects kept on GObjects, and timers on the GLib main loop.

 GTK 4 declares most widgets as final types, whose instance structs are opaque, so Swift imports
 their pointers as OpaquePointer; derivable types (GtkWidget, GtkWindow, GtkEntry) keep typed
 pointers. Conversions go through OpaquePointer either way.

 Lifetimes: a Swift object handed to C (a signal handler's closure, an attached object, a timer's
 closure) is retained for as long as GLib holds it and released by GLib's destroy notification:
 when the handler is disconnected, the object finalized, or the timer source removed. Swift never
 keeps a widget alive on its own; closures capture render nodes weakly.
*/

import CAdwaita

typealias WidgetPointer = UnsafeMutablePointer<GtkWidget>

@inline(__always) func typed<T>(_ pointer: OpaquePointer) -> UnsafeMutablePointer<T> {
    UnsafeMutablePointer<T>(pointer)
}

@inline(__always) func typed<T, U>(_ pointer: UnsafeMutablePointer<U>) -> UnsafeMutablePointer<T> {
    UnsafeMutablePointer<T>(OpaquePointer(pointer))
}

@inline(__always) func opaque<U>(_ pointer: UnsafeMutablePointer<U>) -> OpaquePointer {
    OpaquePointer(pointer)
}

/// A C string GTK returns (not owned by the caller), as a Swift string.
func swiftString(_ text: UnsafePointer<CChar>?) -> String? {
    guard let text else { return nil }
    return String(cString: text)
}

// MARK: - Signals

/// What a signal handler runs; retained by GLib for as long as the handler is connected.
@MainActor final class SignalAction {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
}

/// For signals whose handler takes (instance, user data).
private let twoArgumentTrampoline: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
    guard let data else { return }
    let action = Unmanaged<SignalAction>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { action.run() }
}

/// For signals whose handler takes (instance, one argument, user data), such as notify::.
private let threeArgumentTrampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, _, data in
    guard let data else { return }
    let action = Unmanaged<SignalAction>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { action.run() }
}

/// For a click gesture's "pressed" and "released": (instance, press count, x, y, user data). The
/// doubles travel in floating-point registers, so the user data is not where a three-pointer
/// trampoline would look.
private let pressTrampoline: @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void = { _, _, _, _, data in
    guard let data else { return }
    let action = Unmanaged<SignalAction>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { action.run() }
}

/// A key controller's "key-released" handler, given the key's value.
@MainActor
private final class KeyAction {
    let run: @MainActor (guint) -> Void
    init(_ run: @escaping @MainActor (guint) -> Void) { self.run = run }
}

/// For a key controller's "key-released": (instance, keyval, keycode, state, user data), all in
/// integer registers.
private let keyReleasedTrampoline: @convention(c) (gpointer?, guint, guint, guint, gpointer?) -> Void = { _, keyval, _, _, data in
    guard let data else { return }
    let action = Unmanaged<KeyAction>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { action.run(keyval) }
}

private let releaseKeyAction: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
    guard let data else { return }
    Unmanaged<KeyAction>.fromOpaque(data).release()
}

/// Connects `run` to a key controller's "key-released", with the released key's value (GDK_KEY_*).
@MainActor @discardableResult
func connectKeyReleased(_ controller: UnsafeMutableRawPointer, _ run: @escaping @MainActor (guint) -> Void) -> gulong {
    let data = Unmanaged.passRetained(KeyAction(run)).toOpaque()
    let id = g_signal_connect_data(controller, "key-released", unsafeBitCast(keyReleasedTrampoline, to: GCallback.self),
                                   data, releaseKeyAction, GConnectFlags(0))
    if id == 0 {
        Unmanaged<KeyAction>.fromOpaque(data).release()
    }
    return id
}

private let releaseSignalAction: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
    guard let data else { return }
    Unmanaged<SignalAction>.fromOpaque(data).release()
}

/// The C signature of a signal's handler, which decides the trampoline.
enum SignalShape {
    /// (instance, user data): "clicked", "activate", "changed", "map", "destroy"
    case instanceOnly
    /// (instance, argument, user data): "notify::<property>"
    case instanceAndArgument
    /// (instance, press count, x, y, user data): a GtkGestureClick's "pressed" and "released"
    case press
}

/// Connects `run` to `signal` on a GObject, whatever caused the signal. For a signal a user's
/// input emits, use connectUserSignal, which also ignores the signal while a renderer updates
/// the widget. With `after`, `run` runs after the signal's default handler. Returns GLib's handler
/// id (0 if the signal does not exist, which GLib logs).
@MainActor @discardableResult
func connectSignal(_ instance: UnsafeMutableRawPointer, _ signal: String, _ shape: SignalShape, after: Bool = false,
                   _ run: @escaping @MainActor () -> Void) -> gulong {
    let data = Unmanaged.passRetained(SignalAction(run)).toOpaque()
    let callback: GCallback
    switch shape {
    case .instanceOnly:
        callback = unsafeBitCast(twoArgumentTrampoline, to: GCallback.self)
    case .instanceAndArgument:
        callback = unsafeBitCast(threeArgumentTrampoline, to: GCallback.self)
    case .press:
        callback = unsafeBitCast(pressTrampoline, to: GCallback.self)
    }
    // GLib calls releaseSignalAction once a connected handler is gone. When connecting fails (an
    // unknown signal, which GLib logs) it never calls it, so the action is released here.
    // G_CONNECT_AFTER (1): after the signal's default handler, which does the work of "undo".
    let id = g_signal_connect_data(instance, signal, callback, data, releaseSignalAction, GConnectFlags(after ? 1 : 0))
    if id == 0 {
        Unmanaged<SignalAction>.fromOpaque(data).release()
    }
    return id
}

/// Connects `run` to a signal that a user's input emits ("clicked", "changed", "notify::active").
/// GTK emits the same signals when code changes the widget, synchronously, so `run` is skipped
/// while UpdateGuard says a renderer is applying the model to widgets: only the user's changes
/// reach actions and the model.
@MainActor @discardableResult
func connectUserSignal(_ instance: UnsafeMutableRawPointer, _ signal: String, _ shape: SignalShape,
                       _ run: @escaping @MainActor () -> Void) -> gulong {
    connectSignal(instance, signal, shape) {
        guard !UpdateGuard.isApplying else { return }
        run()
    }
}

/// What a handler given the signal's argument runs; retained by GLib while it is connected.
@MainActor final class ObjectSignalAction {
    let run: @MainActor (UnsafeMutableRawPointer) -> Void
    init(_ run: @escaping @MainActor (UnsafeMutableRawPointer) -> Void) { self.run = run }
}

/// For signals whose handler takes (instance, object, user data) and needs the object, such as a
/// list item factory's "setup" and "bind".
private let objectArgumentTrampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, object, data in
    guard let object, let data else { return }
    let action = Unmanaged<ObjectSignalAction>.fromOpaque(data).takeUnretainedValue()
    // A pointer is not Sendable; its address is. GLib emits on the main thread.
    let address = UInt(bitPattern: object)
    MainActor.assumeIsolated { action.run(UnsafeMutableRawPointer(bitPattern: address)!) }
}

private let releaseObjectSignalAction: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
    guard let data else { return }
    Unmanaged<ObjectSignalAction>.fromOpaque(data).release()
}

/// Connects `run` to a signal whose handler takes one object argument (instance, object, user
/// data), passing the object: a list item factory's "setup", "bind" and "unbind". Not for user
/// input, which goes through connectUserSignal. Returns GLib's handler id (0 if the signal does
/// not exist).
@MainActor @discardableResult
func connectObjectSignal(_ instance: UnsafeMutableRawPointer, _ signal: String,
                         _ run: @escaping @MainActor (UnsafeMutableRawPointer) -> Void) -> gulong {
    let data = Unmanaged.passRetained(ObjectSignalAction(run)).toOpaque()
    let callback = unsafeBitCast(objectArgumentTrampoline, to: GCallback.self)
    let id = g_signal_connect_data(instance, signal, callback, data, releaseObjectSignalAction, GConnectFlags(0))
    if id == 0 {
        Unmanaged<ObjectSignalAction>.fromOpaque(data).release()
    }
    return id
}

/// What a handler that answers its signal runs; retained by GLib while it is connected.
@MainActor final class BooleanSignalAction {
    let run: @MainActor () -> Bool
    init(_ run: @escaping @MainActor () -> Bool) { self.run = run }
}

/// For signals whose handler takes (instance, user data) and returns a gboolean, such as
/// GtkWindow's "close-request".
private let booleanTrampoline: @convention(c) (gpointer?, gpointer?) -> gboolean = { _, data in
    guard let data else { return 0 }
    let action = Unmanaged<BooleanSignalAction>.fromOpaque(data).takeUnretainedValue()
    return MainActor.assumeIsolated { action.run() } ? 1 : 0
}

private let releaseBooleanSignalAction: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
    guard let data else { return }
    Unmanaged<BooleanSignalAction>.fromOpaque(data).release()
}

/// Connects `run` to a signal whose handler returns a gboolean (instance, user data), and
/// returns its answer to GTK: for "close-request", true keeps the window open. Returns GLib's
/// handler id (0 if the signal does not exist).
@MainActor @discardableResult
func connectBooleanSignal(_ instance: UnsafeMutableRawPointer, _ signal: String,
                          _ run: @escaping @MainActor () -> Bool) -> gulong {
    let data = Unmanaged.passRetained(BooleanSignalAction(run)).toOpaque()
    let callback = unsafeBitCast(booleanTrampoline, to: GCallback.self)
    let id = g_signal_connect_data(instance, signal, callback, data, releaseBooleanSignalAction, GConnectFlags(0))
    if id == 0 {
        Unmanaged<BooleanSignalAction>.fromOpaque(data).release()
    }
    return id
}

// MARK: - Widgets with an accessible role

/// A new widget of `type` with `role` as its accessible role, which can only be set when the
/// widget is made. It comes with GTK's floating reference, as gtk_*_new returns.
func newWidget(_ type: GType, accessibleRole role: GtkAccessibleRole) -> WidgetPointer {
    let name: StaticString = "accessible-role"
    var names: [UnsafePointer<CChar>?] = [UnsafeRawPointer(name.utf8Start).assumingMemoryBound(to: CChar.self)]
    var value = GValue()
    g_value_init(&value, gtk_accessible_role_get_type())
    g_value_set_enum(&value, Int32(role.rawValue))
    let widget: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(type, 1, &names, &value)!))
    g_value_unset(&value)
    return widget
}

/// Writes a widget's value range and current value for assistive technologies (a meter or a
/// progress bar drawn by ActionUI, which GTK knows nothing about).
func setAccessibleValue(_ widget: WidgetPointer, min: Double, max: Double, now: Double) {
    var properties = [GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, GTK_ACCESSIBLE_PROPERTY_VALUE_NOW]
    var values = [GValue(), GValue(), GValue()]
    for (index, (property, value)) in zip(properties, [min, max, now]).enumerated() {
        gtk_accessible_property_init_value(property, &values[index])
        g_value_set_double(&values[index], value)
    }
    gtk_accessible_update_property_value(OpaquePointer(widget), Int32(properties.count), &properties, &values)
    for index in values.indices {
        g_value_unset(&values[index])
    }
}

/// Sets a widget's accessible name (a part with no text of its own: a stepper's buttons, a date
/// picker's hour and minute fields).
func setAccessibleLabel(_ widget: WidgetPointer, _ name: String) {
    var value = GValue()
    gtk_accessible_property_init_value(GTK_ACCESSIBLE_PROPERTY_LABEL, &value)
    g_value_set_string(&value, name)
    var property = GTK_ACCESSIBLE_PROPERTY_LABEL
    gtk_accessible_update_property_value(OpaquePointer(widget), 1, &property, &value)
    g_value_unset(&value)
}

// MARK: - Swift objects kept on GObjects

private let releaseAttached: @convention(c) (gpointer?) -> Void = { data in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

/// Keeps `value` on a GObject under `key`, released when the object is finalized or the key is
/// set again.
@MainActor func attach(_ value: AnyObject, to object: UnsafeMutableRawPointer, key: String) {
    let retained = Unmanaged.passRetained(value).toOpaque()
    g_object_set_data_full(typed(OpaquePointer(object)), key, retained, releaseAttached)
}

/// The object attach kept on `object` under `key`, if it is a `T`.
@MainActor func attached<T: AnyObject>(_ type: T.Type, on object: UnsafeMutableRawPointer, key: String) -> T? {
    guard let data = g_object_get_data(typed(OpaquePointer(object)), key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(data).takeUnretainedValue() as? T
}

// MARK: - Timers

/// What a timer runs; retained by GLib until its source is removed.
@MainActor final class TimerAction {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
}

private let runTimerOnce: @convention(c) (gpointer?) -> gboolean = { data in
    guard let data else { return 0 }
    let action = Unmanaged<TimerAction>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { action.run() }
    return 0  // G_SOURCE_REMOVE
}

private let releaseTimerAction: @convention(c) (gpointer?) -> Void = { data in
    guard let data else { return }
    Unmanaged<TimerAction>.fromOpaque(data).release()
}

/// Runs `run` once on the GLib main loop after `milliseconds`. Returns the source id, which
/// g_source_remove cancels. DispatchQueue.main.asyncAfter works too (MainLoopBridge); there is no
/// Timer or RunLoop in FoundationEssentials.
@MainActor @discardableResult
func runAfter(milliseconds: UInt32, _ run: @escaping @MainActor () -> Void) -> guint {
    let data = Unmanaged.passRetained(TimerAction(run)).toOpaque()
    return g_timeout_add_full(G_PRIORITY_DEFAULT, milliseconds, runTimerOnce, data, releaseTimerAction)
}
