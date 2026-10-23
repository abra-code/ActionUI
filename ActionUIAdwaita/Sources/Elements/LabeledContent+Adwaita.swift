// Sources/Elements/LabeledContent+Adwaita.swift
/*
 LabeledContent on GTK: its title, then its children in a row, as macOS lays it out outside a Form
 (measured on macOS 27): the title, 8 points, the children 8 points apart, all centered vertically.
 In a Form the title sits on the content's first text baseline instead (measured: beside three
 lines of text it is on the first line; beside a Color, on its bottom).
 It is as large as that unless a child fills, which then takes the rest of the row.

 Two stacks: the row of the title and the content, and the content's own row, which holds the
 children's boxes. An empty title keeps its gap, as in SwiftUI (measured: the content starts at 8).

 Assistive technologies read the row as a group named after the title (accessibilityLabel, else the
 title), with the content inside; the title label itself has the presentation role, so the title is
 read once.
*/

import CAdwaita

extension LabeledContent: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let row = StackLayout.makeStack(axis: .horizontal)
        StackLayout.configure(row, spacing: nil, alignment: .center)
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_label_set_xalign(opaque(title), 0)
        gtk_widget_set_parent(title, row)
        let content = StackLayout.makeStack(axis: .horizontal)
        StackLayout.configure(content, spacing: nil, alignment: .center)
        gtk_widget_insert_after(content, row, title)
        // A Form lines its title up with the other rows' (FormLayout).
        attach(LabeledRowMarker(.stack), to: row, key: labeledRowMarkerKey)
        return row
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let title = Gtk.Widget(widget).firstChild?.pointer, let content = Gtk.Widget(widget).lastChild?.pointer else { return }
        // In a Form the title sits on the content's first text baseline (Baselines), as macOS
        // lines a Form row up; elsewhere the two are centered.
        StackLayout.configure(widget, spacing: nil, alignment: .center, alignsBaselines: node.environment.inForm)
        let text = Props(node.properties).title
        Gtk.Label(title).text = text
        syncContainerChildren(node, content, node.subviews("children"))
    }

    /// Named after its title, as a group around its content.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }
}
