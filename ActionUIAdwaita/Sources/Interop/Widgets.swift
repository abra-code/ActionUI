// Sources/Interop/Widgets.swift
/*
 Views of GTK widgets for the calls the renderer repeats: Booleans for gboolean, a widget's
 children as a Swift sequence, measuring with a result instead of out-parameters, and setters that
 change the widget only when the value differs. GTK 4.18 already skips an equal value for a label's
 text, visibility, sensitivity and a check button's state (measured); an editable's text it
 replaces, moving the cursor and emitting "changed" twice, so there the guard changes behavior. The
 others keep every setter alike, at the cost of one getter call.

 A view does not own its widget: GTK's widget tree and RenderNode keep widgets alive (OwnedObject).
 Under the `Gtk` namespace, since ActionUI's own element types are named Label, Text and so on.
*/

import CAdwaita

// @MainActor on the enum does not reach its nested types, so each view carries its own.
enum Gtk {
    /// A widget's size in one orientation; baselines are nil when it reports none.
    struct Measurement: Equatable {
        var minimum: Int
        var natural: Int
        var minimumBaseline: Int?
        var naturalBaseline: Int?
    }

    /// Any widget.
    @MainActor
    struct Widget {
        let pointer: WidgetPointer

        init(_ pointer: WidgetPointer) {
            self.pointer = pointer
        }

        var isVisible: Bool {
            get { gtk_widget_get_visible(pointer) != 0 }
            nonmutating set {
                if newValue != isVisible {
                    gtk_widget_set_visible(pointer, newValue ? 1 : 0)
                }
            }
        }

        var isSensitive: Bool {
            get { gtk_widget_get_sensitive(pointer) != 0 }
            nonmutating set {
                if newValue != isSensitive {
                    gtk_widget_set_sensitive(pointer, newValue ? 1 : 0)
                }
            }
        }

        /// Whether the widget grows in `orientation` (its computed expand flag, which its children's
        /// flags reach).
        func expands(_ orientation: GtkOrientation) -> Bool {
            gtk_widget_compute_expand(pointer, orientation) != 0
        }

        /// The widget's size in `orientation`, for `forSize` in the other (-1: none). A `forSize`
        /// below the widget's minimum in the other orientation is measured at that minimum, as
        /// gtk_widget_measure does itself, but without the warning it logs for every such call
        /// (since GTK 4.18.0).
        func measure(_ orientation: GtkOrientation, forSize: Int = -1) -> Measurement {
            var minimum: Int32 = 0
            var natural: Int32 = 0
            var minimumBaseline: Int32 = -1
            var naturalBaseline: Int32 = -1
            var size = Int32(clamping: forSize)
            if size >= 0 {
                let opposite = orientation == GTK_ORIENTATION_HORIZONTAL ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
                var oppositeMinimum: Int32 = 0
                gtk_widget_measure(pointer, opposite, -1, &oppositeMinimum, nil, nil, nil)
                size = max(size, oppositeMinimum)
            }
            gtk_widget_measure(pointer, orientation, size, &minimum, &natural, &minimumBaseline, &naturalBaseline)
            return Measurement(minimum: Int(minimum), natural: Int(natural),
                               minimumBaseline: minimumBaseline >= 0 ? Int(minimumBaseline) : nil,
                               naturalBaseline: naturalBaseline >= 0 ? Int(naturalBaseline) : nil)
        }

        var parent: Widget? { gtk_widget_get_parent(pointer).map(Widget.init) }
        var firstChild: Widget? { gtk_widget_get_first_child(pointer).map(Widget.init) }
        var lastChild: Widget? { gtk_widget_get_last_child(pointer).map(Widget.init) }
        var nextSibling: Widget? { gtk_widget_get_next_sibling(pointer).map(Widget.init) }

        /// The widget's children, first to last. The walk reads each child's next sibling before
        /// handing the child out, so removing the current child is safe; removing a later one is
        /// not (collect them first: Array(children)).
        var children: Children { Children(first: firstChild) }

        /// Whether the widget has the CSS class.
        func hasCSSClass(_ name: String) -> Bool {
            gtk_widget_has_css_class(pointer, name) != 0
        }

        /// Adds or removes the CSS class, only when it changes.
        func setCSSClass(_ name: String, _ on: Bool) {
            guard hasCSSClass(name) != on else { return }
            if on {
                gtk_widget_add_css_class(pointer, name)
            } else {
                gtk_widget_remove_css_class(pointer, name)
            }
        }

        /// Whether the widget is a `type` (or derived from it).
        func isA(_ type: GType) -> Bool {
            g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(pointer)), type) != 0
        }
    }

    /// A widget's children as a sequence.
    @MainActor
    struct Children: @MainActor Sequence, @MainActor IteratorProtocol {
        private var upcoming: Widget?

        init(first: Widget?) {
            upcoming = first
        }

        mutating func next() -> Widget? {
            let current = upcoming
            upcoming = current?.nextSibling
            return current
        }
    }

    /// A GtkLabel.
    @MainActor
    struct Label {
        let pointer: WidgetPointer

        init(_ pointer: WidgetPointer) {
            self.pointer = pointer
        }

        var text: String {
            get { swiftString(gtk_label_get_text(opaque(pointer))) ?? "" }
            nonmutating set {
                if newValue != text {
                    gtk_label_set_text(opaque(pointer), newValue)
                }
            }
        }
    }

    /// A widget with editable text (GtkEntry, GtkPasswordEntry, GtkSpinButton).
    @MainActor
    struct Editable {
        let pointer: WidgetPointer

        init(_ pointer: WidgetPointer) {
            self.pointer = pointer
        }

        /// Setting the same text again would move the cursor (GTK replaces it), so it is skipped.
        var text: String {
            get { swiftString(gtk_editable_get_text(opaque(pointer))) ?? "" }
            nonmutating set {
                if newValue != text {
                    gtk_editable_set_text(opaque(pointer), newValue)
                }
            }
        }
    }

    /// A GtkCheckButton (a checkbox, or a radio button in a group).
    @MainActor
    struct CheckButton {
        let pointer: WidgetPointer

        init(_ pointer: WidgetPointer) {
            self.pointer = pointer
        }

        var isActive: Bool {
            get { gtk_check_button_get_active(typed(pointer)) != 0 }
            nonmutating set {
                if newValue != isActive {
                    gtk_check_button_set_active(typed(pointer), newValue ? 1 : 0)
                }
            }
        }
    }
}
