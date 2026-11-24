// Add-ons/ActionUIRichText/Sources/RichText+WinUI.swift
/*
 The RichText element on Windows, the counterpart of RichText.swift and RichText+Adwaita.swift: the same JSON (the
 sample and the properties are in RichText.swift) over the RichText package's model (RichTextDocument, parsed from
 Markdown), drawn in one WinUI RichTextBlock so the whole text is selectable and copyable as one, as on Apple
 platforms and Linux.

 What it draws: headings (bold, at the GTK renderer's scales of the body size), paragraphs, emphasis, strong,
 strikethrough, inline code (monospaced), links (in the theme's link color; opened as a Link opens its address, after
 RichText's own scheme check), line breaks, nested quotes (indented, in the secondary text color), lists (bullets or
 numbers, nested), fenced code (monospaced, line by line). Not yet: the code card and quote bar behind the text, the
 rule's line, tables as a grid, images (an image shows its alt text in brackets), syntax colors, find, copy as HTML.
 Those follow, as on Linux.

 Built only from ActionUI's interface for add-ons (ActionUIWinUIElement, RenderNode) and the shim's C functions
 (CWinUI's rich text group). The metrics are the GTK renderer's (RichTextGtkBuilder: heading scales, code scale)
 and RichTextTheme's (indent step, block and list spacing). A theme brush is taken when a run is made, so a change
 of theme builds the text again.
*/

#if os(Windows)

import ActionUI
import CWinUI
import FoundationEssentials
import RichText

/// One reference to a WinUI object of the shim's, given back when this goes.
final class ShimObject {
    let pointer: OpaquePointer

    init?(adopting pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        self.pointer = pointer
    }

    deinit {
        actionUIWinUIRelease(pointer)
    }
}

/// The shim's last error on this thread, for the log.
private func lastShimError() -> String {
    var buffer = [CChar](repeating: 0, count: 1024)
    let copied = buffer.withUnsafeMutableBufferPointer { actionUIWinUICopyLastError($0.baseAddress, $0.count) }
    let message = copied ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    return message.isEmpty ? "(no message)" : message
}

// The run style flags as the shim takes them (uint32_t): a C enum imports with a raw type that differs between
// platforms (Int32 on Windows).
private let boldRun = UInt32(truncatingIfNeeded: ActionUIWinUIRunBold.rawValue)
private let italicRun = UInt32(truncatingIfNeeded: ActionUIWinUIRunItalic.rawValue)
private let strikethroughRun = UInt32(truncatingIfNeeded: ActionUIWinUIRunStrikethrough.rawValue)
private let monospaceRun = UInt32(truncatingIfNeeded: ActionUIWinUIRunMonospace.rawValue)

/// What an element instance keeps (RenderNode.state): the RichTextBlock and what it shows.
@MainActor
final class RichTextWinUIState {
    let block: ShimObject
    /// What the block shows: rebuilt when it changes.
    private var shown: Shown?
    private var document = RichTextDocument(blocks: [])
    private var theme = RichTextTheme.default
    private weak var node: RenderNode?

    struct Shown: Equatable {
        var markdown: String
        var baseURL: URL?
        var theme: RichTextTheme
    }

    /// WinUI's body text size, the base when the element names none.
    static let bodySize = 14.0
    /// The GTK renderer's heading scales of the body size (RichTextGtkBuilder.headingScale), h1 to h5 and below.
    static let headingScale: [Double] = [22.0 / 13, 17.0 / 13, 15.0 / 13, 1, 11.0 / 13]
    /// Code blocks' size, of the body size (RichTextGtkBuilder.codeScale).
    static let codeScale = 0.94
    static let secondaryBrush = "TextFillColorSecondaryBrush"

    init?(node: RenderNode, logger: any ActionUILogger) {
        guard let block = ShimObject(adopting: actionUIWinUIRichTextBlockCreate()) else {
            logger.log("RichText: making its text block failed: \(lastShimError())", .error)
            return nil
        }
        self.block = block
        self.node = node
        let context = Unmanaged.passRetained(WeakRichTextState(self)).toOpaque()
        if !actionUIWinUIElementOnActualThemeChanged(block.pointer, richTextThemeChanged, context, releaseWeakRichTextState) {
            logger.log("RichText: following the theme failed: \(lastShimError())", .warning)
        }
    }

