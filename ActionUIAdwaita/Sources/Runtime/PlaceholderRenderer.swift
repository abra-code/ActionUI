// Sources/Runtime/PlaceholderRenderer.swift
/*
 What an element type without a GTK renderer shows: a dimmed label naming the type, as the Android
 and web renderers do.
*/

import CAdwaita

enum PlaceholderRenderer: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let label = gtk_label_new("\(node.element.type) is not available on Linux yet")!
        gtk_widget_add_css_class(label, "dim-label")
        return label
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {}
}
