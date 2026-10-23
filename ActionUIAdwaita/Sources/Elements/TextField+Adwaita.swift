// Sources/Elements/TextField+Adwaita.swift
/*
 TextField on GTK: a GtkEntry, as wide as it is offered (SwiftUI's TextField is greedy in width).

 - The text is the value, else the text property (Props.initialValue); an update sets it only when
   it differs, since setting an entry's text moves the cursor.
 - The placeholder is the prompt, else the title: macOS shows the title inside the field when there
   is no prompt. In a Form the title stands before the field in the label column, and the
   placeholder is the prompt alone (FormFieldTitle).
 - Typing runs Core's TextField.userEditedText (the value, then valueChangeActionID); Return and
   leaving the field run TextField.userSubmitted (actionID), as on macOS, where ending editing
   commits; not the window becoming inactive or closing. Without an actionID, Return activates the
   window's default widget.
 - textContentType becomes GTK's input purpose, which on-screen keyboards and input methods read.
 - Its accessible name is accessibilityLabel, else the title, as in SwiftUI.

 Not yet: axis vertical shows a single line (GtkTextView comes with TextEditor), and a number
 format shows and stores plain text (the formatter comes with localized formatting); both are
 logged once per element type.
*/

import CAdwaita

@MainActor private var reportedLimits: Set<String> = []

extension TextField: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let entry = gtk_entry_new()!
        gtk_widget_set_hexpand(entry, 1)
        connectUserSignal(entry, "changed", .instanceOnly) { [weak node] in
            guard let node else { return }
            let text = swiftString(gtk_editable_get_text(OpaquePointer(entry))) ?? ""
            TextField.userEditedText(text, element: node.element, model: node.model, windowUUID: node.windowUUID,
                                     props: Props(node.properties))
        }
        connectUserSignal(entry, "activate", .instanceOnly) { [weak node] in
            guard let node else { return }
            TextField.userSubmitted(element: node.element, windowUUID: node.windowUUID, props: Props(node.properties))
        }
        let focus = gtk_event_controller_focus_new()!
        connectUserSignal(UnsafeMutableRawPointer(focus), "leave", .instanceOnly) { [weak node] in
            // Only the focus moving elsewhere submits. GTK also emits "leave" when the window
            // becomes inactive, and keeps its focus in the entry (AppKit ends no editing then), and
            // when the window goes away, after unmapping the entry.
            guard let node, node.isAttached, gtk_widget_get_mapped(entry) != 0, !containsWindowFocus(entry) else { return }
            TextField.userSubmitted(element: node.element, windowUUID: node.windowUUID, props: Props(node.properties))
        }
        gtk_widget_add_controller(entry, focus)
        return FormFieldTitle.widget(entry, node)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let entryWidget = FormFieldTitle.entry(widget)
        let entry: UnsafeMutablePointer<GtkEntry> = typed(entryWidget)
        let text = node.model.value as? String ?? props.initialValue
        Gtk.Editable(entryWidget).text = text
        let placeholder = FormFieldTitle.update(widget, node, title: props.title, prompt: props.prompt)
        if swiftString(gtk_entry_get_placeholder_text(entry)) != placeholder {
            gtk_entry_set_placeholder_text(entry, placeholder)
        }
        let activatesDefault: gboolean = props.actionID == nil ? 1 : 0
        if gtk_entry_get_activates_default(entry) != activatesDefault {
            gtk_entry_set_activates_default(entry, activatesDefault)
        }
        let purpose = inputPurpose(props.textContentType)
        if gtk_entry_get_input_purpose(entry) != purpose {
            gtk_entry_set_input_purpose(entry, purpose)
        }
        if props.axis == .vertical {
            reportOnce("axis vertical shows a single line on Linux for now")
        }
        if props.format != nil {
            reportOnce("number formats show plain text on Linux for now")
        }
    }

    /// Outside a Form the bare entry; in a Form its title and the entry (FormFieldTitle).
    static func widgetKind(_ node: RenderNode) -> Int {
        FormFieldTitle.widgetKind(node)
    }

    /// The entry, which assistive technologies read (in a Form, beside its title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        FormFieldTitle.entry(widget)
    }

    /// Named after its title, as SwiftUI names a TextField (an entry has no name of its own).
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// GTK's input purpose for a textContentType (Apple's UITextContentType names).
    static func inputPurpose(_ contentType: String?) -> GtkInputPurpose {
        switch contentType {
        case "emailAddress": return GTK_INPUT_PURPOSE_EMAIL
        case "url": return GTK_INPUT_PURPOSE_URL
        case "telephoneNumber": return GTK_INPUT_PURPOSE_PHONE
        case "name", "namePrefix", "givenName", "middleName", "familyName", "nameSuffix", "nickname", "username":
            return GTK_INPUT_PURPOSE_NAME
        case "oneTimeCode": return GTK_INPUT_PURPOSE_PIN
        case "creditCardNumber", "creditCardSecurityCode": return GTK_INPUT_PURPOSE_DIGITS
        default: return GTK_INPUT_PURPOSE_FREE_FORM
        }
    }

    /// Whether the focus of the entry's window is the entry or inside it (its text widget). SecureField
    /// uses it too.
    static func containsWindowFocus(_ entry: WidgetPointer) -> Bool {
        guard let root = gtk_widget_get_root(entry), let focus = gtk_root_get_focus(root) else { return false }
        return focus == entry || gtk_widget_is_ancestor(focus, entry) != 0
    }

    private static func reportOnce(_ limit: String) {
        if reportedLimits.insert(limit).inserted {
            ActionUIModel.shared.logger.log("TextField: \(limit)", .warning)
        }
    }
}