    /// Shows `markdown` (its relative image paths resolved against `baseURL`, its local images as the node's
    /// content may read them) in `theme`; the same as shown changes nothing.
    func show(markdown: String, baseURL: URL?, theme: RichTextTheme) {
        let wanted = Shown(markdown: markdown, baseURL: baseURL, theme: theme)
        guard wanted != shown, let node else { return }
        shown = wanted
        self.theme = theme
        // The trust policy judges the file a file: image's URL names as Windows opens it (a host is a share).
        document = RichTextView.document(markdown: markdown, baseURL: baseURL, readsURL: { node.readsFileURL($0) })
        rebuild()
    }

    /// Builds the text again, as the theme has it now.
    func themeChanged() {
        rebuild()
    }

    private func rebuild() {
        let baseSize = theme.baseFontSize.map { Double($0) } ?? Self.bodySize
        _ = actionUIWinUIRichTextBlockClear(block.pointer)
        _ = actionUIWinUIRichTextBlockSetFontSize(block.pointer, theme.baseFontSize.map { Double($0) } ?? 0)
        var builder = RichTextWinUIBuilder(block: block.pointer, theme: theme, baseSize: baseSize, node: node)
        builder.append(document.blocks, indent: 0, secondary: false)
        if let failure = builder.failure {
            ActionUIModel.shared.logger.log("RichText: \(failure)", .warning)
        }
    }
}

/// Walks the model into the block's paragraphs and runs.
@MainActor
struct RichTextWinUIBuilder {
    let block: OpaquePointer
    let theme: RichTextTheme
    let baseSize: Double
    weak var node: RenderNode?
    /// The first shim failure, logged once after the walk.
    private(set) var failure: String?

    init(block: OpaquePointer, theme: RichTextTheme, baseSize: Double, node: RenderNode?) {
        self.block = block
        self.theme = theme
        self.baseSize = baseSize
        self.node = node
    }

    private var indentStep: Double { Double(theme.indentStep) }
    private var blockSpacing: Double { Double(theme.blockSpacing) }
    private var listSpacing: Double { Double(theme.listSpacing) }

    mutating func append(_ blocks: [RichTextBlock], indent: Double, secondary: Bool) {
        for block in blocks {
            append(block, indent: indent, secondary: secondary)
        }
    }

    mutating func append(_ block: RichTextBlock, indent: Double, secondary: Bool) {
        switch block {
        case .heading(let level, let inlines):
            let scale = RichTextWinUIState.headingScale[min(max(level, 1), RichTextWinUIState.headingScale.count) - 1]
            paragraph(indent: indent, spaceBefore: blockSpacing * 0.6, spaceAfter: blockSpacing * 0.5)
            append(inlines, style: boldRun, size: baseSize * scale, secondary: secondary)
        case .paragraph(let inlines):
            paragraph(indent: indent, spaceAfter: blockSpacing)
            append(inlines, style: 0, size: 0, secondary: secondary)
        case .codeBlock(_, let code):
            paragraph(indent: indent, spaceAfter: blockSpacing)
            var lines = code.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.last == "" {
                lines.removeLast()
            }
            for (index, line) in lines.enumerated() {
                if index > 0 {
                    check(actionUIWinUIRichTextBlockAddLineBreak(self.block), "a line break")
                }
                run(String(line), style: monospaceRun, size: baseSize * RichTextWinUIState.codeScale,
                    secondary: secondary)
            }
        case .blockQuote(let inner):
            append(inner, indent: indent + indentStep, secondary: true)
        case .list(let ordered, let start, _, let items):
            for (index, item) in items.enumerated() {
                let marker = ordered ? "\(start + index)." : "\u{2022}"
                appendItem(item, marker: marker, indent: indent, secondary: secondary)
            }
        case .thematicBreak:
            // Until the line is drawn behind the text: a row of light box-drawing strokes.
            paragraph(indent: indent, spaceBefore: blockSpacing * 0.5, spaceAfter: blockSpacing)
            run(String(repeating: "\u{2500}", count: 24), style: 0, size: 0, secondary: true)
        case .table(let headers, _, let rows):
            // Until tables are a grid: each row a line, its cells apart.
            for (rowIndex, cells) in ([headers] + rows).enumerated() {
                paragraph(indent: indent, spaceAfter: rowIndex == rows.count ? blockSpacing : 2)
                for (cellIndex, cell) in cells.enumerated() {
                    if cellIndex > 0 {
                        run("  \u{2502}  ", style: 0, size: 0, secondary: true)
                    }
                    append(cell, style: rowIndex == 0 ? boldRun : 0, size: 0, secondary: secondary)
                }
            }
        }
    }

