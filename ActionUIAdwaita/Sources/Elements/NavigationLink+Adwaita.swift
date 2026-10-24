// Sources/Elements/NavigationLink+Adwaita.swift
/*
 NavigationLink on GTK: a flat button with the title and a forward arrow, as a row that leads on
 does in GNOME (and SwiftUI shows a chevron in a List). A click pushes on the enclosing
 NavigationStack (NavigationStack+Adwaita.swift):
 - an inline "destination" view, which is not in the stack's path, as SwiftUI's view-destination
   link is not;
 - else the destination destinationViewId names in the stack's "destinations", added to the path.
 A link with neither is shown dimmed and does nothing; a click outside a NavigationStack is logged.
*/

import CAdwaita

/// The parts of a NavigationLink's button.
@MainActor
final class NavigationLinkParts {
    let label: WidgetPointer

    init(label: WidgetPointer) {
        self.label = label
    }
}

let navigationLinkPartsKey = AttachKey<NavigationLinkParts>("actionui-navigation-link")

extension NavigationLink: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let button = gtk_button_new()!
        gtk_widget_add_css_class(button, "flat")
        // A row's text, not a button's bold label.
        StyleSheet.shared.apply(["font-weight: normal;"], to: button, slot: "navigation-link")
        let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
        let label = gtk_label_new(nil)!
        gtk_label_set_xalign(OpaquePointer(label), 0)
        gtk_widget_set_hexpand(label, 1)
        gtk_box_append(typed(row), label)
        gtk_box_append(typed(row), gtk_image_new_from_icon_name("go-next-symbolic"))
        gtk_button_set_child(typed(button), row)
        attach(NavigationLinkParts(label: label), to: button, key: navigationLinkPartsKey)
        connectUserSignal(button, "clicked", .instanceOnly) { [weak node] in
            guard let node else { return }
            let destination = node.effectiveElement.subviews?["destination"] as? any ActionUIElementBase
            guard destination != nil || initialValue(node.model) is Int else { return }
            NavigationStack.push(from: node, element: destination,
                                 destinationID: destination == nil ? initialValue(node.model) as? Int : nil)
        }
        return button
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let parts = attached(on: widget, key: navigationLinkPartsKey) else { return }
        let title = Props(node.properties).title
        if swiftString(gtk_label_get_text(OpaquePointer(parts.label))) != title {
            gtk_label_set_text(OpaquePointer(parts.label), title)
        }
        let leads = node.effectiveElement.subviews?["destination"] is any ActionUIElementBase
            || initialValue(node.model) is Int
        // The row, not the button, whose sensitivity is the disabled modifier's (ModifierBox).
        if let row = gtk_button_get_child(typed(widget)), (gtk_widget_get_sensitive(row) != 0) != leads {
            gtk_widget_set_sensitive(row, leads ? 1 : 0)
        }
    }

    /// Named after its title, as SwiftUI names a link.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }
}
