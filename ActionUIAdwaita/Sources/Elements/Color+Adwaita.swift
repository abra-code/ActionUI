// Sources/Elements/Color+Adwaita.swift
/*
 Color on GTK: a widget filled with the color (its CSS background), greedy in both axes as
 SwiftUI's Color is, with SwiftUI's ideal size of 10 x 10 (measured on macOS) as its natural size
 and no minimum. The value, a ColorSpec set at run time, overrides the color property.
*/

import CAdwaita

nonisolated(unsafe) private var fillWidgetType: GType = 0

extension Color: ActionUIAdwaitaRenderer {
    /// SwiftUI's ideal size of a Color (and of the shapes) in each axis.
    static let idealLength: Int32 = 10

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(fillType(), 0, nil, nil)!))
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let color = node.model.value as? ColorSpec ?? ColorSpec.parse(Props(node.properties).color)
        let declarations = color.map { ["background-color: \(ColorCSS.value($0));"] } ?? []
        StyleSheet.shared.apply(declarations, to: widget, slot: "color")
    }

    static var defaultExpansion: Expansion { .both }

    /// A GtkWidget subclass with no children whose size is 0 at least and 10 x 10 naturally; GTK
    /// draws its CSS background.
    static func fillType() -> GType {
        if fillWidgetType != 0 { return fillWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.measure = { _, _, _, minimum, natural, minimumBaseline, naturalBaseline in
                minimum?.pointee = 0
                natural?.pointee = Color.idealLength
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-fill")
        }
        fillWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIFill", &info, GTypeFlags(0))
        return fillWidgetType
    }
}