    /// A list item: its first paragraph after the marker on a hanging line, the rest of its blocks one step in.
    private mutating func appendItem(_ item: [RichTextBlock], marker: String, indent: Double, secondary: Bool) {
        let inner = indent + indentStep
        var rest = item[...]
        if case .paragraph(let inlines)? = rest.first {
            rest = rest.dropFirst()
            paragraph(indent: inner, firstLineIndent: -indentStep, spaceAfter: listSpacing)
            run(marker + " ", style: 0, size: 0, secondary: secondary)
            append(inlines, style: 0, size: 0, secondary: secondary)
        } else {
            paragraph(indent: inner, firstLineIndent: -indentStep, spaceAfter: listSpacing)
            run(marker, style: 0, size: 0, secondary: secondary)
        }
        append(Array(rest), indent: inner, secondary: secondary)
    }

    mutating func append(_ inlines: [RichTextInline], style: UInt32, size: Double, secondary: Bool) {
        for inline in inlines {
            switch inline {
            case .text(let text):
                run(text, style: style, size: size, secondary: secondary)
            case .emphasis(let children):
                append(children, style: style | italicRun, size: size, secondary: secondary)
            case .strong(let children):
                append(children, style: style | boldRun, size: size, secondary: secondary)
            case .strikethrough(let children):
                append(children, style: style | strikethroughRun, size: size, secondary: secondary)
            case .code(let text):
                // The body's monospaced size wherever it is, as on Apple platforms and Linux; not bold in a heading.
                run(text, style: (style & ~boldRun) | monospaceRun,
                    size: 0, secondary: secondary)
            case .link(let text, let url):
                link(text.plainText, url: url, style: style, size: size)
            case .image(let alt, _):
                // Until images load: the alt text, as a picture that cannot be shown.
                run("[" + (alt.isEmpty ? "image" : alt) + "]", style: style | italicRun, size: size,
                    secondary: true)
            case .lineBreak:
                check(actionUIWinUIRichTextBlockAddLineBreak(block), "a line break")
            }
        }
    }

    private mutating func paragraph(indent: Double, firstLineIndent: Double = 0, spaceBefore: Double = 0,
                                    spaceAfter: Double) {
        check(actionUIWinUIRichTextBlockAddParagraph(block, indent, firstLineIndent, spaceBefore, spaceAfter), "a paragraph")
    }

    private mutating func run(_ text: String, style: UInt32, size: Double, secondary: Bool) {
        check(actionUIWinUIRichTextBlockAddRun(block, text, style, size, nil, secondary ? RichTextWinUIState.secondaryBrush : nil),
              "a run")
    }

    /// A link that opens `url` when RichText's policy takes its scheme (http, https, mailto, tel) and the node's
    /// content may open it (RenderNode.openLink); any other link is plain text, as on Apple and Linux.
    private mutating func link(_ text: String, url: String, style: UInt32, size: Double) {
        guard let allowed = RichTextURLPolicy.allowedLink(url) else {
            run(text, style: style, size: size, secondary: false)
            return
        }
        let context = Unmanaged.passRetained(RichTextLinkTarget(url: allowed.absoluteString, node: node)).toOpaque()
        check(actionUIWinUIRichTextBlockAddLink(block, text, style, size, openRichTextLink, context, releaseRichTextLink),
              "a link")
    }

