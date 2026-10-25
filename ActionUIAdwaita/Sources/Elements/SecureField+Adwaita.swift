// Sources/Elements/SecureField+Adwaita.swift
/*
 SecureField on GTK: a GtkPasswordEntry, which shows dots and tells input methods the text is a
 password. It behaves as TextField does:
 - as wide as it is offered (SwiftUI's SecureField is greedy in width, as TextField is);
 - the text is the value, else the text property (SecureField.initialValue), set only when it
   differs, since setting it moves the cursor;
 - the placeholder is the prompt, else the title; in a Form the title stands before the field in
   the label column and the placeholder is the prompt alone (FormFieldTitle);
 - typing runs Core's TextField.userEditedText (the value, then valueChangeActionID), shared by the
   two entries; Return and leaving the field run TextField.userSubmitted (actionID), as on macOS;
   without an actionID, Return activates the window's default widget;
 - its accessible name is accessibilityLabel, else the title.
 No peek icon, as macOS's SecureField has none.
*/

import CAdwaita

private let placeholderText = PropertyKey<String?>("placeholder-text")
private let activatesDefault = PropertyKey<Bool>("activates-default")

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
        return FormFieldTitle.widget(entry, node)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let text = SecureField.initialValue(node.model) as? String ?? ""
        let entry = FormFieldTitle.entry(widget)
        Gtk.Editable(entry).text = text
        // GtkPasswordEntry has these as properties only, without setters.
        let placeholder = FormFieldTitle.update(widget, node, title: props.title, prompt: props.prompt)
        Gtk.Widget(entry)[placeholderText] = placeholder
        Gtk.Widget(entry)[activatesDefault] = props.actionID == nil
        ControlSizeCSS.applyFont(node, to: widget)
        ControlSizeCSS.applyPart(ControlSizeCSS.entry(node.environment.controlSize), to: entry)
    }

    /// Outside a Form the bare entry; in a Form its title and the entry (FormFieldTitle).
    static func widgetKind(_ node: RenderNode) -> Int {
        FormFieldTitle.widgetKind(node)
    }

    /// The entry, which assistive technologies read (in a Form, beside its title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        FormFieldTitle.entry(widget)
    }

    /// Named after its title, as SwiftUI names a SecureField.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }
}
