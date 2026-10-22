// Sources/Elements/EmptyView+Adwaita.swift
/*
 EmptyView on GTK: nothing. Its box is invisible, so a stack gives it no place and no spacing:
 measured on macOS 27, two views with an EmptyView between them are as far apart as without it.
 Its modifiers show nothing either, as in SwiftUI.
*/

import CAdwaita

extension EmptyView: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        // The box is what the parent lays out; nothing else changes its visibility.
        if gtk_widget_get_visible(node.outerWidget) != 0 {
            gtk_widget_set_visible(node.outerWidget, 0)
        }
    }
}
