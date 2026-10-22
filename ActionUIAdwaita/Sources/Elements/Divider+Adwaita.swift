// Sources/Elements/Divider+Adwaita.swift
/*
 Divider on GTK: a GtkSeparator across its parent's stack axis, as SwiftUI's Divider is: a vertical
 line in an HStack (and in LabeledContent's row), a horizontal one anywhere else. It spans the
 other axis and is 1 point thick (measured on macOS 27: the layout parity fixtures divider-*), with
 the stack's spacing on both sides.
*/

import CAdwaita

extension Divider: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        // The parent stack's axis, as Spacer reads it.
        let inRow = Spacer.parentAxis(node) == .horizontal
        let orientation = inRow ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        if gtk_orientable_get_orientation(OpaquePointer(widget)) != orientation {
            gtk_orientable_set_orientation(OpaquePointer(widget), orientation)
        }
        // Spans the axis across the line.
        let across: gboolean = inRow ? 0 : 1
        if gtk_widget_get_hexpand(widget) != across {
            gtk_widget_set_hexpand(widget, across)
        }
        if gtk_widget_get_vexpand(widget) != 1 - across {
            gtk_widget_set_vexpand(widget, 1 - across)
        }
    }
}
