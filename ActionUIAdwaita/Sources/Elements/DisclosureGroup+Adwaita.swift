// Sources/Elements/DisclosureGroup+Adwaita.swift
/*
 DisclosureGroup on GTK: a GtkExpander showing the title with its arrow; expanded, its children
 below in a column, as macOS shows a disclosure group's content under its title. Measured on
 macOS 27 with the parity recorder:
 - It takes the width it is offered and the height it needs (beside a filling Color in a row it
   takes half; above one in a column, only its own height).
 - The children are a centered column with 8 points between them (none next to a Spacer, as in a
   VStack given no spacing) and no indent, offered the group's width and only their own height: a
   Color that fills is 10 points tall, its ideal.

 - Expanded is states["isExpanded"], which starts as the isExpanded property; the host changes it
   with setElementState. Expanding or collapsing runs Core's DisclosureGroup.userSetExpanded (the
   state, then valueChangeActionID); an update fires nothing.
 - Assistive technologies read the GtkExpander as a button with its expanded state, named after
   the title: GTK names it from its content, which takes in the children while expanded.

 Not yet: template mode (rows from states["content"]); templates come with the collections.
*/

import CAdwaita

extension DisclosureGroup: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let expander = gtk_expander_new(nil)!
        // As wide as it is offered, as tall as it needs, whatever its children do.
        gtk_widget_set_hexpand(expander, 1)
        gtk_widget_set_vexpand(expander, 0)
        let column = StackLayout.makeStack(axis: .vertical)
        gtk_expander_set_child(OpaquePointer(expander), column)
        connectUserSignal(expander, "notify::expanded", .instanceAndArgument) { [weak node] in
            guard let node else { return }
            DisclosureGroup.userSetExpanded(gtk_expander_get_expanded(OpaquePointer(expander)) != 0, element: node.element,
                                            model: node.model, windowUUID: node.windowUUID, props: Props(node.properties))
        }
        return expander
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let expander = OpaquePointer(widget)
        let props = Props(node.properties)
        if swiftString(gtk_expander_get_label(expander)) != props.title {
            gtk_expander_set_label(expander, props.title)
        }
        let expanded = node.model.states["isExpanded"] as? Bool ?? props.isExpanded
        if (gtk_expander_get_expanded(expander) != 0) != expanded {
            gtk_expander_set_expanded(expander, expanded ? 1 : 0)
        }
        guard let column = gtk_expander_get_child(expander) else { return }
        // SwiftUI's default spacing: 8 points between the children, none next to a Spacer (measured
        // on macOS 27).
        StackLayout.configure(column, spacing: nil, alignment: .center)
        syncContainerChildren(node, column, node.subviews("children"))
    }

    /// Named after its title, not its content (GTK's name for a button), which includes the
    /// children's text while expanded.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }
}
