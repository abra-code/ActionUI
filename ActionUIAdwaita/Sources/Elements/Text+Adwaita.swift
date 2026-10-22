// Sources/Elements/Text+Adwaita.swift
/*
 Text on GTK: a GtkLabel that wraps as SwiftUI's Text does: at word boundaries, and inside a word
 that does not fit (measured on macOS: Text("eleven") offered 20 points breaks into three lines, and
 beside a filling sibling it takes half the row even below its longest word). Its natural width is
 the text on one line, its smallest one character (SwiftUI's Text has none; GTK cannot go below
 one), and it gets taller as it gets narrower.

 - The value (a String or an AttributedString set at run time) takes precedence over the markdown
   and text properties, as on Apple. Markdown shows as its source text until the markdown parser
   arrives (FoundationEssentials has none).
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
        return label
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let label = opaque(widget)
        let text = displayedText(node)
        if swiftString(gtk_label_get_text(label)) != text {
            gtk_label_set_text(label, text)
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
            // Selectable, not focusable, as SwiftUI's Text (gtk_label_set_selectable turns it on).
            gtk_widget_set_focusable(widget, 0)
        }
    }

    /// Where the wrapped text sits in the label: where the parent VStack would place a box as wide
    /// as its widest line (a tracked read of the parent's properties), else in the middle.
    static func boxPosition(_ node: RenderNode) -> Float {
        guard let parent = node.parent else { return 0.5 }
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

    /// What the label shows: the value, else the markdown, else the text property.
    static func displayedText(_ node: RenderNode) -> String {
        if let attributed = node.model.value as? AttributedString {
            return String(attributed.characters)
        }
        if let plain = node.model.value as? String {
            return plain
        }
        let props = Props(node.properties)
        return props.markdown ?? props.text
    }
}
