// Sources/Elements/Label+Adwaita.swift
/*
 Label on GTK: its icon and its title side by side, 8 points apart, as large as they are (measured
 on macOS 27: a star and "Name" take the star's 17 points, 8, and the title's 36, and do not grow).

 - The title is the value, else the title property (Label.initialValue).
 - The icon is the one Image shows for systemImage, else an icon theme name for imageName; without
   either, the title alone.
 - Assistive technologies read the title label, named accessibilityLabel, else the title shown, as
   VoiceOver reads a Label; the icon is decoration and left out of the tree.
*/

import CAdwaita

extension Label: ActionUIAdwaitaRenderer {
    /// The gap between the icon and the title.
    static let iconSpacing: Int32 = 8

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, iconSpacing)!
        let icon = newWidget(gtk_image_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        Gtk.Widget(icon).isVisible = false
        gtk_box_append(typed(box), icon)
        let title = gtk_label_new(nil)!
        gtk_label_set_xalign(opaque(title), 0)
        gtk_box_append(typed(box), title)
        return box
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let icon = Gtk.Widget(widget).firstChild?.pointer, let title = Gtk.Widget(widget).lastChild?.pointer else { return }
        let props = Props(node.properties)
        let text = Label.initialValue(node.model) as? String ?? ""
        Gtk.Label(title).text = text
        let name = iconName(props)
        if let name, swiftString(gtk_image_get_icon_name(opaque(icon))) != name {
            gtk_image_set_from_icon_name(opaque(icon), name)
        }
        Gtk.Widget(icon).isVisible = name != nil
    }

    /// The title label, which assistive technologies read (the box only holds it and the icon).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        Gtk.Widget(widget).lastChild?.pointer ?? widget
    }

    /// Named after the title it shows, as Text is named after its text.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Label.initialValue(node.model) as? String
    }

    /// The icon: systemImage, else imageName, when not empty.
    static func iconName(_ props: Props) -> String? {
        if let symbol = props.systemImage, !symbol.isEmpty {
            return Image.iconName(.symbol(symbol))
        }
        if let asset = props.imageName, !asset.isEmpty {
            return Image.iconName(.themeIcon(asset))
        }
        return nil
    }
}
