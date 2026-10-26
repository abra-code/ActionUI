// Sources/Elements/TextEditor+Adwaita.swift
/*
 TextEditor on GTK: a GtkTextView in a scrolled window, as large as it is offered in both axes (as
 SwiftUI's TextEditor is, measured on macOS 27), word-wrapping its lines.

 - The text is the value, else the text property, else the markdown property (TextEditor.initialValue);
   an update sets it only when it differs, since setting a buffer's text moves the cursor.
 - With the markdown property it edits styled text, as SwiftUI's TextEditor does from macOS 26: the
   markdown is shown with its inline styles and links (Markdown/MarkdownBuffer.swift), typed text
   takes the style around it, and the value is an AttributedString (a String value is read as
   markdown, as on Apple). A click on a link opens it in the user's browser, and the pointer is a
   hand over it, as in SwiftUI's editor on macOS; there are no formatting commands yet.
 - Typing runs Core's TextField.userEditedText (the value, then valueChangeActionID), as every text
   entry does, once per edit (typing over a selection is one); an update fires nothing.
 - readOnly makes the text view not editable; its cursor stays, for selecting from the keyboard.
 - The placeholder is a dimmed label over the top leading corner while the text is empty, as the
   SwiftUI renderer lays it over SwiftUI's TextEditor.
 - Its accessible name is accessibilityLabel, else the placeholder.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

/// The user action open on a text editor's buffer, if any, and whether its text changed in it.
@MainActor private final class UserActionState {
    var depth = 0
    var changed = false
}

extension TextEditor: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let overlay = gtk_overlay_new()!
        let scrolled = gtk_scrolled_window_new()!
        gtk_scrolled_window_set_policy(OpaquePointer(scrolled), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        Gtk.Widget(scrolled).setCSSClass("card", true)
        let view = gtk_text_view_new()!
        gtk_text_view_set_wrap_mode(typed(view), GTK_WRAP_WORD_CHAR)
        for margin in [gtk_text_view_set_left_margin, gtk_text_view_set_right_margin, gtk_text_view_set_top_margin, gtk_text_view_set_bottom_margin] {
            margin(typed(view), 6)
        }
        openLinksOnClick(view)
        gtk_scrolled_window_set_child(OpaquePointer(scrolled), view)
        gtk_overlay_set_child(OpaquePointer(overlay), scrolled)

        let placeholder = makePlaceholder(leading: 6, top: 6)
        gtk_overlay_add_overlay(OpaquePointer(overlay), placeholder)

        gtk_widget_set_hexpand(overlay, 1)
        gtk_widget_set_vexpand(overlay, 1)
        // Lines up on its first line, 6 below its top (the text view's margin), as macOS lines up a
        // TextEditor's title near its top (Baselines).
        attach(TextLineMarker(.top(inset: 6)), to: overlay, key: textLineMarkerKey)
        let buffer = gtk_text_view_get_buffer(typed(view))!
        reportEdits(of: buffer, placeholder: placeholder) { [weak node] in
            guard let node else { return }
            let props = Props(node.properties)
            if props.markdown != nil {
                userEditedAttributedText(MarkdownBuffer.of(buffer).attributedText(), valueChangeActionID: props.valueChangeActionID, node)
                return
            }
            TextField.userEditedText(bufferText(buffer), valueChangeActionID: props.valueChangeActionID, viewID: node.element.id,
                                     model: node.model, windowUUID: node.windowUUID)
        }
        return overlay
    }

    /// A dimmed placeholder label for the top leading corner of a text view, `leading` and `top`
    /// in from it (its text margins), wrapping; left out of the accessibility tree (the text view
    /// carries the placeholder as its name). A vertical TextField shows one too.
    static func makePlaceholder(leading: Int32, top: Int32) -> WidgetPointer {
        let placeholder = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        Gtk.Widget(placeholder).setCSSClass("dim-label", true)
        gtk_widget_set_halign(placeholder, GTK_ALIGN_START)
        gtk_widget_set_valign(placeholder, GTK_ALIGN_START)
        gtk_widget_set_margin_start(placeholder, leading)
        gtk_widget_set_margin_top(placeholder, top)
        gtk_widget_set_can_target(placeholder, 0)
        gtk_widget_set_margin_end(placeholder, leading)
        gtk_label_set_wrap(opaque(placeholder), 1)
        gtk_label_set_wrap_mode(opaque(placeholder), PANGO_WRAP_WORD_CHAR)
        gtk_label_set_xalign(opaque(placeholder), 0)
        return placeholder
    }

    /// Runs `report` once per edit the user makes to `buffer` (not for an update), and shows
    /// `placeholder` only while the text is empty and the placeholder has text. A vertical
    /// TextField reports its edits this way too.
    static func reportEdits(of buffer: UnsafeMutablePointer<GtkTextBuffer>, placeholder: WidgetPointer,
                            _ report: @escaping @MainActor () -> Void) {
        // GtkTextView makes each edit one user action, and typing over a selection, pasting and
        // dropping text are a delete, then an insert, each emitting "changed": the edit is reported
        // once, when its user action ends, as GtkText's "changed" is (no empty value in between).
        let userAction = UserActionState()
        connectSignal(UnsafeMutableRawPointer(buffer), "begin-user-action", .instanceOnly) {
            userAction.depth += 1
        }
        let endAction: @MainActor () -> Void = {
            userAction.depth -= 1
            guard userAction.depth == 0, userAction.changed else { return }
            userAction.changed = false
            if !UpdateGuard.isApplying {
                report()
            }
        }
        connectSignal(UnsafeMutableRawPointer(buffer), "end-user-action", .instanceOnly, endAction)
        // Undo and redo replace text outside a user action (a delete, then an insert): grouped the
        // same way, from before the signal's default handler, which does the work, to after it.
        for signal in ["undo", "redo"] {
            connectSignal(UnsafeMutableRawPointer(buffer), signal, .instanceOnly) {
                userAction.depth += 1
            }
            connectSignal(UnsafeMutableRawPointer(buffer), signal, .instanceOnly, after: true, endAction)
        }
        connectUserSignal(UnsafeMutableRawPointer(buffer), "changed", .instanceOnly) {
            if userAction.depth > 0 {
                userAction.changed = true
            } else {
                report()
            }
        }
        // The placeholder follows the text the user types too, not only the model's. (A character
        // count, not the text: no copy of a long text per keystroke.)
        connectSignal(UnsafeMutableRawPointer(buffer), "changed", .instanceOnly) {
            let hasPlaceholder = gtk_label_get_text(opaque(placeholder)).map { $0.pointee != 0 } ?? false
            Gtk.Widget(placeholder).isVisible = hasPlaceholder && gtk_text_buffer_get_char_count(buffer) == 0
        }
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let view = accessibleWidgetIfAny(widget), let placeholder = Gtk.Widget(widget).lastChild?.pointer else { return }
        let props = Props(node.properties)
        let buffer = gtk_text_view_get_buffer(typed(view))!
        let isEmpty: Bool
        if let markdown = props.markdown {
            let content = markdownContent(node.model.value, markdown: markdown)
            let styled = MarkdownBuffer.of(buffer)
            if styled.attributedText() != content {
                styled.show(content)
            }
            isEmpty = content.characters.isEmpty
        } else {
            let text = TextEditor.initialValue(node.model) as? String ?? ""
            if bufferText(buffer) != text {
                gtk_text_buffer_set_text(buffer, text, -1)
            }
            isEmpty = text.isEmpty
        }
        let editable: gboolean = props.readOnly ? 0 : 1
        if gtk_text_view_get_editable(typed(view)) != editable {
            // The cursor stays, so a read-only text can still be selected from the keyboard, as in
            // an NSTextView that does not edit.
            gtk_text_view_set_editable(typed(view), editable)
        }
        let placeholderText = props.placeholder ?? ""
        Gtk.Label(placeholder).text = placeholderText
        Gtk.Widget(placeholder).isVisible = !placeholderText.isEmpty && isEmpty
    }

    /// Opens a URL as GTK's own link handlers do (a GtkLabel's link, GtkLinkButton), with the
    /// widget's window as the parent. Tests replace it.
    static var openURI: @MainActor (String, WidgetPointer) -> Void = { uri, widget in
        let launcher = gtk_uri_launcher_new(uri)!
        gtk_uri_launcher_launch(launcher, gtk_widget_get_root(widget).map { typed($0) }, nil, nil, nil)
        g_object_unref(UnsafeMutableRawPointer(launcher))
    }

    /// In a markdown editor, a click on a link opens it, and the pointer is a hand over a link.
    private static func openLinksOnClick(_ view: WidgetPointer) {
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, guint(GDK_BUTTON_PRIMARY))
        connectClick(UnsafeMutableRawPointer(click), "released") { _, x, y in
            clickReleased(view, x, y)
        }
        gtk_widget_add_controller(view, click)
        let motion = gtk_event_controller_motion_new()!
        // Set only when the pointer moves onto or off a link: each set makes a new cursor.
        var overLink = false
        connectPoint(UnsafeMutableRawPointer(motion), "motion") { x, y in
            let buffer = gtk_text_view_get_buffer(typed(view))!
            guard MarkdownBuffer.existing(buffer) != nil else { return }
            let onLink = link(at: x, y, in: view) != nil
            if onLink != overLink {
                overLink = onLink
                gtk_widget_set_cursor_from_name(view, onLink ? "pointer" : "text")
            }
        }
        gtk_widget_add_controller(view, motion)
    }

    /// A click released at `x`, `y` in the text view: opens the link there, unless the click selected
    /// text (a drag ending on a link is not a click on it).
    static func clickReleased(_ view: WidgetPointer, _ x: Double, _ y: Double) {
        let buffer = gtk_text_view_get_buffer(typed(view))!
        var start = GtkTextIter()
        var end = GtkTextIter()
        guard gtk_text_buffer_get_selection_bounds(buffer, &start, &end) == 0, let url = link(at: x, y, in: view) else { return }
        openURI(url.absoluteString, view)
    }

    /// The link under `x`, `y` in the text view (its own coordinates), in a markdown editor.
    static func link(at x: Double, _ y: Double, in view: WidgetPointer) -> URL? {
        let textView: UnsafeMutablePointer<GtkTextView> = typed(view)
        guard let markdown = MarkdownBuffer.existing(gtk_text_view_get_buffer(textView)!) else { return nil }
        var bufferX: Int32 = 0
        var bufferY: Int32 = 0
        gtk_text_view_window_to_buffer_coords(textView, GTK_TEXT_WINDOW_WIDGET, Int32(x), Int32(y), &bufferX, &bufferY)
        var position = GtkTextIter()
        // The character under the point (get_iter_at_location moves past it on its right half).
        // Not over the text (past a line's end, below the last line): no link.
        var trailing: Int32 = 0
        guard gtk_text_view_get_iter_at_position(textView, &position, &trailing, bufferX, bufferY) != 0 else { return nil }
        return markdown.link(at: Int(gtk_text_iter_get_offset(&position)))
    }

    /// What a markdown editor shows: its AttributedString value, else its String value or the
    /// markdown property read as markdown (as SwiftUI's attributed TextEditor reads them).
    static func markdownContent(_ value: Any?, markdown: String) -> AttributedString {
        if let attributed = value as? AttributedString {
            return attributed
        }
        return ActionUIRendererHooks.markdown(value as? String ?? markdown)
    }

    /// What typing does in a markdown editor, as on Apple: stores the styled text as the value and
    /// fires valueChangeActionID, only when it differs from the value.
    private static func userEditedAttributedText(_ text: AttributedString, valueChangeActionID: String?, _ node: RenderNode) {
        guard node.model.value as? AttributedString != text else { return }
        node.model.value = text
        if let valueChangeActionID {
            ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
    }

    /// The text view, which assistive technologies read (the overlay holds it, scrolled, and the
    /// placeholder).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        accessibleWidgetIfAny(widget) ?? widget
    }

    /// Named after its placeholder, which says what to type.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).placeholder
    }

    private static func accessibleWidgetIfAny(_ widget: WidgetPointer) -> WidgetPointer? {
        guard let scrolled = gtk_overlay_get_child(OpaquePointer(widget)) else { return nil }
        return gtk_scrolled_window_get_child(OpaquePointer(scrolled))
    }

    /// The buffer's whole text.
    static func bufferText(_ buffer: UnsafeMutablePointer<GtkTextBuffer>) -> String {
        var start = GtkTextIter()
        var end = GtkTextIter()
        gtk_text_buffer_get_bounds(buffer, &start, &end)
        return takeGString(gtk_text_buffer_get_text(buffer, &start, &end, 0)) ?? ""
    }
}
