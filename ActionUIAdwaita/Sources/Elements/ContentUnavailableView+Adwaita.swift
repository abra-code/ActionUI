// Sources/Elements/ContentUnavailableView+Adwaita.swift
/*
 ContentUnavailableView on GTK: the icon, the title and the description, centered one above the
 other, with libadwaita's styles (a dimmed icon, a title-2 heading, dimmed wrapping text). As wide
 as it is offered up to 400 points, centered in more, and as tall as it needs (measured on macOS 27:
 it asks for 400 at any width, takes 400 beside a filling Color in a 2000-wide row and half of a
 600-wide one, and is centered in a wide frame; in a column it keeps its own height, 126 points with
 an icon and a title). An AdwClamp holds it to 400, and a SizeLimit tells stacks so (LayoutCaps).

 Not AdwStatusPage, the plan's choice: even in its compact style its icon and margins made it about
 twice as tall as SwiftUI's view, and its icon size is not a property.

 - The title is the value, else the title property; the icon is systemImage's (SymbolNames), none
   without one.
 - The texts wrap at words, and inside a word that does not fit, as SwiftUI's do (a long search
   query would otherwise set the minimum width). Assistive technologies read the title and the
   description, as VoiceOver does; the icon is left out of the tree.
 - search: SwiftUI's search variant: a magnifying glass, "No Results" (or "No Results for" the query,
   which is the value, else the query property) and "Check the spelling or try a new search.". The
   title, systemImage and description are not used then, as in SwiftUI.

 Not yet: the search variant's texts are English on Linux (SwiftUI localizes them).
*/

import CAdwaita

extension ContentUnavailableView: ActionUIAdwaitaRenderer {
    /// The icon's size in pixels, the gap between the parts, and the margin around them.
    static let iconSize: Int32 = 48
    static let spacing: Int32 = 8
    static let margin: Int32 = 16
    /// The widest it gets, measured on macOS 27.
    static let maximumWidth: Int32 = 400

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, spacing)!
        for set in [gtk_widget_set_margin_top, gtk_widget_set_margin_bottom, gtk_widget_set_margin_start, gtk_widget_set_margin_end] {
            set(box, margin)
        }
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 0)
        // Decoration, left out of the accessibility tree: VoiceOver reads only the title and the
        // description of SwiftUI's view (measured on macOS 27); an unnamed image reads as "image".
        let icon = newWidget(gtk_image_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_image_set_pixel_size(opaque(icon), iconSize)
        Gtk.Widget(icon).setCSSClass("dim-label", true)
        gtk_box_append(typed(box), icon)
        let title = gtk_label_new(nil)!
        Gtk.Widget(title).setCSSClass("title-2", true)
        gtk_label_set_wrap(opaque(title), 1)
        gtk_label_set_wrap_mode(opaque(title), PANGO_WRAP_WORD_CHAR)
        gtk_label_set_justify(opaque(title), GTK_JUSTIFY_CENTER)
        gtk_box_append(typed(box), title)
        let description = gtk_label_new(nil)!
        Gtk.Widget(description).setCSSClass("dim-label", true)
        gtk_label_set_wrap(opaque(description), 1)
        gtk_label_set_wrap_mode(opaque(description), PANGO_WRAP_WORD_CHAR)
        gtk_label_set_justify(opaque(description), GTK_JUSTIFY_CENTER)
        gtk_box_append(typed(box), description)
        let clamp = adw_clamp_new()!
        adw_clamp_set_maximum_size(OpaquePointer(clamp), maximumWidth)
        adw_clamp_set_tightening_threshold(OpaquePointer(clamp), maximumWidth)
        // Pixels, as every other length in the layout: the clamp's default unit, sp, grows with
        // the text scaling factor (gtk-xft-dpi), which SwiftUI's 400 points and the SizeLimit
        // below do not.
        adw_clamp_set_unit(OpaquePointer(clamp), ADW_LENGTH_UNIT_PX)
        adw_clamp_set_child(OpaquePointer(clamp), box)
        gtk_widget_set_hexpand(clamp, 1)
        gtk_widget_set_vexpand(clamp, 0)
        attach(SizeLimit(width: Int(maximumWidth)), to: clamp, key: sizeLimitKey)
        return clamp
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let box = adw_clamp_get_child(OpaquePointer(widget)), let icon = Gtk.Widget(box).firstChild?.pointer,
              let title = Gtk.Widget(icon).nextSibling?.pointer,
              let description = Gtk.Widget(title).nextSibling?.pointer else { return }
        let content = shown(Props(node.properties), node.model.value as? String)
        Gtk.Label(title).text = content.title
        let text = content.description ?? ""
        Gtk.Label(description).text = text
        setVisible(description, !text.isEmpty)
        if let name = content.icon, swiftString(gtk_image_get_icon_name(opaque(icon))) != name {
            gtk_image_set_from_icon_name(opaque(icon), name)
        }
        setVisible(icon, content.icon != nil)
    }

    /// The title, description and icon name shown, from the properties and the value.
    static func shown(_ props: Props, _ value: String?) -> (title: String, description: String?, icon: String?) {
        if props.search {
            let query = value ?? props.query
            let title = query.isEmpty ? "No Results" : "No Results for \u{201C}\(query)\u{201D}"
            return (title, "Check the spelling or try a new search.", Image.iconName(.symbol("magnifyingglass")))
        }
        let icon = props.systemImage.flatMap { $0.isEmpty ? nil : Image.iconName(.symbol($0)) }
        return (value ?? props.title, props.description, icon)
    }

    private static func setVisible(_ widget: WidgetPointer, _ visible: Bool) {
        Gtk.Widget(widget).isVisible = visible
    }
}
