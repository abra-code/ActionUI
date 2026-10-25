// Sources/Elements/VerticalTextField.swift
/*
 A TextField with axis vertical on GTK: a GtkTextView that wraps its text and grows with it, drawn
 as an entry is (libadwaita's entry look), as SwiftUI's TextField(axis: .vertical) grows on macOS.

 - Its height is a number of lines, as SwiftUI's lineLimit sets it on a vertical field: lineLimit n
   is at most n lines, from 1 (SwiftUI reserves no space without reservesSpace); a range {min, max}
   at least min and at most max; {min} at least min, without a bound; none, from 1 without a bound.
   Beyond its most lines the text scrolls, by the wheel and with the cursor, without a scroll bar.
 - Return submits, as in a one-line field (TextField.userSubmitted: actionID; without one, the
   window's default widget); Option+Return and Control+Return insert a new line, as in a macOS
   text field, and Shift+Return too, as GNOME apps insert one, unless a shortcut of the window
   or the app takes that key (a button's command+Return, Ctrl+Return on Linux, still presses it,
   as on macOS). Return that an input method is composing with goes to the input method. Tab
   moves the focus, as in a text field.
 - Assistive technologies read the text view, named as the one-line field is, with the
   placeholder as its placeholder.
 - Typing, leaving the field, the placeholder (the prompt, else the title) and a Form's title work
   as in the one-line field; the placeholder is a dimmed label over the first line, as TextEditor
   shows its own (TextEditor.makePlaceholder, reportEdits).
 - In a Form its title stands beside its first line, as macOS lines it up.

 Not yet: a font changed at run time resizes the lines at the next update or showing, not at once.
*/

import CAdwaita

@MainActor
enum VerticalTextField {
    /// The text's distance from the field's leading and trailing edges, and from its top and bottom
    /// (an entry's: 9 and 8, a line of 18 in an entry 34 tall).
    static let inset = (horizontal: Int32(9), vertical: Int32(8))

    /// libadwaita's entry look for the scrolled window holding the text view.
    static let rules = """
        .actionui-vertical-field { background-color: alpha(currentColor, 0.1); border-radius: 6px; \
        outline: 0 solid transparent; outline-offset: 2px; }
        .actionui-vertical-field:focus-within { outline-color: color-mix(in srgb, var(--accent-color) 50%, transparent); \
        outline-width: 2px; outline-offset: -2px; }
        .actionui-vertical-field > textview, .actionui-vertical-field > textview > text { background: none; }
        """

    /// Whether an input method is composing in a text view (its preedit is not empty): Return is
    /// the input method's then.
    private final class Composing {
        var isComposing = false
    }

    /// The field: an overlay of the scrolled text view and the placeholder; in a Form, beside its
    /// title (FormFieldTitle).
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StyleSheet.shared.installFixedRules("actionui-vertical-field", rules)
        let overlay = gtk_overlay_new()!
        let scrolled = gtk_scrolled_window_new()!
        // Scrolled by the wheel and the cursor without a scroll bar, as a macOS text field scrolls
        // its lines: a scroll bar that may show also makes GTK give the field at least its height
        // (58, a field of 3 lines), too tall for one or two.
        gtk_scrolled_window_set_policy(OpaquePointer(scrolled), GTK_POLICY_NEVER, GTK_POLICY_EXTERNAL)
        gtk_scrolled_window_set_propagate_natural_height(OpaquePointer(scrolled), 1)
        Gtk.Widget(scrolled).setCSSClass("actionui-vertical-field", true)
        let view = gtk_text_view_new()!
        let textView: UnsafeMutablePointer<GtkTextView> = typed(view)
        gtk_text_view_set_wrap_mode(textView, GTK_WRAP_WORD_CHAR)
        gtk_text_view_set_accepts_tab(textView, 0)
        gtk_text_view_set_left_margin(textView, inset.horizontal)
        gtk_text_view_set_right_margin(textView, inset.horizontal)
        gtk_text_view_set_top_margin(textView, inset.vertical)
        gtk_text_view_set_bottom_margin(textView, inset.vertical)
        gtk_scrolled_window_set_child(OpaquePointer(scrolled), view)
        gtk_overlay_set_child(OpaquePointer(overlay), scrolled)
        let placeholder = TextEditor.makePlaceholder(leading: inset.horizontal, top: inset.vertical)
        gtk_overlay_add_overlay(OpaquePointer(overlay), placeholder)
        gtk_widget_set_hexpand(overlay, 1)
        // Lines up on its first line (Baselines).
        attach(TextLineMarker(.top(inset: Int(inset.vertical))), to: overlay, key: textLineMarkerKey)

