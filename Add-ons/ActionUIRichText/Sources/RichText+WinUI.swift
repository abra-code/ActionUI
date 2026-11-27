// Add-ons/ActionUIRichText/Sources/RichText+WinUI.swift
/*
 The RichText element on Windows, the counterpart of RichText.swift and RichText+Adwaita.swift: the same JSON (the
 sample and the properties are in RichText.swift) over the RichText package's model (RichTextDocument, parsed from
 Markdown), drawn in one WinUI RichTextBlock so the whole text is selectable and copyable as one, as on Apple
 platforms and Linux.

 What it draws: headings (bold, at the GTK renderer's scales of the body size), paragraphs, emphasis, strong,
 strikethrough, inline code (monospaced), links (in the theme's link color; opened as a Link opens its address, after
 RichText's own scheme check), line breaks, nested quotes (indented, in the secondary text color), lists (bullets or
 numbers, nested), fenced code (monospaced, line by line, in syntax colors when the theme asks), and behind the text,
 as on Apple platforms and Linux: code cards, quote bars, rules and the fill behind inline code; and tables as a grid,
 as the GTK renderer draws them: each row a paragraph of the same text, each cell placed at its column (left, center
 or right, as the Markdown aligns it) by a spacer before it, the columns as wide as their widest cell plus the
 theme's cell padding, lines at the column edges and between the rows, the header row bold on the code fill. A copy
 has a space between cells, where Linux has a tab. The cells are placed once the text is laid out, where WinUI's own
 measure of each cell is known (placeTables). Images are inline elements of the text at their places, loaded as
 "remoteImages" allows (RichText+WinUIImages.swift). Not yet: find, copy as HTML; a row wider than the element wraps
 (on Linux only its last cell wraps).

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

/// A shape drawn behind the text, at the place of one or more paragraphs (their indices in the block).
enum RichTextDecoration {
    /// A rounded card behind a code block's paragraph, from `indent` to the right edge.
    case codeCard(paragraph: Int, indent: Double)
    /// A bar beside a paragraph of the innermost quote it is in, at `x`, as on Apple platforms and Linux.
    case quoteBar(paragraph: Int, x: Double)
    /// A line through a rule's paragraph, from `indent` to the right edge.
    case rule(paragraph: Int, indent: Double)
    /// The fill behind inline code, the `inline`th inline of its paragraph, in three parts: its first line, the full
    /// lines between (one shape over them), and its last line; a part it does not have gets no size.
    case inlineCode(paragraph: Int, inline: Int, part: InlineCodePart)
    /// The fill behind a table's header row.
    case tableHeader(table: Int, row: Int)
    /// A line at a table row's `edge`th column edge (0: the table's left edge).
    case tableColumnLine(table: Int, row: Int, edge: Int)
    /// A line above (the first row) or below a table row.
    case tableRowLine(table: Int, row: Int, below: Bool)
}

/// A table as built: each row's paragraph and, for each cell, its spacer and its inlines (indices in the paragraph),
/// for placing the cells once the text is laid out; and its column edges, from that placing.
struct RichTextWinUITable {
    struct Cell {
        /// The space run before the cell (none before the first), the spacer that places it, and its width now.
        var separator: Int?
        var spacer: Int
        var spacerWidth: Double = 0
        /// The cell's first and last inline; nil for an empty cell, which is measured from what is before it.
        var content: ClosedRange<Int>?
    }

    struct Row {
        var paragraph: Int
        var cells: [Cell] = []
    }

    var indent: Double
    var padding: Double
    var alignments: [RichTextColumnAlignment]
    var rows: [Row] = []
    /// The column edges, from the table's left edge to its right; empty until the cells are placed.
    var edges: [Double] = []
}

enum InlineCodePart {
    case first, middle, last
}

/// An inline of a paragraph: the key of its measured lines during one arrange.
struct RichTextInlineKey: Hashable {
    var paragraph: Int
    var inline: Int
}

/// What an element instance keeps (RenderNode.state): a panel holding the RichTextBlock in front of the shapes
/// drawn behind its text, and what it shows.
@MainActor
final class RichTextWinUIState {
    /// The element's object: a panel laid out here (measureRichText, arrangeRichText).
    let panel: ShimObject
    let block: ShimObject
    /// The shapes behind the text, one per decoration, the panel's first children.
    private var shapes: [ShimObject] = []
    private var decorations: [RichTextDecoration] = []
    /// Each inline code's lines, measured once per arrange for its three shapes.
    private var inlineLines: [RichTextInlineKey: [ActionUIWinUIRect]] = [:]
    /// The tables, for placing their cells; how many layouts have moved cells since the text was built (bounded, in
    /// case a placing never settles).
    private var tables: [RichTextWinUITable] = []
    private var tablePlacings = 0
    /// The width at which every table was last found placed: at that width an arrange measures nothing again.
    private var tablesSettledAt: Double?
    /// The images in the text, and when their remote ones may load ("remoteImages").
    private var images: [RichTextWinUIImageSlot] = []
    private var remoteImages: RichTextRemoteImages = .automatic
    /// What the block shows: rebuilt when it changes.
    private var shown: Shown?
    private var document = RichTextDocument(blocks: [])
    private var theme = RichTextTheme.default
    private weak var node: RenderNode?

    /// The fill behind code (cards and inline code) and the color of quote bars and rules: theme brushes, as the
    /// GTK renderer derives them from the text color.
    static let codeFillBrush = "SubtleFillColorSecondaryBrush"
    static let separatorBrush = "DividerStrokeColorDefaultBrush"
    /// The space between a code card's edges and its text: beside it, and above and below it.
    static let codeInset = 10.0
    static let codeVerticalInset = 6.0
    /// A quote bar's width, and how far left of the quoted text it stands (Apple's and the GTK renderer's).
    static let quoteBarWidth = 3.0
    static let quoteBarGap = 12.0
    /// Inline code's fill: a little wider than its text, with rounded corners, as on Apple platforms.
    static let inlineCodeInset = 2.0
    static let inlineCodeCornerRadius = 3.0

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
        let layoutContext = Unmanaged.passRetained(WeakRichTextState()).toOpaque()
        guard let panel = ShimObject(adopting: actionUIWinUIPanelCreate(measureRichText, arrangeRichText, layoutContext,
                                                                        releaseWeakRichTextState)) else {
            logger.log("RichText: making its panel failed: \(lastShimError())", .error)
            return nil
        }
        self.block = block
        self.panel = panel
        self.node = node
        Unmanaged<WeakRichTextState>.fromOpaque(layoutContext).takeUnretainedValue().state = self
        guard actionUIWinUIPanelInsertChild(panel.pointer, 0, block.pointer) else {
            logger.log("RichText: placing its text failed: \(lastShimError())", .error)
            return nil
        }
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

    /// When the text's remote images may load; a change starts the ones it now allows (a held image loads at
    /// "automatic", or waits for a click at "on-click").
    func setRemoteImages(_ policy: RichTextRemoteImages) {
        guard policy != remoteImages else { return }
        remoteImages = policy
        for image in images {
            image.start(policy: policy)
        }
    }

    /// An image took its size: the text is laid out again, and its tables placed again (one may hold the image).
    private func imageArrived() {
        inlineLines = [:]
        tablePlacings = 0
        tablesSettledAt = nil
        _ = actionUIWinUIElementInvalidateMeasure(block.pointer)
        _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
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
        tables = builder.tables
        tablePlacings = 0
        tablesSettledAt = nil
        images = builder.images
        for image in images {
            image.sizeChanged = { [weak self] in self?.imageArrived() }
            image.start(policy: remoteImages)
        }
        replaceShapes(builder.decorations)
        _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
    }

    /// The shapes for `decorations`, in place of the old ones, behind the text.
    private func replaceShapes(_ newDecorations: [RichTextDecoration]) {
        for _ in shapes {
            _ = actionUIWinUIPanelRemoveChild(panel.pointer, 0)
        }
        shapes = []
        decorations = []
        for decoration in newDecorations {
            let radius: Double = switch decoration {
            case .codeCard: Double(theme.codeCornerRadius)
            case .quoteBar: Self.quoteBarWidth / 2
            case .rule, .tableHeader, .tableColumnLine, .tableRowLine: 0
            case .inlineCode: Self.inlineCodeCornerRadius
            }
            let kind = radius > 0 ? ActionUIWinUIShapeRoundedRectangle : ActionUIWinUIShapeRectangle
            guard let shape = ShimObject(adopting: actionUIWinUIShapeCreate(kind)) else { continue }
            let brush = switch decoration {
            case .codeCard, .inlineCode, .tableHeader: Self.codeFillBrush
            case .quoteBar, .rule, .tableColumnLine, .tableRowLine: Self.separatorBrush
            }
            _ = actionUIWinUIElementSetBrush(shape.pointer, ActionUIWinUIBrushFill, nil, brush)
            if radius > 0 {
                _ = actionUIWinUIShapeSetCornerRadius(shape.pointer, radius)
            }
            guard actionUIWinUIPanelInsertChild(panel.pointer, Int32(shapes.count), shape.pointer) else { continue }
            shapes.append(shape)
            decorations.append(decoration)
        }
    }

    // MARK: - Layout

    func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        // The text's size; a "fill" element is stretched by its container (expansion), as before the panel.
        let size = actionUIWinUIElementMeasure(block.pointer, available)
        for shape in shapes {
            _ = actionUIWinUIElementMeasure(shape.pointer, ActionUIWinUISize(width: 0, height: 0))
        }
        return size
    }

    /// The text over the whole size, then each shape where its paragraphs are, now that the text is laid out.
    func arrange(_ size: ActionUIWinUISize) {
        _ = actionUIWinUIElementArrange(block.pointer, ActionUIWinUIRect(x: 0, y: 0, width: size.width, height: size.height))
        // The text is laid out anew: its inline code is measured again.
        inlineLines = [:]
        placeTables(width: size.width)
        for (shape, decoration) in zip(shapes, decorations) {
            _ = actionUIWinUIElementArrange(shape.pointer, frame(of: decoration, width: size.width))
        }
    }

    /// Places each table's cells at their columns, from where WinUI laid out each cell's text: each column as wide as
    /// its widest cell plus the padding on both sides, each cell at its column's left, center or right. A spacer that
    /// must change is resized, and WinUI lays the text out again; the next arrange checks the result, which settles at
    /// once (each cell's place depends only on fixed widths before it), up to four times per build. A table whose rows
    /// wrap keeps its cells where they are until it fits again.
    private func placeTables(width: Double) {
        guard !tables.isEmpty, tablePlacings < 4, tablesSettledAt != width else { return }
        var moved = false
        var skipped = false
        nextTable: for index in tables.indices {
            var table = tables[index]
            // Each cell's start and width as laid out now: from its inlines' lines.
            var cells: [[(start: Double, width: Double)]] = []
            for row in table.rows {
                var measured: [(start: Double, width: Double)] = []
                var rowTop: Double?
                for cell in row.cells {
                    guard let content = cell.content else {
                        // An empty cell starts where its spacer ends: after the space before it, or at the row's start.
                        var before = table.indent
                        if let separator = cell.separator {
                            let rects = lines(of: RichTextInlineKey(paragraph: row.paragraph, inline: separator))
                            guard let last = rects.last else {
                                skipped = true
                                continue nextTable
                            }
                            before = last.x + last.width
                        }
                        measured.append((before + cell.spacerWidth, 0))
                        continue
                    }
                    var left = Double.infinity
                    var right = -Double.infinity
                    for inline in content {
                        for rect in lines(of: RichTextInlineKey(paragraph: row.paragraph, inline: inline)) {
                            // A row that wraps (the element is narrower than the table) is left as it is: its
                            // wrapped lines are no cell widths, and placing by them would widen the columns at
                            // each layout.
                            let top = rowTop ?? rect.y
                            rowTop = top
                            guard abs(rect.y - top) <= rect.height / 2 else {
                                skipped = true
                                continue nextTable
                            }
                            left = min(left, rect.x)
                            right = max(right, rect.x + rect.width)
                        }
                    }
                    // Not laid out yet: placed at a later arrange (the other tables are placed now).
                    guard left.isFinite, right.isFinite else {
                        skipped = true
                        continue nextTable
                    }
                    measured.append((left, max(0, right - left)))
                }
                cells.append(measured)
            }
            let columns = table.rows.map(\.cells.count).max() ?? 0
            var widths = [Double](repeating: 0, count: columns)
            for row in cells {
                for (column, cell) in row.enumerated() {
                    widths[column] = max(widths[column], cell.width)
                }
            }
            var edges = [table.indent]
            for width in widths {
                edges.append(edges[edges.count - 1] + table.padding * 2 + width)
            }
            table.edges = edges
            for (rowIndex, row) in table.rows.enumerated() {
                // How far the cells after a resized spacer have moved already.
                var shift = 0.0
                for (column, cell) in row.cells.enumerated() {
                    let measured = cells[rowIndex][column]
                    let room = widths[column] - measured.width
                    let alignment = column < table.alignments.count ? table.alignments[column] : .none
                    let offset = switch alignment {
                    case .right: room
                    case .center: room / 2
                    case .left, .none: 0.0
                    }
                    let wanted = edges[column] + table.padding + offset
                    let delta = wanted - (measured.start + shift)
                    // Half a point: WinUI may round a spacer to whole pixels, which must not count as a move.
                    guard abs(delta) > 0.5 else { continue }
                    let width = max(0, cell.spacerWidth + delta)
                    if actionUIWinUIRichTextBlockSetSpacerWidth(block.pointer, Int32(row.paragraph), Int32(cell.spacer), width) {
                        shift += width - cell.spacerWidth
                        table.rows[rowIndex].cells[column].spacerWidth = width
                        moved = true
                    }
                }
            }
            tables[index] = table
        }
        if !moved, !skipped {
            tablesSettledAt = width
        }
        if moved {
            tablePlacings += 1
            // Laid out again with the new spacers; the inlines move, so their lines are measured again.
            inlineLines = [:]
            _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
        }
    }

    /// The lines an inline takes, measured at the first ask in an arrange.
    private func lines(of key: RichTextInlineKey) -> [ActionUIWinUIRect] {
        if let known = inlineLines[key] {
            return known
        }
        var rects = [ActionUIWinUIRect](repeating: ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0), count: 64)
        let count = Int(actionUIWinUIRichTextBlockInlineLineBounds(block.pointer, Int32(key.paragraph), Int32(key.inline),
                                                                  &rects, Int32(rects.count)))
        let measured = Array(rects.prefix(max(0, count)))
        inlineLines[key] = measured
        return measured
    }

    private func bounds(_ paragraph: Int) -> ActionUIWinUIRect? {
        var rect = ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
        return actionUIWinUIRichTextBlockParagraphBounds(block.pointer, Int32(paragraph), &rect) ? rect : nil
    }

    private func frame(of decoration: RichTextDecoration, width: Double) -> ActionUIWinUIRect {
        let none = ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
        switch decoration {
        case .codeCard(let paragraph, let indent):
            guard let text = bounds(paragraph) else { return none }
            // The card around the text with its insets (the paragraph's margins make the room).
            let inset = Self.codeVerticalInset
            return ActionUIWinUIRect(x: indent, y: text.y - inset, width: max(0, width - indent), height: text.height + 2 * inset)
        case .quoteBar(let paragraph, let x):
            guard let text = bounds(paragraph) else { return none }
            return ActionUIWinUIRect(x: x, y: text.y, width: Self.quoteBarWidth, height: text.height)
        case .inlineCode(let paragraph, let inline, let part):
            let rects = lines(of: RichTextInlineKey(paragraph: paragraph, inline: inline))
            let count = rects.count
            let lines: ArraySlice<ActionUIWinUIRect>
            switch part {
            case .first: lines = rects.prefix(1)
            case .middle: lines = count > 2 ? rects[1..<(count - 1)] : []
            case .last: lines = count > 1 ? rects.suffix(1) : []
            }
            guard !lines.isEmpty else { return none }
            let left = lines.map(\.x).min() ?? 0
            let right = lines.map { $0.x + $0.width }.max() ?? 0
            let top = lines.map(\.y).min() ?? 0
            let bottom = lines.map { $0.y + $0.height }.max() ?? 0
            let inset = Self.inlineCodeInset
            return ActionUIWinUIRect(x: left - inset, y: top, width: max(0, right - left + 2 * inset), height: max(0, bottom - top))
        case .rule(let paragraph, let indent):
            guard let line = bounds(paragraph) else { return none }
            return ActionUIWinUIRect(x: indent, y: line.y + line.height / 2, width: max(0, width - indent), height: 1)
        case .tableHeader(let table, let row), .tableColumnLine(let table, let row, _), .tableRowLine(let table, let row, _):
            guard table < tables.count, row < tables[table].rows.count, let left = tables[table].edges.first,
                  let right = tables[table].edges.last, let line = bounds(tables[table].rows[row].paragraph) else {
                return none
            }
            // One-point lines on whole points, as the GTK renderer draws them.
            switch decoration {
            case .tableColumnLine(_, _, let edge):
                let edges = tables[table].edges
                guard edge < edges.count else { return none }
                return ActionUIWinUIRect(x: edges[edge].rounded(), y: line.y, width: 1, height: line.height)
            case .tableRowLine(_, _, let below):
                let y = (below ? line.y + line.height : line.y).rounded()
                return ActionUIWinUIRect(x: left.rounded(), y: y, width: right.rounded() - left.rounded() + 1, height: 1)
            default:
                return ActionUIWinUIRect(x: left, y: line.y, width: right - left, height: line.height)
            }
        }
    }
}

/// The panel callbacks' context: the state, not kept alive by it (the node keeps the state).
private let measureRichText: ActionUIWinUIMeasureCallback = { context, _, available in
    let weak = context.map { Unmanaged<WeakRichTextState>.fromOpaque($0).takeUnretainedValue() }
    return MainActor.assumeIsolated {
        guard let size = weak?.state?.measure(available) else { return ActionUIWinUISize(width: 0, height: 0) }
        // WinUI gets no more than it offered.
        return ActionUIWinUISize(width: min(size.width, available.width), height: min(size.height, available.height))
    }
}

private let arrangeRichText: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let weak = context.map { Unmanaged<WeakRichTextState>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        weak?.state?.arrange(finalSize)
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
    /// The shapes to draw behind the text, by paragraph index.
    private(set) var decorations: [RichTextDecoration] = []
    /// The tables, in the order of their decorations' table indices.
    private(set) var tables: [RichTextWinUITable] = []
    /// The images, in the order of the text.
    private(set) var images: [RichTextWinUIImageSlot] = []
    /// The paragraphs added so far: the next one's index.
    private var paragraphCount = 0
    /// Where the bar of the innermost quote being walked stands; nil outside quotes.
    private var quoteBarX: Double?
    /// Whether the block's theme is dark (the syntax colors' lighter shades): read once per build.
    private lazy var dark: Bool = actionUIWinUIElementIsDark(block)

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
        case .codeBlock(let language, let code):
            // In a card: the paragraph's margins leave its insets free.
            let inset = RichTextWinUIState.codeInset
            let vertical = RichTextWinUIState.codeVerticalInset
            decorations.append(.codeCard(paragraph: paragraphCount, indent: indent))
            paragraph(indent: indent + inset, rightIndent: inset, spaceBefore: vertical, spaceAfter: blockSpacing + vertical)
            appendCode(code, language: language, secondary: secondary)
        case .blockQuote(let inner):
            // A bar beside each of its paragraphs, left of the quoted text; a nested quote's paragraphs get only its bar.
            let outer = quoteBarX
            quoteBarX = indent + indentStep - RichTextWinUIState.quoteBarGap
            append(inner, indent: indent + indentStep, secondary: true)
            quoteBarX = outer
        case .list(let ordered, let start, _, let items):
            for (index, item) in items.enumerated() {
                let marker = ordered ? "\(start + index)." : "\u{2022}"
                appendItem(item, marker: marker, indent: indent, secondary: secondary)
            }
        case .thematicBreak:
            // A line through an empty line (a no-break space gives it the text's height, and copies as a space).
            decorations.append(.rule(paragraph: paragraphCount, indent: indent))
            paragraph(indent: indent, spaceBefore: blockSpacing * 0.5, spaceAfter: blockSpacing)
            run("\u{00A0}", style: 0, size: 0, secondary: true)
        case .table(let headers, let alignments, let rows):
            appendTable(headers: headers, alignments: alignments, rows: rows, indent: indent, secondary: secondary)
        }
    }

    /// A table: a paragraph per row (the header row bold), each cell after a spacer that places it at its column once
    /// the text is laid out (RichTextWinUIState.placeTables), a small space between cells for a copy; the
    /// header's fill, the lines at the column edges and between the rows behind it.
    private mutating func appendTable(headers: [[RichTextInline]], alignments: [RichTextColumnAlignment],
                                      rows: [[[RichTextInline]]], indent: Double, secondary: Bool) {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return }
        let tableIndex = tables.count
        var table = RichTextWinUITable(indent: indent, padding: Double(theme.cellPadding), alignments: alignments)
        let allRows = [headers] + rows
        for (rowIndex, cells) in allRows.enumerated() {
            let isLast = rowIndex == allRows.count - 1
            var row = RichTextWinUITable.Row(paragraph: paragraphCount)
            paragraph(indent: indent, spaceAfter: isLast ? blockSpacing : 0)
            if rowIndex == 0 {
                decorations.append(.tableHeader(table: tableIndex, row: rowIndex))
            }
            for column in 0..<columns {
                var separator: Int?
                if column > 0 {
                    // A space apart in a copy, a point's size. Not a tab: its width depends on where it starts, so a
                    // resized spacer before it would move the cells after it by more than the spacer changed.
                    run(" ", style: 0, size: 1, secondary: secondary)
                    separator = Int(actionUIWinUIRichTextBlockLastInlineIndex(block))
                }
                check(actionUIWinUIRichTextBlockAddSpacer(block, 0), "a table cell's place")
                let spacer = Int(actionUIWinUIRichTextBlockLastInlineIndex(block))
                append(column < cells.count ? cells[column] : [], style: rowIndex == 0 ? boldRun : 0, size: 0,
                       secondary: secondary)
                let last = Int(actionUIWinUIRichTextBlockLastInlineIndex(block))
                row.cells.append(.init(separator: separator, spacer: spacer, content: last > spacer ? (spacer + 1)...last : nil))
            }
            for edge in 0...columns {
                decorations.append(.tableColumnLine(table: tableIndex, row: rowIndex, edge: edge))
            }
            if rowIndex == 0 {
                decorations.append(.tableRowLine(table: tableIndex, row: rowIndex, below: false))
            }
            decorations.append(.tableRowLine(table: tableIndex, row: rowIndex, below: true))
            table.rows.append(row)
        }
        tables.append(table)
    }

    /// Fenced code, line by line in the monospaced face, its comments, strings, numbers and keywords in the syntax
    /// colors when the theme highlights (RichText's tokenizer, as on Apple and Linux; no language: not highlighted).
    private mutating func appendCode(_ code: String, language: String?, secondary: Bool) {
        let scalars = Array(code.unicodeScalars)
        var end = scalars.count
        if end > 0, scalars[end - 1] == "\n" {
            end -= 1
        }
        // Each scalar's token type, where a token covers it.
        var types = [RichTextSyntaxHighlighter.TokenType?](repeating: nil, count: end)
        if theme.syntaxHighlighting {
            for token in RichTextSyntaxHighlighter.tokenize(code, profile: .profile(for: language)) {
                for index in token.scalarRange where index < end {
                    types[index] = token.type
                }
            }
        }
        let size = baseSize * RichTextWinUIState.codeScale
        var segment = String.UnicodeScalarView()
        var segmentType: RichTextSyntaxHighlighter.TokenType?
        for index in 0..<end {
            let scalar = scalars[index]
            if scalar == "\n" || types[index] != segmentType {
                codeRun(String(segment), type: segmentType, size: size, secondary: secondary)
                segment = String.UnicodeScalarView()
                segmentType = types[index]
            }
            if scalar == "\n" {
                check(actionUIWinUIRichTextBlockAddLineBreak(block), "a line break")
            } else {
                segment.append(scalar)
            }
        }
        codeRun(String(segment), type: segmentType, size: size, secondary: secondary)
    }

    /// A run of code in the syntax color of `type` (none: the text color).
    private mutating func codeRun(_ text: String, type: RichTextSyntaxHighlighter.TokenType?, size: Double, secondary: Bool) {
        guard !text.isEmpty else { return }
        guard let type else {
            run(text, style: monospaceRun, size: size, secondary: secondary)
            return
        }
        var color = RichTextWinUISyntaxColors.color(type, dark: dark)
        check(actionUIWinUIRichTextBlockAddRun(block, text, monospaceRun, size, &color, nil), "a run")
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
                // On a light fill, as on Apple and Linux: shapes behind its first line, the lines between and its last.
                let inline = Int(actionUIWinUIRichTextBlockLastInlineIndex(block))
                if inline >= 0, paragraphCount > 0 {
                    for part in [InlineCodePart.first, .middle, .last] {
                        decorations.append(.inlineCode(paragraph: paragraphCount - 1, inline: inline, part: part))
                    }
                }
            case .link(let text, let url):
                link(text.plainText, url: url, style: style, size: size)
            case .image(let alt, let url):
                // A picture at its place in the text, loaded as "remoteImages" allows (RichText+WinUIImages.swift);
                // the alt text in brackets only if it cannot be placed.
                if let image = RichTextWinUIImageSlot(alt: alt, url: URL(string: url)),
                   actionUIWinUIRichTextBlockAddInlineElement(block, image.panel.pointer) {
                    images.append(image)
                } else {
                    run("[" + (alt.isEmpty ? "image" : alt) + "]", style: style | italicRun, size: size,
                        secondary: true)
                }
            case .lineBreak:
                check(actionUIWinUIRichTextBlockAddLineBreak(block), "a line break")
            }
        }
    }

    private mutating func paragraph(indent: Double, rightIndent: Double = 0, firstLineIndent: Double = 0,
                                    spaceBefore: Double = 0, spaceAfter: Double) {
        check(actionUIWinUIRichTextBlockAddParagraph(block, indent, rightIndent, firstLineIndent, spaceBefore, spaceAfter),
              "a paragraph")
        if let quoteBarX {
            decorations.append(.quoteBar(paragraph: paragraphCount, x: quoteBarX))
        }
        paragraphCount += 1
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

/// The syntax colors: the GTK renderer's (Adwaita's purple, red, blue and green), the darker shades on a light theme
/// and the lighter ones on a dark one.
enum RichTextWinUISyntaxColors {
    static func color(_ type: RichTextSyntaxHighlighter.TokenType, dark: Bool) -> ActionUIWinUIColor {
        switch type {
        case .keyword: return rgb(dark ? 0xDC8ADD : 0x813D9C)
        case .string: return rgb(dark ? 0xF66151 : 0xC01C28)
        case .number: return rgb(dark ? 0x99C1F1 : 0x1A5FB4)
        case .comment: return rgb(dark ? 0x8FF0A4 : 0x26A269)
        }
    }

    private static func rgb(_ hex: UInt32) -> ActionUIWinUIColor {
        ActionUIWinUIColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                           blue: Double(hex & 0xFF) / 255, alpha: 1)
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

/// The theme and layout callbacks' context: the state, not kept alive by it.
@MainActor
private final class WeakRichTextState {
    weak var state: RichTextWinUIState?

    init(_ state: RichTextWinUIState? = nil) {
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
        return actionUIWinUIRetain(state.panel.pointer)
    }

    /// The RichTextBlock, not the panel around it and its decorations: accessibility tools see the text.
    static func accessibleObject(_ view: OpaquePointer, _ node: RenderNode) -> OpaquePointer? {
        (node.state as? RichTextWinUIState)?.block.pointer
    }

    static func update(_ view: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? RichTextWinUIState else { return }
        let properties = node.properties
        // The runtime value wins, else the "markdown" property.
        let runtime = (node.model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let markdown = runtime ?? (properties["markdown"] as? String) ?? ""
        // The base path is asked whether it is a folder only if the content may read it (RichText+LocalImages.swift).
        let baseURL = markdownBaseURL(properties["baseURL"], mayProbe: { node.readsLocalFile($0) })
        // Before the text: a rebuild starts its images with the policy (RichTextView+RemoteImages.swift).
        state.setRemoteImages(effectiveRemoteImagesPolicy(properties["remoteImages"]))
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
