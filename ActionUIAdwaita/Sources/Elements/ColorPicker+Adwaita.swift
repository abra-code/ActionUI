// Sources/Elements/ColorPicker+Adwaita.swift
/*
 ColorPicker on GTK: its title, then a GtkColorDialogButton showing the color, which opens GTK's
 color chooser, as macOS shows a color well after the title that opens the color panel. As large as
 it is (measured on macOS 27: it does not grow in either axis; 56 x 24 points without a title).

 - The color is the value, else the selectedColor property, else clear (ColorPicker.initialValue);
   a named color shows as its light-mode components (ColorCSS). The chooser offers opacity, as
   SwiftUI's ColorPicker does by default.
 - Picking a color runs Core's ColorPicker.userPicked (the value as sRGB components, then
   actionID); an update fires nothing.
 - labelsHidden hides the title; it still names the button for assistive technologies, which read
   the button and not the title beside it. An empty title stays, 0 wide, so the button starts 8
   after it (measured on macOS 27); in a Form the title ends at the label column (FormLayout).
 - The chooser keeps GTK's own window title, as macOS's color panel is titled Colors whatever the
   picker's title.
*/

import CAdwaita

extension ColorPicker: ActionUIAdwaitaRenderer {
    /// The gap between the title and the button (SwiftUI's default spacing).
    static let titleSpacing: Int32 = 8

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, titleSpacing)!
        // Left out of the accessibility tree: the button carries the title as its name.
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_label_set_xalign(opaque(title), 0)
        gtk_widget_set_valign(title, GTK_ALIGN_CENTER)
        gtk_box_append(typed(box), title)
        // The button takes the dialog's reference.
        let button = gtk_color_dialog_button_new(gtk_color_dialog_new())!
        gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
        gtk_box_append(typed(box), button)
        // A Form lines its title up with the other rows' (FormLayout).
        attach(LabeledRowMarker(.box), to: box, key: labeledRowMarkerKey)
        connectUserSignal(button, "notify::rgba", .instanceAndArgument) { [weak node] in
            guard let node, let rgba = gtk_color_dialog_button_get_rgba(OpaquePointer(button))?.pointee else { return }
            let color = ColorSpec.rgba(red: Double(rgba.red), green: Double(rgba.green), blue: Double(rgba.blue),
                                       alpha: Double(rgba.alpha))
            ColorPicker.userPicked(color, element: node.element, model: node.model, windowUUID: node.windowUUID,
                                   props: Props(node.properties))
        }
        return box
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let title = Gtk.Widget(widget).firstChild?.pointer, let button = Gtk.Widget(widget).lastChild?.pointer else { return }
        let props = Props(node.properties)
        Gtk.Label(title).text = props.title
        Gtk.Widget(title).isVisible = !node.environment.labelsHidden
        let spec = ColorPicker.initialValue(node.model) as? ColorSpec ?? .named(.clear)
        let value = ColorCSS.components(spec)
        var rgba = GdkRGBA(red: Float(value.red), green: Float(value.green), blue: Float(value.blue), alpha: Float(value.alpha))
        let shown = gtk_color_dialog_button_get_rgba(OpaquePointer(button))
        if shown.map({ gdk_rgba_equal($0, &rgba) == 0 }) ?? true {
            gtk_color_dialog_button_set_rgba(OpaquePointer(button), &rgba)
        }
    }

    /// The button, which assistive technologies read (the box only holds it and the title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        Gtk.Widget(widget).lastChild?.pointer ?? widget
    }

    /// Named after its title, also when labelsHidden hides it, as in SwiftUI.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }
}
