// Sources/Elements/Toggle+Adwaita.swift
/*
 Toggle on GTK, in the style the document names:
 - checkbox, and no style: a GtkCheckButton with the title as its label. macOS's default toggle
   is a checkbox, and Linux is a desktop as macOS is.
 - switch: the title beside a GtkSwitch, as macOS shows a switch toggle's label before it. An
   empty title stays, 0 wide, so the switch starts 8 after it; in a Form the title ends at the
   label column (FormLayout), while a checkbox keeps its title beside it (measured on macOS 27).
 - button: a GtkToggleButton showing the title, pressed while on.
 None of them grows when offered more space (measured on macOS 27, every style: an HStack with a
 Toggle and a filling Color gives the Toggle only what it needs).

 - On is the value, else the isOn property, else off (Toggle.initialValue).
 - labelsHidden hides the title of a checkbox or switch; it still names the control for assistive
   technologies, as in SwiftUI. A button toggle keeps its title, which is all it shows.
 - Turning it on or off runs Core's Toggle.userSetValue (the value, then actionID with the new
   state as context); an update fires nothing.
 - Its accessible name is accessibilityLabel, else the title.

 Not yet: a Toggle in a data-driven template row (templates come with the collections).
*/

import CAdwaita

extension Toggle: ActionUIAdwaitaRenderer {
    /// The widget each style needs (RenderNode.widgetKind).
    enum Kind: Int {
        case checkbox = 0, `switch`, button
    }

    /// The gap between a switch's title and the switch (SwiftUI's default spacing).
    static let titleSpacing: Int32 = 8

    static func widgetKind(_ node: RenderNode) -> Int {
        kind(Props(node.properties).style).rawValue
    }

    static func kind(_ style: Props.Style?) -> Kind {
        switch style {
        case .switch?: return .switch
        case .button?: return .button
        case .checkbox?, nil: return .checkbox
        }
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        switch Kind(rawValue: node.widgetKind) ?? .checkbox {
        case .checkbox:
            let check = gtk_check_button_new()!
            connectUserSignal(check, "toggled", .instanceOnly) { [weak node] in
                guard let node else { return }
                userToggled(node, on: Gtk.CheckButton(check).isActive)
            }
            return check
        case .switch:
            let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, titleSpacing)!
            // Left out of the accessibility tree: the switch carries the title as its name.
            let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
            gtk_label_set_xalign(opaque(title), 0)
            gtk_widget_set_valign(title, GTK_ALIGN_CENTER)
            gtk_box_append(typed(box), title)
            let toggle = gtk_switch_new()!
            gtk_widget_set_valign(toggle, GTK_ALIGN_CENTER)
            gtk_box_append(typed(box), toggle)
            // A Form lines its title up with the other rows' (FormLayout).
            attach(LabeledRowMarker(.box), to: box, key: labeledRowMarkerKey)
            connectUserSignal(toggle, "notify::active", .instanceAndArgument) { [weak node] in
                guard let node else { return }
                userToggled(node, on: gtk_switch_get_active(OpaquePointer(toggle)) != 0)
            }
            return box
        case .button:
            let button = gtk_toggle_button_new()!
            connectUserSignal(button, "toggled", .instanceOnly) { [weak node] in
                guard let node else { return }
                userToggled(node, on: gtk_toggle_button_get_active(typed(button)) != 0)
            }
            return button
        }
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let on = Toggle.initialValue(node.model) as? Bool ?? false
        let showsTitle = !props.title.isEmpty && !node.environment.labelsHidden
        switch Kind(rawValue: node.widgetKind) ?? .checkbox {
        case .checkbox:
            let check: UnsafeMutablePointer<GtkCheckButton> = typed(widget)
            let label = showsTitle ? props.title : nil
            if swiftString(gtk_check_button_get_label(check)) != label {
                gtk_check_button_set_label(check, label)
            }
            Gtk.CheckButton(widget).isActive = on
        case .switch:
            guard let title = Gtk.Widget(widget).firstChild?.pointer else { return }
            let toggle = OpaquePointer(accessibleWidget(widget))
            Gtk.Label(title).text = props.title
            // An empty title stays, 0 wide, keeping its gap (measured; a column of 0 in a Form).
            Gtk.Widget(title).isVisible = !node.environment.labelsHidden
            if (gtk_switch_get_active(toggle) != 0) != on {
                gtk_switch_set_active(toggle, on ? 1 : 0)
            }
        case .button:
            let button: UnsafeMutablePointer<GtkToggleButton> = typed(widget)
            if swiftString(gtk_button_get_label(typed(widget))) != props.title {
                gtk_button_set_label(typed(widget), props.title)
            }
            if (gtk_toggle_button_get_active(button) != 0) != on {
                gtk_toggle_button_set_active(button, on ? 1 : 0)
            }
            clearLabelledBy(widget)
        }
    }

    /// The switch of a switch toggle, which assistive technologies read (the box only holds it and
    /// the title); the widget itself for the other styles.
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        let isBox = g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_box_get_type()) != 0
        return isBox ? Gtk.Widget(widget).lastChild?.pointer ?? widget : widget
    }

    /// Named after its title, also when labelsHidden hides it, as in SwiftUI.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// Takes away the labelled-by relation gtk_button_set_label gives a toggle button to its label:
    /// it outranks the accessible label that accessibilityLabel sets (as on Button). A check button
    /// gets none, and mapping a toggle button adds none (measured on GTK 4.18).
    static func clearLabelledBy(_ widget: WidgetPointer) {
        gtk_accessible_reset_relation(OpaquePointer(widget), GTK_ACCESSIBLE_RELATION_LABELLED_BY)
    }

    private static func userToggled(_ node: RenderNode, on: Bool) {
        Toggle.userSetValue(on, element: node.element, model: node.model, windowUUID: node.windowUUID,
                            props: Props(node.properties))
    }
}