        let buffer = gtk_text_view_get_buffer(textView)!
        TextEditor.reportEdits(of: buffer, placeholder: placeholder) { [weak node] in
            guard let node else { return }
            TextField.userEditedText(TextEditor.bufferText(buffer), element: node.element, model: node.model,
                                     windowUUID: node.windowUUID, props: TextField.Props(node.properties))
        }
        let composing = Composing()
        // The preedit string, empty when the input method stops composing.
        connectObjectSignal(view, "preedit-changed") { preedit in
            composing.isComposing = preedit.load(as: CChar.self) != 0
        }
        // Return, before the text view inserts a line for it.
        let keys = gtk_event_controller_key_new()!
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE)
        connectKeyPressed(UnsafeMutableRawPointer(keys)) { [weak node] keyval in
            guard [GDK_KEY_Return, GDK_KEY_KP_Enter, GDK_KEY_ISO_Enter].contains(Int32(keyval)), let node else { return false }
            if composing.isComposing {
                return false
            }
            if returnInsertsNewLine(gtk_event_controller_get_current_event_state(keys)) {
                // A shortcut of the window or the app for it first (a Send button's command+Return,
                // which is Ctrl+Return on Linux): the text view would take any Return as a new line.
                if let root = gtk_widget_get_root(view),
                   gtk_event_controller_key_forward(keys, typed(root)) != 0 {
                    return true
                }
                insertNewLine(textView)
            } else if TextField.Props(node.properties).actionID != nil {
                TextField.userSubmitted(element: node.element, windowUUID: node.windowUUID, props: TextField.Props(node.properties))
            } else {
                gtk_widget_activate_default(view)
            }
            return true
        }
        gtk_widget_add_controller(view, keys)
        let focus = gtk_event_controller_focus_new()!
        connectUserSignal(UnsafeMutableRawPointer(focus), "leave", .instanceOnly) { [weak node] in
            // Only the focus moving elsewhere submits, as in a one-line field.
            guard let node, node.isAttached, gtk_widget_get_mapped(view) != 0, !TextField.containsWindowFocus(view) else { return }
            TextField.userSubmitted(element: node.element, windowUUID: node.windowUUID, props: TextField.Props(node.properties))
        }
        gtk_widget_add_controller(view, focus)
        // The lines' height in the field's font, once it is styled.
        connectSignal(view, "map", .instanceOnly) { [weak node] in
            guard let node else { return }
            sizeLines(scrolled, view, TextField.Props(node.properties).lineLimit)
        }

        let widget = FormFieldTitle.widget(overlay, node)
        if widget != overlay, let title = Gtk.Widget(widget).firstChild {
            // Beside the first line, not the middle of the field.
            gtk_widget_set_valign(title.pointer, GTK_ALIGN_START)
            gtk_widget_set_margin_top(title.pointer, inset.vertical)
        }
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let parts = parts(widget) else { return }
        let props = TextField.Props(node.properties)
        let buffer = gtk_text_view_get_buffer(typed(parts.view))!
        let text = node.model.value as? String ?? props.initialValue
        if TextEditor.bufferText(buffer) != text {
            gtk_text_buffer_set_text(buffer, text, -1)
        }
        let placeholderText = FormFieldTitle.update(widget, node, title: props.title, prompt: props.prompt) ?? ""
        if Gtk.Label(parts.placeholder).text != placeholderText {
            Gtk.Label(parts.placeholder).text = placeholderText
            setAccessiblePlaceholder(parts.view, placeholderText)
        }
        Gtk.Widget(parts.placeholder).isVisible = !placeholderText.isEmpty && text.isEmpty
        let purpose = TextField.inputPurpose(props.textContentType)
        if gtk_text_view_get_input_purpose(typed(parts.view)) != purpose {
            gtk_text_view_set_input_purpose(typed(parts.view), purpose)
        }
        sizeLines(parts.scrolled, parts.view, props.lineLimit)
    }

    /// The text view, the scrolled window holding it and the placeholder, in the field's widget.
    static func parts(_ widget: WidgetPointer) -> (view: WidgetPointer, scrolled: WidgetPointer, placeholder: WidgetPointer)? {
        let overlay = FormFieldTitle.entry(widget)
        guard Gtk.Widget(overlay).isA(gtk_overlay_get_type()),
              let scrolled = gtk_overlay_get_child(OpaquePointer(overlay)),
              let view = gtk_scrolled_window_get_child(OpaquePointer(scrolled)),
              let placeholder = Gtk.Widget(overlay).lastChild?.pointer else { return nil }
        return (view, scrolled, placeholder)
    }

    /// The fewest and most lines `lineLimit` shows on a vertical field, as SwiftUI reads it; nil
    /// for no most.
    static func lineRange(_ lineLimit: TextField.Props.LineLimit?) -> (min: Int, max: Int?) {
        switch lineLimit {
        case .exact(let lines):
            return (1, max(lines, 1))
        case .range(let lower, let upper):
            let least = max(lower ?? 1, 1)
            return (least, upper.map { max($0, least) })
        case nil:
            return (1, nil)
        }
    }

    /// Sizes the scrolled window to the lines `lineLimit` shows, a line being the height of a line
    /// of the text view's font.
    private static func sizeLines(_ scrolled: WidgetPointer, _ view: WidgetPointer, _ lineLimit: TextField.Props.LineLimit?) {
        let range = lineRange(lineLimit)
        let line = lineHeight(view)
        let insets = Int(inset.vertical) * 2
        // Clamped: a document's lineLimit can be any Int, and a product past Int32 (or Int) traps.
        let height = { (lines: Int) in Int32(clamping: min(lines, Int(Int32.max)) * line + insets) }
        let least = height(range.min)
        let most = range.max.map(height) ?? -1
        let window = OpaquePointer(scrolled)
        guard gtk_scrolled_window_get_min_content_height(window) != least
              || gtk_scrolled_window_get_max_content_height(window) != most else { return }
        // No most first: GTK refuses a least above the current most.
        gtk_scrolled_window_set_max_content_height(window, -1)
        gtk_scrolled_window_set_min_content_height(window, least)
        gtk_scrolled_window_set_max_content_height(window, most)
    }

    /// The height of one line of `view`'s text, as it lays a line out.
    private static func lineHeight(_ view: WidgetPointer) -> Int {
        let layout = gtk_widget_create_pango_layout(view, "X")!
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        var width: Int32 = 0
        var height: Int32 = 0
        pango_layout_get_pixel_size(layout, &width, &height)
        return Int(height)
    }

    /// Tells assistive technologies the text view's placeholder, as an entry tells its own.
    private static func setAccessiblePlaceholder(_ view: WidgetPointer, _ text: String) {
        var value = GValue()
        gtk_accessible_property_init_value(GTK_ACCESSIBLE_PROPERTY_PLACEHOLDER, &value)
        g_value_set_string(&value, text)
        var property = GTK_ACCESSIBLE_PROPERTY_PLACEHOLDER
        gtk_accessible_update_property_value(OpaquePointer(view), 1, &property, &value)
        g_value_unset(&value)
    }

    /// Whether Return with `modifiers` inserts a new line (Option, Control or Shift held) rather than
    /// submitting.
    static func returnInsertsNewLine(_ modifiers: GdkModifierType) -> Bool {
        modifiers.rawValue & (GDK_ALT_MASK.rawValue | GDK_CONTROL_MASK.rawValue | GDK_SHIFT_MASK.rawValue) != 0
    }

    /// Inserts a new line at the cursor, over the selection, as one edit the user made.
    private static func insertNewLine(_ view: UnsafeMutablePointer<GtkTextView>) {
        let buffer = gtk_text_view_get_buffer(view)!
        let editable = gtk_text_view_get_editable(view)
        gtk_text_buffer_begin_user_action(buffer)
        gtk_text_buffer_delete_selection(buffer, 1, editable)
        gtk_text_buffer_insert_interactive_at_cursor(buffer, "\n", 1, editable)
        gtk_text_buffer_end_user_action(buffer)
        gtk_text_view_scroll_mark_onscreen(view, gtk_text_buffer_get_insert(buffer))
    }
}