    private mutating func check(_ added: Bool, _ what: String) {
        if !added, failure == nil {
            failure = "adding \(what) failed: \(lastShimError())"
        }
    }
}

/// A link's context: the address and its node, which it does not keep alive.
@MainActor
private final class RichTextLinkTarget {
    let url: String
    weak var node: RenderNode?

    init(url: String, node: RenderNode?) {
        self.url = url
        self.node = node
    }
}

private let openRichTextLink: ActionUIWinUICallback = { context in
    let target = context.map { Unmanaged<RichTextLinkTarget>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        guard let target, let node = target.node else { return }
        node.openLink(target.url)
    }
}

private let releaseRichTextLink: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<RichTextLinkTarget>.fromOpaque(context).release()
}

/// The theme callback's context: the state, not kept alive by it.
@MainActor
private final class WeakRichTextState {
    weak var state: RichTextWinUIState?

    init(_ state: RichTextWinUIState) {
        self.state = state
    }
}

private let richTextThemeChanged: ActionUIWinUICallback = { context in
    let weak = context.map { Unmanaged<WeakRichTextState>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        weak?.state?.themeChanged()
    }
}

private let releaseWeakRichTextState: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<WeakRichTextState>.fromOpaque(context).release()
}

// MARK: - The element

struct RichTextView: ActionUIWinUIElement {
    // The element's runtime value is the Markdown source string.
    static var valueType: Any.Type { String.self }

    // "" (not nil) when no value is set yet, so the String valueType has an initial value; an empty string means
    // "no runtime source", and update then falls back to the "markdown" property.
    static var initialValue: (ViewModel) -> Any? { { model in (model.value as? String) ?? "" } }

    // Seeded as an empty String, as on Apple and Linux: a state key's first write fixes its type. (Find, which reads
    // it, follows on Windows.)
    static var initialStates: (ViewModel) -> [String: Any] {
        { model in
            var states = model.states
            if states["search"] == nil {
                states["search"] = ""
            }
            return states
        }
    }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeView(_ node: RenderNode) -> OpaquePointer? {
        guard let state = RichTextWinUIState(node: node, logger: ActionUIModel.shared.logger) else { return nil }
        node.state = state
        // The node takes over a reference of its own; the state keeps its own.
        return actionUIWinUIRetain(state.block.pointer)
    }

    static func update(_ view: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? RichTextWinUIState else { return }
        let properties = node.properties
        // The runtime value wins, else the "markdown" property.
        let runtime = (node.model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let markdown = runtime ?? (properties["markdown"] as? String) ?? ""
        // The base path is asked whether it is a folder only if the content may read it (RichText+LocalImages.swift).
        let baseURL = markdownBaseURL(properties["baseURL"], mayProbe: { node.readsLocalFile($0) })
        state.show(markdown: markdown, baseURL: baseURL, theme: theme(properties))
    }

    /// "fill" (the default) takes the width it is offered; "hug" takes its text's, wrapping only at what it is offered.
    static func expansion(_ node: RenderNode) -> ActionUIExpansion {
        node.properties["widthBehavior"] as? String == "hug" ? [] : .horizontal
    }

    /// Its text wraps, so a stack can make it narrower, as a Text.
    static func compression(_ node: RenderNode) -> ActionUIExpansion {
        .horizontal
    }

    // Starts from the package's default theme, overriding what the JSON gives (as on Linux).
    private static func theme(_ properties: [String: Any]) -> RichTextTheme {
        var theme = RichTextTheme.default
        switch properties["baseFontSize"] {
        case let size as any BinaryFloatingPoint: theme.baseFontSize = RichTextLength(Double(size))
        case let size as Int: theme.baseFontSize = RichTextLength(size)
        default: break
        }
        if let highlighting = properties["syntaxHighlighting"] as? Bool {
            theme.syntaxHighlighting = highlighting
        }
        return theme
    }
}

#endif
