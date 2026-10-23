// Sources/Layout/FormFieldTitle.swift
/*
 The title of a TextField or SecureField, as macOS shows it (measured on macOS 27): outside a Form
 the title is the field's placeholder when it has no prompt; in a Form the title stands before the
 field and ends at the label column, as a Picker's does (FormLayout), and the placeholder is the
 prompt alone. An empty title makes a column of 0; labelsHidden shows no title and makes no column.

 Outside a Form the field's widget is its bare entry (widget kind 0); in a Form it is a box of the
 title and the entry (widget kind 1), marked as a labeled row. Inside or outside a Form comes from
 the environment (inForm), so a field moved into or out of a Form gets the other widget.
*/

import CAdwaita

@MainActor
enum FormFieldTitle {
    /// The gap between the title and the entry (SwiftUI's default spacing).
    static let spacing: Int32 = 8

    /// 0: the bare entry; 1: the title and the entry, in a Form.
    static func widgetKind(_ node: RenderNode) -> Int {
        node.environment.inForm ? 1 : 0
    }

    /// The field's widget for `node.widgetKind`: `entry` itself, or a box of a title and `entry`.
    static func widget(_ entry: WidgetPointer, _ node: RenderNode) -> WidgetPointer {
        guard node.widgetKind == 1 else { return entry }
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, spacing)!
        // Left out of the accessibility tree: the entry carries the title as its name.
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_label_set_xalign(opaque(title), 0)
        gtk_box_append(typed(box), title)
        gtk_box_append(typed(box), entry)
        // A Form lines its title up with the other rows' (FormLayout).
        attach(LabeledRowMarker(.box), to: box, key: labeledRowMarkerKey)
        return box
    }

    /// The entry in the field's widget.
    static func entry(_ widget: WidgetPointer) -> WidgetPointer {
        guard attached(on: widget, key: labeledRowMarkerKey) != nil else { return widget }
        return gtk_widget_get_last_child(widget) ?? widget
    }

    /// Shows `title` before the entry when the field is in a Form, and returns the entry's
    /// placeholder: the prompt, else, outside a Form, the title.
    static func update(_ widget: WidgetPointer, _ node: RenderNode, title: String, prompt: String?) -> String? {
        if attached(on: widget, key: labeledRowMarkerKey) != nil,
           let label = Gtk.Widget(widget).firstChild {
            Gtk.Label(label.pointer).text = title
            label.isVisible = !node.environment.labelsHidden
        }
        return node.environment.inForm ? prompt : prompt ?? title
    }
}
