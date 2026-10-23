// Sources/Interop/Properties.swift
/*
 GObject properties by name ("placeholder-text", "activates-default"), for the settings GTK offers
 no typed function for. A PropertyKey carries the name and the Swift type, so reading or writing
 one is a subscript on Gtk.Widget instead of initializing, filling and unsetting a GValue by hand.
 Like the other views, a write changes the widget only when the value differs.

 G_TYPE_STRING and the other fundamental types are G_TYPE_MAKE_FUNDAMENTAL(n), a function-like
 macro Swift does not import, so the numbers are spelled out from gtype.h.
*/

import CAdwaita

/// A Swift type GLib's property system holds as a fundamental GValue type.
protocol PropertyValue: Equatable {
    /// The GValue type the value is held as.
    static var valueType: GType { get }
    /// The value a GValue of valueType holds.
    init(_ value: UnsafePointer<GValue>)
    /// Stores the value in a GValue initialized to valueType.
    func store(in value: UnsafeMutablePointer<GValue>)
}

extension Bool: PropertyValue {
    static var valueType: GType { GType(5 << G_TYPE_FUNDAMENTAL_SHIFT) }
    init(_ value: UnsafePointer<GValue>) { self = g_value_get_boolean(value) != 0 }
    func store(in value: UnsafeMutablePointer<GValue>) { g_value_set_boolean(value, self ? 1 : 0) }
}

extension Double: PropertyValue {
    static var valueType: GType { GType(15 << G_TYPE_FUNDAMENTAL_SHIFT) }
    init(_ value: UnsafePointer<GValue>) { self = g_value_get_double(value) }
    func store(in value: UnsafeMutablePointer<GValue>) { g_value_set_double(value, self) }
}

/// A string property; nil is GLib's NULL string (most GTK text properties take it as "none").
extension Optional: PropertyValue where Wrapped == String {
    static var valueType: GType { GType(16 << G_TYPE_FUNDAMENTAL_SHIFT) }
    init(_ value: UnsafePointer<GValue>) { self = swiftString(g_value_get_string(value)) }
    func store(in value: UnsafeMutablePointer<GValue>) { g_value_set_string(value, self) }
}

/// A GObject property's name and the Swift type its value has.
struct PropertyKey<Value: PropertyValue>: Sendable {
    let name: String
    init(_ name: String) { self.name = name }
}

extension Gtk.Widget {
    /// The widget's value of a property; setting it changes the widget only when the value
    /// differs. GLib logs a warning for a property the widget does not have, and reading one
    /// returns the type's zero value.
    subscript<Value>(property: PropertyKey<Value>) -> Value {
        get {
            var value = GValue()
            g_value_init(&value, Value.valueType)
            defer { g_value_unset(&value) }
            g_object_get_property(typed(OpaquePointer(pointer)), property.name, &value)
            return Value(&value)
        }
        nonmutating set {
            guard newValue != self[property] else { return }
            var value = GValue()
            g_value_init(&value, Value.valueType)
            defer { g_value_unset(&value) }
            newValue.store(in: &value)
            g_object_set_property(typed(OpaquePointer(pointer)), property.name, &value)
        }
    }
}
