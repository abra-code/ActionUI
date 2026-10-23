// Sources/Interop/Owned.swift
/*
 References the renderer owns, released when they go away. Each type holds one reference and
 cannot be copied, so a reference has one owner and is released once, also on an early return
 (the compiler places the release); it costs nothing at run time beyond the C calls.

 Two initializers, in the terms of Cocoa's ownership rules:
 - `retaining:` for a pointer the caller does not own: a borrowed one (a getter's result, a
   signal's argument) or a newly made widget or variant (gtk_box_new, g_variant_new_string);
 - `adopting:` for a pointer handed over with its reference, as Core Foundation's Create rule
   does (GLib's "transfer full": g_menu_new, g_simple_action_new, g_action_get_state).
 A reference given to a function that takes it ("transfer full" parameter, such as
 adw_toggle_group_add) leaves through `handOver()`, without being released.

 Why a new widget is "retained" rather than adopted: GLib gives a new widget (any
 GInitiallyUnowned) or a new GVariant a "floating" reference, owned by no one yet, so C code can
 create and hand it over in one expression (gtk_box_append(box, gtk_label_new("x"))); the first
 owner claims it ("sinks" it). `retaining:` calls the sinking function (g_object_ref_sink,
 g_variant_ref_sink), which claims a floating reference, or takes a new reference when the
 pointer is not floating. Either way the owner ends up with exactly one reference, so Swift code
 never has to tell floating from borrowed. Adopting a floating pointer would be a mistake (the
 first container to claim it would take this reference too); `adopting:` asserts it does not
 happen.
*/

import CAdwaita

/// One reference to a GObject.
struct OwnedObject: ~Copyable {
    let pointer: UnsafeMutableRawPointer

    /// A new or borrowed object, with a reference of our own (g_object_ref_sink: a new widget's
    /// floating reference is claimed, any other pointer retained).
    init(retaining pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
        g_object_ref_sink(pointer)
    }

    /// An object handed over with its reference (transfer full), taken as is. Never a new widget
    /// (gtk_label_new, g_object_new of a widget), whose reference is floating: use `retaining:`.
    init(adopting pointer: UnsafeMutableRawPointer) {
        assert(g_object_is_floating(pointer) == 0, "a new widget's floating reference: use init(retaining:)")
        self.pointer = pointer
    }

    /// A new or borrowed widget (gtk_box_new), with a reference of our own.
    init(retaining widget: WidgetPointer) {
        self.init(retaining: UnsafeMutableRawPointer(widget))
    }

    /// A new or borrowed object of a final GTK type, whose pointer Swift imports as opaque.
    init(retaining object: OpaquePointer) {
        self.init(retaining: UnsafeMutableRawPointer(object))
    }

    /// An object of a final type handed over with its reference (g_menu_new, g_simple_action_new).
    init(adopting object: OpaquePointer) {
        self.init(adopting: UnsafeMutableRawPointer(object))
    }

    deinit {
        g_object_unref(pointer)
    }

    /// The object as a typed pointer, for the GTK functions that take one (gtk_box_append takes a
    /// GtkBox): the caller knows its type.
    func typed<T>(_ type: T.Type = T.self) -> UnsafeMutablePointer<T> {
        pointer.assumingMemoryBound(to: T.self)
    }

    /// The object as a widget (the caller knows it is one).
    var widget: WidgetPointer {
        pointer.assumingMemoryBound(to: GtkWidget.self)
    }

    /// The object as an opaque pointer, for the GTK functions that take one.
    var opaquePointer: OpaquePointer {
        OpaquePointer(pointer)
    }

    /// Gives the reference to a function that takes it (transfer full); nothing is released here.
    consuming func handOver() -> UnsafeMutableRawPointer {
        let pointer = self.pointer
        discard self
        return pointer
    }
}

/// One reference to a GVariant.
struct OwnedVariant: ~Copyable {
    let pointer: OpaquePointer

    /// A new or borrowed variant, with a reference of our own (g_variant_ref_sink: a new variant's
    /// floating reference from g_variant_new_* is claimed, any other retained). Borrowed: a signal
    /// handler's argument, such as the parameter of a GSimpleAction's "activate". Not for menu
    /// attributes: g_menu_model_get_item_attribute_value hands over its reference (`adopting:`).
    init(retaining pointer: OpaquePointer) {
        self.pointer = pointer
        g_variant_ref_sink(pointer)
    }

    /// A variant handed over with its reference (g_action_get_state), taken as is. Never a new
    /// one (g_variant_new_*), whose reference is floating: use `retaining:`.
    init(adopting pointer: OpaquePointer) {
        assert(g_variant_is_floating(pointer) == 0, "a new variant's floating reference: use init(retaining:)")
        self.pointer = pointer
    }

    deinit {
        g_variant_unref(pointer)
    }

    /// The string the variant holds; nil when it holds no string (g_variant_get_string would
    /// stop the process). Checked with g_variant_classify: a GVariantType made from a Swift
    /// string would point into a temporary that is gone once the call making it returns.
    var string: String? {
        guard g_variant_classify(pointer) == G_VARIANT_CLASS_STRING else { return nil }
        return String(cString: g_variant_get_string(pointer, nil))
    }

    /// The Boolean the variant holds; nil when it holds none.
    var bool: Bool? {
        guard g_variant_classify(pointer) == G_VARIANT_CLASS_BOOLEAN else { return nil }
        return g_variant_get_boolean(pointer) != 0
    }
}

/// A string GLib hands to the caller to free (g_date_time_format, gtk_text_buffer_get_text), as a
/// Swift string, freed here.
func takeGString(_ text: UnsafeMutablePointer<gchar>?) -> String? {
    guard let text else { return nil }
    defer { g_free(text) }
    return String(cString: text)
}
