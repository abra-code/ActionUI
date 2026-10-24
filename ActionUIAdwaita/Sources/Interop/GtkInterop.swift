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

/// A Swift closure handed to GLib (a signal handler, a timer): retained while GLib holds it, and
/// released by GLib's destroy notification (releaseClosureBox, releaseObject).
@MainActor final class CallbackBox<Run> {
    let run: Run
    init(_ run: Run) { self.run = run }
}

/// The box behind a callback's user data, which GLib passes back unchanged.
private func callbackBox<Run>(_ data: gpointer) -> CallbackBox<Run> {
    Unmanaged<CallbackBox<Run>>.fromOpaque(data).takeUnretainedValue()
}

/// GLib's destroy notification for a signal handler's box, whatever its closure type.
private let releaseClosureBox: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

/// Connects `callback`, a trampoline that runs a CallbackBox<Run>, to `signal`, with `run` in the
/// box. GLib calls releaseClosureBox once a connected handler is gone; when connecting fails (an
/// unknown signal, which GLib logs) it never calls it, so the box is released here. Returns GLib's
/// handler id, 0 on failure.
@MainActor
private func connectBox<Run>(_ instance: UnsafeMutableRawPointer, _ signal: String, _ callback: GCallback,
                          after: Bool = false, _ run: Run) -> gulong {
    let data = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
    // G_CONNECT_AFTER (1): after the signal's default handler.
    let id = g_signal_connect_data(instance, signal, callback, data, releaseClosureBox, GConnectFlags(after ? 1 : 0))
    if id == 0 {
        Unmanaged<CallbackBox<Run>>.fromOpaque(data).release()
    }
    return id
}

/// A handler that takes nothing and returns nothing, whatever the signal passes.
typealias SignalRun = @MainActor () -> Void

/// For signals whose handler takes (instance, user data).
private let twoArgumentTrampoline: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
    guard let data else { return }
    let box: CallbackBox<SignalRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run() }
}

/// For signals whose handler takes (instance, one argument, user data), such as notify::.
private let threeArgumentTrampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, _, data in
    guard let data else { return }
    let box: CallbackBox<SignalRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run() }
}

/// For a click gesture's "pressed" and "released": (instance, press count, x, y, user data). The
/// doubles travel in floating-point registers, so the user data is not where a three-pointer
/// trampoline would look.
private let pressTrampoline: @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void = { _, _, _, _, data in
    guard let data else { return }
    let box: CallbackBox<SignalRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run() }
}

private typealias KeyRun = @MainActor (guint) -> Void

/// For a key controller's "key-released": (instance, keyval, keycode, state, user data), all in
/// integer registers.
private let keyReleasedTrampoline: @convention(c) (gpointer?, guint, guint, guint, gpointer?) -> Void = { _, keyval, _, _, data in
    guard let data else { return }
    let box: CallbackBox<KeyRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run(keyval) }
}

/// Connects `run` to a key controller's "key-released", with the released key's value (GDK_KEY_*).
@MainActor @discardableResult
func connectKeyReleased(_ controller: UnsafeMutableRawPointer, _ run: @escaping @MainActor (guint) -> Void) -> gulong {
    connectBox(controller, "key-released", unsafeBitCast(keyReleasedTrampoline, to: GCallback.self), run as KeyRun)
}

private typealias KeyPressRun = @MainActor (guint) -> Bool

/// For a key controller's "key-pressed": (instance, keyval, keycode, state, user data), all in
/// integer registers, returning whether the key was handled.
private let keyPressedTrampoline: @convention(c) (gpointer?, guint, guint, guint, gpointer?) -> gboolean = { _, keyval, _, _, data in
    guard let data else { return 0 }
    let box: CallbackBox<KeyPressRun> = callbackBox(data)
    return MainActor.assumeIsolated { box.run(keyval) } ? 1 : 0
}

/// Connects `run` to a key controller's "key-pressed", with the pressed key's value (GDK_KEY_*);
/// `run` returns true when it handled the key, which stops it there.
@MainActor @discardableResult
func connectKeyPressed(_ controller: UnsafeMutableRawPointer, _ run: @escaping @MainActor (guint) -> Bool) -> gulong {
    connectBox(controller, "key-pressed", unsafeBitCast(keyPressedTrampoline, to: GCallback.self), run as KeyPressRun)
}

private typealias PositionRun = @MainActor (guint) -> Void

/// For signals whose handler takes (instance, position, user data), the position a guint in an
/// integer register: GtkColumnView's and GtkListView's "activate".
private let positionTrampoline: @convention(c) (gpointer?, guint, gpointer?) -> Void = { _, position, data in
    guard let data else { return }
    let box: CallbackBox<PositionRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run(position) }
}

/// Connects `run` to a signal whose handler takes a position in a list model (see
/// positionTrampoline).
@MainActor @discardableResult
func connectPosition(_ instance: UnsafeMutableRawPointer, _ signal: String, _ run: @escaping @MainActor (guint) -> Void) -> gulong {
    connectBox(instance, signal, unsafeBitCast(positionTrampoline, to: GCallback.self), run as PositionRun)
}

private typealias PointRun = @MainActor (Double, Double) -> Void

/// For signals whose handler takes (instance, x, y, user data): a drag gesture's "drag-begin",
/// "drag-update" and "drag-end" (an offset for the last two), a motion controller's "motion" and
/// "enter". The doubles travel in floating-point registers.
private let pointTrampoline: @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void = { _, x, y, data in
    guard let data else { return }
    let box: CallbackBox<PointRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run(x, y) }
}

