// Sources/Elements/SecureField+Adwaita.swift
/*
 SecureField on GTK: a GtkPasswordEntry, which shows dots and tells input methods the text is a
 password. It behaves as TextField does:
 - as wide as it is offered (SwiftUI's SecureField is greedy in width, as TextField is);
 - the text is the value, else the text property (SecureField.initialValue), set only when it
   differs, since setting it moves the cursor;
 - the placeholder is the prompt, else the title;
 - typing runs Core's TextField.userEditedText (the value, then valueChangeActionID), shared by the
   two entries; Return and leaving the field run TextField.userSubmitted (actionID), as on macOS;
   without an actionID, Return activates the window's default widget;
 - its accessible name is accessibilityLabel, else the title.
 No peek icon, as macOS's SecureField has none.
*/

import CAdwaita

// G_TYPE_STRING and G_TYPE_BOOLEAN, G_TYPE_MAKE_FUNDAMENTAL(16) and (5): function-like macros Swift
// does not import.
private let stringType = GType(16 << G_TYPE_FUNDAMENTAL_SHIFT)
private let booleanType = GType(5 << G_TYPE_FUNDAMENTAL_SHIFT)

extension SecureField: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let entry = gtk_password_entry_new()!
        gtk_widget_set_hexpand(entry, 1)
        connectUserSignal(entry, "changed", .instanceOnly) { [weak node] in
            guard let node else { return }
            let text = swiftString(gtk_editable_get_text(OpaquePointer(entry))) ?? ""
            TextField.userEditedText(text, valueChangeActionID: Props(node.properties).valueChangeActionID, viewID: node.element.id,
                                     model: node.model, windowUUID: node.windowUUID)
        }
        connectUserSignal(entry, "activate", .instanceOnly) { [weak node] in
            guard let node else { return }
            TextField.userSubmitted(actionID: Props(node.properties).actionID, viewID: node.element.id, windowUUID: node.windowUUID)
        }
        let focus = gtk_event_controller_focus_new()!
        connectUserSignal(UnsafeMutableRawPointer(focus), "leave", .instanceOnly) { [weak node] in
            // Only the focus moving elsewhere submits, as on TextField: not the window becoming
            // inactive, nor the window going away.
            guard let node, node.isAttached, gtk_widget_get_mapped(entry) != 0, !TextField.containsWindowFocus(entry) else { return }
            TextField.userSubmitted(actionID: Props(node.properties).actionID, viewID: node.element.id, windowUUID: node.windowUUID)
        }
        gtk_widget_add_controller(entry, focus)
        return entry
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let text = SecureField.initialValue(node.model) as? String ?? ""
        if swiftString(gtk_editable_get_text(OpaquePointer(widget))) != text {
            gtk_editable_set_text(OpaquePointer(widget), text)
        }
        // GtkPasswordEntry has these as properties only, without setters.
        let placeholder = props.prompt ?? props.title
        if stringProperty(widget, "placeholder-text") != placeholder {
            setStringProperty(widget, "placeholder-text", placeholder)
        }
        let activatesDefault = props.actionID == nil
        if boolProperty(widget, "activates-default") != activatesDefault {
            setBoolProperty(widget, "activates-default", activatesDefault)
        }
    }

    /// Named after its title, as SwiftUI names a SecureField.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    private static func stringProperty(_ widget: WidgetPointer, _ name: String) -> String? {
        var value = GValue()
        g_value_init(&value, stringType)
        defer { g_value_unset(&value) }
        g_object_get_property(typed(OpaquePointer(widget)), name, &value)
        return swiftString(g_value_get_string(&value))
    }

    private static func setStringProperty(_ widget: WidgetPointer, _ name: String, _ text: String) {
        var value = GValue()
        g_value_init(&value, stringType)
        defer { g_value_unset(&value) }
        g_value_set_string(&value, text)
        g_object_set_property(typed(OpaquePointer(widget)), name, &value)
    }

    private static func boolProperty(_ widget: WidgetPointer, _ name: String) -> Bool {
        var value = GValue()
        g_value_init(&value, booleanType)
        defer { g_value_unset(&value) }
        g_object_get_property(typed(OpaquePointer(widget)), name, &value)
        return g_value_get_boolean(&value) != 0
    }

    private static func setBoolProperty(_ widget: WidgetPointer, _ name: String, _ flag: Bool) {
        var value = GValue()
        g_value_init(&value, booleanType)
        defer { g_value_unset(&value) }
        g_value_set_boolean(&value, flag ? 1 : 0)
        g_object_set_property(typed(OpaquePointer(widget)), name, &value)
    }
}
