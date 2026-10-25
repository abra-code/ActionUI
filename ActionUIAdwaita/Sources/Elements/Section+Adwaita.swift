// Sources/Elements/Section+Adwaita.swift
/*
 Section on GTK: a Group (Group+Adwaita) whose first row is its header. Measured on macOS 27 in a
 Form (the layout parity fixtures): a Section adds no space of its own, so a Form's rows are as far
 apart across Sections as within one, and a header is a line of text in the Form's content column,
 as far above the first row as the rows are apart. So the Section's children and its header are
 laid out as its stack's own rows, with the Section's modifiers on each, as on a Group.

 The header is a label in a child box of the Section's, hidden without a header (it then takes no
 place). Elsewhere than in a stack the Section is a VStack with no spacing, the header first.
 The template form shows one row per content row after the header, as on Group.
*/

import CAdwaita

extension Section: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = Group.makeWidget(node)
        let header = gtk_label_new(nil)!
        gtk_label_set_xalign(opaque(header), 0)
        Gtk.Widget(header).isVisible = false
        let box = ModifierBox.wrap(header)
        attach(GroupChildBoxMarker(), to: box, key: groupChildBoxMarkerKey)
        gtk_widget_set_parent(box, widget)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let box = Gtk.Widget(widget).firstChild?.pointer, let content = ModifierBox.content(of: box),
              let header = ModifierBox.element(inContent: content) else { return }
        let text = Props(node.properties).header ?? ""
        Gtk.Label(header).text = text
        Gtk.Widget(header).isVisible = !text.isEmpty
        ModifierBox.applyBoxModifiers(box, BaseModifiers(node.properties))
        Group.syncChildBoxes(widget, node, after: box)
    }

    static func boxModifiers(_ modifiers: BaseModifiers) -> BaseModifiers {
        Group.boxModifiers(modifiers)
    }
}
