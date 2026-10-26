// Sources/Elements/Text+Adwaita.swift
/*
 Text on GTK: a GtkLabel that wraps as SwiftUI's Text does: at word boundaries, and inside a word
 that does not fit (measured on macOS: Text("eleven") offered 20 points breaks into three lines, and
 beside a filling sibling it takes half the row even below its longest word). Its natural width is
 the text on one line, its smallest one character (SwiftUI's Text has none; GTK cannot go below
 one), and it gets taller as it gets narrower.

 - The value (a String or an AttributedString set at run time) takes precedence over the markdown
   and text properties, as on Apple. Markdown is shown as SwiftUI's Text shows it (inline styles and
   links, Markdown/MarkdownText.swift), drawn from Pango markup; its links open in the user's browser
   through GTK's own handler, as SwiftUI's Text opens them with the system. A label with a link
   takes no keyboard focus either, as SwiftUI's Text on macOS.
 - An empty Text keeps one line's height, as on Apple. Apple needs a zero-width space for that; an
   empty GtkLabel has it already (measured), and the space would become its accessible name.
 - multilineTextAlignment (from the environment) justifies the lines. Where the wrapped text sits in
   the label follows the parent VStack's alignment (centered elsewhere): SwiftUI's Text box is as
   wide as its widest line and its parent places that box, while a GtkLabel is given the whole
   offered width.
 - textSelection (from the environment) makes the text selectable, but not focusable: SwiftUI's
   selectable Text takes no keyboard focus (measured on macOS), and a focusable GtkLabel would take
   the window's first focus. Mouse selection and the context menu's Copy work.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

extension Text: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let label = gtk_label_new(nil)!
        gtk_label_set_wrap(opaque(label), 1)
        gtk_label_set_wrap_mode(opaque(label), PANGO_WRAP_WORD_CHAR)
        // Tab passes it by: a selectable label or one with a link, kept unfocusable in update,
        // would otherwise stop Tab (GtkLabel's focus handler claims it moved focus when it did not).
        gtk_widget_set_can_focus(label, 0)
        return label
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let label = opaque(widget)
        let attributed = displayedAttributedText(node.model.value, node.properties)
        if let markup = MarkdownText.pangoMarkup(attributed) {
            if gtk_label_get_use_markup(label) == 0 || swiftString(gtk_label_get_label(label)) != markup {
                gtk_label_set_markup(label, markup)
            }
        } else if gtk_label_get_use_markup(label) != 0 {
            // Its text matches the plain text, but the markup's styles must go.
            gtk_label_set_text(label, String(attributed.characters))
        } else {
            Gtk.Label(widget).text = String(attributed.characters)
        }

        let environment = node.environment
        let justification: GtkJustification
        // Left and right are leading and trailing: GTK flips both for right-to-left text.
        switch environment.multilineTextAlignment {
        case .leading: justification = GTK_JUSTIFY_LEFT
        case .center: justification = GTK_JUSTIFY_CENTER
        case .trailing: justification = GTK_JUSTIFY_RIGHT
        }
        if gtk_label_get_justify(label) != justification {
            gtk_label_set_justify(label, justification)
        }
        let position = boxPosition(node)
        if gtk_label_get_xalign(label) != position {
            gtk_label_set_xalign(label, position)
        }
        let selectable: gboolean = environment.textSelectable ? 1 : 0
        if gtk_label_get_selectable(label) != selectable {
            gtk_label_set_selectable(label, selectable)
        }
        // Not focusable, as SwiftUI's Text, also when selectable or with a link (gtk_label_set_selectable
        // and markup with a link turn it on).
        if gtk_widget_get_focusable(widget) != 0 {
            gtk_widget_set_focusable(widget, 0)
        }
    }

    /// Where the wrapped text sits in the label: where the parent VStack would place a box as wide
    /// as its widest line (a tracked read of the parent's properties), else in the middle (also for
    /// a background or overlay view, which is not in its element's stack).
    static func boxPosition(_ node: RenderNode) -> Float {
        guard node.decoration == nil, let parent = node.parent else { return 0.5 }
        let alignment: StackSolver.Alignment
        if parent.renderer == VStack.self {
            alignment = VStack.stackAlignment(VStack.Props(parent.properties).alignment)
        } else if parent.renderer == LazyVStack.self {
            alignment = LazyVStack.stackAlignment(LazyVStack.Props(parent.properties).alignment)
        } else {
            return 0.5
        }
        switch alignment {
        case .start: return 0
        case .center: return 0.5
        case .end: return 1
        }
    }

    /// Named after its text, which a GtkLabel also writes itself; ModifierBox writes it back when an
    /// accessibilityLabel is removed (resetting the label removes GtkLabel's own).
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        displayedText(node)
    }

    /// What the label shows: the value, else the markdown, else the text property.
    static func displayedText(_ node: RenderNode) -> String {
        displayedText(node.model.value, node.properties)
    }

    /// What a Text with `value` and `properties` shows (also as a menu item), as plain text.
    static func displayedText(_ value: Any?, _ properties: [String: Any]) -> String {
        String(displayedAttributedText(value, properties).characters)
    }

    /// What a Text with `value` and `properties` shows: the value, else the markdown (parsed), else
    /// the text property.
    static func displayedAttributedText(_ value: Any?, _ properties: [String: Any]) -> AttributedString {
        if let attributed = value as? AttributedString {
            return attributed
        }
        if let plain = value as? String {
            return AttributedString(plain)
        }
        let props = Props(properties)
        return props.markdown.map(ActionUIRendererHooks.markdown) ?? AttributedString(props.text)
    }
}
