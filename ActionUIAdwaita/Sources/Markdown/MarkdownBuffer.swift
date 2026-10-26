// Sources/Markdown/MarkdownBuffer.swift
/*
 Markdown in a TextEditor on GTK: the AttributedString of MarkdownText shown in a GtkTextBuffer with
 text tags, the buffer read back as one, and typed text styled as SwiftUI's attributed TextEditor
 styles it. Measured on macOS 27, SwiftUI's TextEditor bound to an AttributedString(markdown:):
 - It draws the inline styles Text draws, with the blocks run together: bold, italic,
   strikethrough, monospaced code, and links in the accent color (not underlined).
 - Typed text, a new line included, takes the style of the character before it, at the start of
   the text that of the first character, and typed over a selection that of the selection's first
   character. A link is continued only inside it: text typed right after its end is plain.
 - A click on a link opens it in the default browser (NSWorkspace, not SwiftUI's openURL), and
   the pointer is a pointing hand over it. The TextEditor does that on GTK, with this buffer's links.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

private let markdownBufferKey = AttachKey<MarkdownBuffer>("actionui-markdown-buffer")

/// A GtkTextBuffer's markdown styles, kept on the buffer.
@MainActor final class MarkdownBuffer {
    /// Not retained: this object lives on the buffer and goes with it.
    private let buffer: UnsafeMutablePointer<GtkTextBuffer>
    private let styleTags: [(style: MarkdownStyle, tag: UnsafeMutablePointer<GtkTextTag>)]
    private var linkTags: [(url: URL, tag: UnsafeMutablePointer<GtkTextTag>)] = []
    /// Where the user's current action deleted text, and the style of its first character, which
    /// text typed in its place takes.
    private var replaced: (offset: Int, style: MarkdownStyle)?
    /// The style manager's handlers that recolor the links.
    private var colorHandlers: [gulong] = []

    /// The buffer's markdown styles, made on first use.
    static func of(_ buffer: UnsafeMutablePointer<GtkTextBuffer>) -> MarkdownBuffer {
        if let existing = attached(on: UnsafeMutableRawPointer(buffer), key: markdownBufferKey) {
            return existing
        }
        let made = MarkdownBuffer(buffer)
        attach(made, to: UnsafeMutableRawPointer(buffer), key: markdownBufferKey)
        return made
    }

    /// The buffer's markdown styles, if it has them (a TextEditor with markdown).
    static func existing(_ buffer: UnsafeMutablePointer<GtkTextBuffer>) -> MarkdownBuffer? {
        attached(on: UnsafeMutableRawPointer(buffer), key: markdownBufferKey)
    }

    private init(_ buffer: UnsafeMutablePointer<GtkTextBuffer>) {
        self.buffer = buffer
        styleTags = [
            (.bold, Self.newTag(in: buffer, [("weight", .int(700))])),
            (.italic, Self.newTag(in: buffer, [("style", .enumeration(pango_style_get_type(), Int32(PANGO_STYLE_ITALIC.rawValue)))])),
            (.strikethrough, Self.newTag(in: buffer, [("strikethrough", .boolean(true))])),
            (.code, Self.newTag(in: buffer, [("family", .string("monospace"))])),
        ]
        let raw = UnsafeMutableRawPointer(buffer)
        connectTextDeleting(raw) { [weak self] start, end in
            self?.deleting(start, end)
        }
        connectTextInserted(raw) { [weak self] start, end in
            self?.inserted(start, end)
        }
        connectSignal(raw, "end-user-action", .instanceOnly) { [weak self] in
            self?.replaced = nil
        }
        let manager = UnsafeMutableRawPointer(adw_style_manager_get_default()!)
        for signal in ["notify::dark", "notify::accent-color"] {
            colorHandlers.append(connectSignal(manager, signal, .instanceAndArgument) { [weak self] in
                self?.recolorLinks()
            })
        }
    }

    isolated deinit {
        let manager = UnsafeMutableRawPointer(adw_style_manager_get_default()!)
        for handler in colorHandlers {
            g_signal_handler_disconnect(manager, handler)
        }
    }

    // MARK: Content

    /// Replaces the buffer's text with `attributed`, styled. Not undoable, as gtk_text_buffer_set_text
    /// is not: undo would otherwise take the shown runs away one by one.
    func show(_ attributed: AttributedString) {
        gtk_text_buffer_begin_irreversible_action(buffer)
        defer { gtk_text_buffer_end_irreversible_action(buffer) }
        gtk_text_buffer_set_text(buffer, "", 0)
        var offset = 0
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            var end = GtkTextIter()
            gtk_text_buffer_get_end_iter(buffer, &end)
            gtk_text_buffer_insert(buffer, &end, text, -1)
            // A GtkTextBuffer counts characters as Unicode scalars.
            let count = text.unicodeScalars.count
            let style = run[MarkdownStyleAttribute.self] ?? []
            for entry in styleTags where style.contains(entry.style) {
                apply(entry.tag, offset, offset + count)
            }
            if let link = run.link {
                apply(linkTag(link), offset, offset + count)
            }
            offset += count
        }
    }

    /// The buffer's text, with its styles and links.
    func attributedText() -> AttributedString {
        var result = AttributedString()
        var start = GtkTextIter()
        gtk_text_buffer_get_start_iter(buffer, &start)
        while gtk_text_iter_is_end(&start) == 0 {
            var next = start
            // To the next change of any tag, or the end.
            gtk_text_iter_forward_to_tag_toggle(&next, nil)
            var piece = AttributedString(takeGString(gtk_text_buffer_get_text(buffer, &start, &next, 0)) ?? "")
            let style = self.style(at: &start)
            if !style.isEmpty {
                piece[MarkdownStyleAttribute.self] = style
            }
            piece.link = linkTags.first { gtk_text_iter_has_tag(&start, $0.tag) != 0 }?.url
            result.append(piece)
            start = next
        }
        return result
    }

    /// The link of the character at `offset`, if it is in one.
    func link(at offset: Int) -> URL? {
        var position = iter(offset)
        return linkTags.first { gtk_text_iter_has_tag(&position, $0.tag) != 0 }?.url
    }

    // MARK: Typing

    private func deleting(_ start: Int, _ end: Int) {
        guard !UpdateGuard.isApplying, end > start else { return }
        replaced = (start, style(at: start))
    }

    private func inserted(_ start: Int, _ end: Int) {
        guard !UpdateGuard.isApplying, end > start else { return }
        let count = Int(gtk_text_buffer_get_char_count(buffer))
        let style: MarkdownStyle
        if let replaced, replaced.offset == start {
            style = replaced.style
        } else if start > 0 {
            style = self.style(at: start - 1)
        } else if end < count {
            style = self.style(at: end)
        } else {
            style = []
        }
        replaced = nil
        let links = start > 0 && end < count
            ? linkTags.filter { hasTag($0.tag, at: start - 1) && hasTag($0.tag, at: end) }.map(\.tag)
            : []
        var from = iter(start)
        var to = iter(end)
        gtk_text_buffer_remove_all_tags(buffer, &from, &to)
        for entry in styleTags where style.contains(entry.style) {
            apply(entry.tag, start, end)
        }
        for tag in links {
            apply(tag, start, end)
        }
    }

    // MARK: Tags

    private func style(at offset: Int) -> MarkdownStyle {
        var position = iter(offset)
        return style(at: &position)
    }

    private func style(at position: inout GtkTextIter) -> MarkdownStyle {
        var style: MarkdownStyle = []
        for entry in styleTags where gtk_text_iter_has_tag(&position, entry.tag) != 0 {
            style.insert(entry.style)
        }
        return style
    }

    private func hasTag(_ tag: UnsafeMutablePointer<GtkTextTag>, at offset: Int) -> Bool {
        var position = iter(offset)
        return gtk_text_iter_has_tag(&position, tag) != 0
    }

    private func iter(_ offset: Int) -> GtkTextIter {
        var position = GtkTextIter()
        gtk_text_buffer_get_iter_at_offset(buffer, &position, Int32(offset))
        return position
    }

    private func apply(_ tag: UnsafeMutablePointer<GtkTextTag>, _ start: Int, _ end: Int) {
        var from = iter(start)
        var to = iter(end)
        gtk_text_buffer_apply_tag(buffer, tag, &from, &to)
    }

    /// The tag of a link to `url`, one per URL, in the accent color.
    private func linkTag(_ url: URL) -> UnsafeMutablePointer<GtkTextTag> {
        if let existing = linkTags.first(where: { $0.url == url }) {
            return existing.tag
        }
        let tag = Self.newTag(in: buffer, [("foreground-rgba", .rgba(Self.linkColor()))])
        linkTags.append((url, tag))
        return tag
    }

    private func recolorLinks() {
        let color = Self.linkColor()
        for entry in linkTags {
            Self.set(entry.tag, "foreground-rgba", .rgba(color))
        }
    }

    /// Adwaita's link color: the accent color for text, which is lighter in the dark style.
    private static func linkColor() -> GdkRGBA {
        let manager = adw_style_manager_get_default()
        var color = GdkRGBA()
        adw_accent_color_to_standalone_rgba(adw_style_manager_get_accent_color(manager), adw_style_manager_get_dark(manager), &color)
        return color
    }

    private enum TagValue {
        case int(Int32)
        case boolean(Bool)
        case string(String)
        case enumeration(GType, Int32)
        case rgba(GdkRGBA)
    }

    /// A new anonymous tag in the buffer's tag table, which keeps it.
    private static func newTag(in buffer: UnsafeMutablePointer<GtkTextBuffer>,
                               _ properties: [(String, TagValue)]) -> UnsafeMutablePointer<GtkTextTag> {
        let tag = gtk_text_tag_new(nil)!
        for (name, value) in properties {
            set(tag, name, value)
        }
        gtk_text_tag_table_add(gtk_text_buffer_get_tag_table(buffer), tag)
        g_object_unref(tag)
        return tag
    }

    private static func set(_ tag: UnsafeMutablePointer<GtkTextTag>, _ name: String, _ value: TagValue) {
        var gvalue = GValue()
        switch value {
        case .int(let number):
            g_value_init(&gvalue, GType(6 << G_TYPE_FUNDAMENTAL_SHIFT))
            g_value_set_int(&gvalue, number)
        case .boolean(let flag):
            g_value_init(&gvalue, GType(5 << G_TYPE_FUNDAMENTAL_SHIFT))
            g_value_set_boolean(&gvalue, flag ? 1 : 0)
        case .string(let text):
            g_value_init(&gvalue, GType(16 << G_TYPE_FUNDAMENTAL_SHIFT))
            g_value_set_string(&gvalue, text)
        case .enumeration(let type, let number):
            g_value_init(&gvalue, type)
            g_value_set_enum(&gvalue, number)
        case .rgba(var color):
            g_value_init(&gvalue, gdk_rgba_get_type())
            g_value_set_boxed(&gvalue, &color)
        }
        g_object_set_property(typed(OpaquePointer(tag)), name, &gvalue)
        g_value_unset(&gvalue)
    }
}
