// Sources/Elements/Stepper+Adwaita.swift
/*
 Stepper on GTK: its label, then a linked pair of buttons, minus and plus, as macOS shows a
 stepper's label before its arrows. Not a GtkSpinButton: that shows the value in an editable field,
 which SwiftUI's Stepper has not, and labelFormat usually shows the value already. As large as it
 is (measured on macOS 27: it does not grow; an empty label keeps its gap).

 - The label is Core's Stepper.labelText: labelFormat with the value in it (NumberPrintf; a format
   it refuses shows the plain value), else the label property, as on Apple. labelsHidden hides it;
   it still names the stepper. In a Form the label ends at the label column (FormLayout).
 - A button steps the value by step, kept in the range when there is one, and runs Core's
   Stepper.userSetValue (the value, then actionID with it as context). A button is disabled at its
   end of the range, as SwiftUI disables an arrow there.
 - For assistive technologies the stepper is a group named after its label, and the buttons are
   named Decrement and Increment, as VoiceOver names a stepper's parts.
*/

import CAdwaita

extension Stepper: ActionUIAdwaitaRenderer {
    /// The gap between the label and the buttons (SwiftUI's default spacing).
    static let labelSpacing: Int32 = 8

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = newWidget(gtk_box_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_GROUP)
        gtk_box_set_spacing(typed(box), labelSpacing)
        // Left out of the accessibility tree: the group carries the label as its name.
        let label = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_label_set_xalign(opaque(label), 0)
        gtk_box_append(typed(box), label)
        let buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_add_css_class(buttons, "linked")
        gtk_widget_set_valign(buttons, GTK_ALIGN_CENTER)
        for (icon, name, direction) in [("list-remove-symbolic", "Decrement", -1.0), ("list-add-symbolic", "Increment", 1.0)] {
            let button = gtk_button_new_from_icon_name(icon)!
            setAccessibleLabel(button, name)
            connectUserSignal(button, "clicked", .instanceOnly) { [weak node] in
                guard let node else { return }
                let props = Props(node.properties)
                let value = Stepper.initialValue(node.model) as? Double ?? props.initialValue
                Stepper.userSetValue(stepped(value, by: direction, props), element: node.element, model: node.model,
                                     windowUUID: node.windowUUID, props: props)
            }
            gtk_box_append(typed(buttons), button)
        }
        gtk_box_append(typed(box), buttons)
        // A Form lines its label up with the other rows' titles (FormLayout).
        attach(LabeledRowMarker(.box), to: box, key: labeledRowMarkerKey)
        return box
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let label = gtk_widget_get_first_child(widget), let buttons = gtk_widget_get_last_child(widget),
              let minus = gtk_widget_get_first_child(buttons), let plus = gtk_widget_get_last_child(buttons) else { return }
        let props = Props(node.properties)
        let value = Stepper.initialValue(node.model) as? Double ?? props.initialValue
        let text = labelText(props, value: value)
        if swiftString(gtk_label_get_text(opaque(label))) != text {
            gtk_label_set_text(opaque(label), text)
        }
        let showsLabel: gboolean = node.environment.labelsHidden ? 0 : 1
        if gtk_widget_get_visible(label) != showsLabel {
            gtk_widget_set_visible(label, showsLabel)
        }
        let canDecrement: gboolean = props.range.map { value > $0.lowerBound } ?? true ? 1 : 0
        let canIncrement: gboolean = props.range.map { value < $0.upperBound } ?? true ? 1 : 0
        if gtk_widget_get_sensitive(minus) != canDecrement {
            gtk_widget_set_sensitive(minus, canDecrement)
        }
        if gtk_widget_get_sensitive(plus) != canIncrement {
            gtk_widget_set_sensitive(plus, canIncrement)
        }
    }

    /// Named after the label it shows, also when labelsHidden hides it.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        let props = Props(node.properties)
        return labelText(props, value: Stepper.initialValue(node.model) as? Double ?? props.initialValue)
    }

    /// One step from `value` in `direction` (-1 or 1), kept in the range when there is one.
    static func stepped(_ value: Double, by direction: Double, _ props: Props) -> Double {
        let next = value + direction * props.step
        guard let range = props.range else { return next }
        return Swift.min(Swift.max(next, range.lowerBound), range.upperBound)
    }

    /// Sets a widget's accessible name.
    private static func setAccessibleLabel(_ widget: WidgetPointer, _ name: String) {
        var value = GValue()
        gtk_accessible_property_init_value(GTK_ACCESSIBLE_PROPERTY_LABEL, &value)
        g_value_set_string(&value, name)
        var property = GTK_ACCESSIBLE_PROPERTY_LABEL
        gtk_accessible_update_property_value(OpaquePointer(widget), 1, &property, &value)
        g_value_unset(&value)
    }
}