/// Connects `run` to a signal whose handler takes a point or an offset (see pointTrampoline).
@MainActor @discardableResult
func connectPoint(_ instance: UnsafeMutableRawPointer, _ signal: String, _ run: @escaping @MainActor (Double, Double) -> Void) -> gulong {
    connectBox(instance, signal, unsafeBitCast(pointTrampoline, to: GCallback.self), run as PointRun)
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
/// the widget. With `after`, `run` runs after the signal's default handler (which does the work of
/// "undo"). Returns GLib's handler id (0 if the signal does not exist, which GLib logs).
@MainActor @discardableResult
func connectSignal(_ instance: UnsafeMutableRawPointer, _ signal: String, _ shape: SignalShape, after: Bool = false,
                   _ run: @escaping @MainActor () -> Void) -> gulong {
    let callback: GCallback
    switch shape {
    case .instanceOnly:
        callback = unsafeBitCast(twoArgumentTrampoline, to: GCallback.self)
    case .instanceAndArgument:
        callback = unsafeBitCast(threeArgumentTrampoline, to: GCallback.self)
    case .press:
        callback = unsafeBitCast(pressTrampoline, to: GCallback.self)
    }
    return connectBox(instance, signal, callback, after: after, run as SignalRun)
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

private typealias ObjectRun = @MainActor (UnsafeMutableRawPointer) -> Void

/// For signals whose handler takes (instance, object, user data) and needs the object, such as a
/// list item factory's "setup" and "bind".
private let objectArgumentTrampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, object, data in
    guard let object, let data else { return }
    let box: CallbackBox<ObjectRun> = callbackBox(data)
    // A pointer is not Sendable; its address is. GLib emits on the main thread.
    let address = UInt(bitPattern: object)
    MainActor.assumeIsolated { box.run(UnsafeMutableRawPointer(bitPattern: address)!) }
}

/// Connects `run` to a signal whose handler takes one object argument (instance, object, user
/// data), passing the object: a list item factory's "setup", "bind" and "unbind". Not for user
/// input, which goes through connectUserSignal. Returns GLib's handler id (0 if the signal does
/// not exist).
@MainActor @discardableResult
func connectObjectSignal(_ instance: UnsafeMutableRawPointer, _ signal: String,
                         _ run: @escaping @MainActor (UnsafeMutableRawPointer) -> Void) -> gulong {
    connectBox(instance, signal, unsafeBitCast(objectArgumentTrampoline, to: GCallback.self), run as ObjectRun)
}

private typealias BooleanRun = @MainActor () -> Bool

/// For signals whose handler takes (instance, user data) and returns a gboolean, such as
/// GtkWindow's "close-request".
private let booleanTrampoline: @convention(c) (gpointer?, gpointer?) -> gboolean = { _, data in
    guard let data else { return 0 }
    let box: CallbackBox<BooleanRun> = callbackBox(data)
    return MainActor.assumeIsolated { box.run() } ? 1 : 0
}

/// Connects `run` to a signal whose handler returns a gboolean (instance, user data), and
/// returns its answer to GTK: for "close-request", true keeps the window open. Returns GLib's
/// handler id (0 if the signal does not exist).
@MainActor @discardableResult
func connectBooleanSignal(_ instance: UnsafeMutableRawPointer, _ signal: String,
                          _ run: @escaping @MainActor () -> Bool) -> gulong {
    connectBox(instance, signal, unsafeBitCast(booleanTrampoline, to: GCallback.self), run as BooleanRun)
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

/// GLib's destroy notification for a retained Swift object (an attached object, a timer's box).
private let releaseObject: @convention(c) (gpointer?) -> Void = { data in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

/// The name a Swift object is kept under on a GObject (GObject data), and the object's type, so a
/// key can only store and return its own type.
struct AttachKey<Value: AnyObject>: Sendable {
    let name: String
    init(_ name: String) { self.name = name }
}

/// Keeps `value` on a GObject under `key`, released when the object is finalized or the key is
/// set again.
@MainActor func attach<Value>(_ value: Value, to object: UnsafeMutableRawPointer, key: AttachKey<Value>) {
    let retained = Unmanaged.passRetained(value as AnyObject).toOpaque()
    g_object_set_data_full(typed(OpaquePointer(object)), key.name, retained, releaseObject)
}

/// The object attach kept on `object` under `key`; nil when there is none, or when another key of
/// the same name stored another type.
@MainActor func attached<Value>(on object: UnsafeMutableRawPointer, key: AttachKey<Value>) -> Value? {
    guard let data = g_object_get_data(typed(OpaquePointer(object)), key.name) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(data).takeUnretainedValue() as? Value
}

// MARK: - Timers

private let runTimerOnce: @convention(c) (gpointer?) -> gboolean = { data in
    guard let data else { return 0 }
    let box: CallbackBox<SignalRun> = callbackBox(data)
    MainActor.assumeIsolated { box.run() }
    return 0  // G_SOURCE_REMOVE
}

/// Runs `run` once on the GLib main loop after `milliseconds`; GLib holds it until the source is
/// removed. Returns the source id, which g_source_remove cancels. DispatchQueue.main.asyncAfter
/// works too (MainLoopBridge); there is no Timer or RunLoop in FoundationEssentials.
@MainActor @discardableResult
func runAfter(milliseconds: UInt32, _ run: @escaping @MainActor () -> Void) -> guint {
    let data = Unmanaged.passRetained(CallbackBox(run as SignalRun)).toOpaque()
    return g_timeout_add_full(G_PRIORITY_DEFAULT, milliseconds, runTimerOnce, data, releaseObject)
}
