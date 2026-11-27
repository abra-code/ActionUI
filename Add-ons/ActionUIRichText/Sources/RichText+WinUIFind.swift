// Add-ons/ActionUIRichText/Sources/RichText+WinUIFind.swift
/*
 Find in the RichText element's text on Windows, the counterpart of RichTextGtkFindController in the RichText
 package's GTK view: the query, the options, the matches and the one the reader is on, painted behind the text, and
 whether the find bar (RichText+WinUIFindBar.swift) shows.

 - The text searched is the block's own, as WinUI holds it (actionUIWinUIRichTextBlockVisitText): each run's text,
   a line break and a new paragraph as a newline, and an inline element (a table cell's spacer, an image) as
   U+FFFC, which is no word character, so literal text matches across neither a paragraph nor a table cell (a
   regular expression's \s or . can, as in Apple's rendered string).
 - The engine is the RichText package's (RichTextSearch, over Windows' ICU), with its options and rules: case and
   diacritic folding, whole words, regular expressions, as on Apple platforms and Linux.
 - Each match is highlighted with WinUI's TextHighlighter (all matches in one color, the current in another, the GTK
   view's yellow and orange), whose index counts the text and line breaks only (TextReader). A highlight next to an
   inline element, which takes no position, can take it in: a match at a table cell's start paints the cell's
   leading space too.
 - As on Apple platforms and Linux: the match the reader was on stays current while it is still found, else the
   first is; next and previous wrap around.
*/

#if os(Windows)

import ActionUI
import CWinUI
import FoundationEssentials
import RichText

@MainActor
final class RichTextWinUIFind {
    /// The highlights' colors: every match, and the current one (the GTK view's).
    static let matchColor = ActionUIWinUIColor(red: 1, green: 0.85, blue: 0, alpha: 0.35)
    static let currentColor = ActionUIWinUIColor(red: 1, green: 0.6, blue: 0, alpha: 0.55)

    var query = "" {
        didSet {
            if query != oldValue {
                recompute()
            }
        }
    }

    var options = RichTextSearchOptions.default {
        didSet {
            if options != oldValue {
                recompute()
            }
        }
    }

    /// The matches, in the highlighter's positions (TextReader), and the one the reader is on.
    private(set) var ranges: [Range<Int>] = []
    private(set) var currentIndex: Int?
    /// Whether the find bar shows (the element follows it, while "showFindBar" is on).
    private(set) var isPresented = false
    /// Set by present(), cleared by the element once it put the focus in the bar's field (again on a repeat Ctrl+F).
    var focusRequested = false
    /// Runs after any change of the matches, the current match or the presentation (the bar follows it).
    var onChange: [@MainActor () -> Void] = []

    private let block: OpaquePointer
    /// The searched text, and where each of its pieces is among the highlighter's positions.
    private var text = ""
    private var pieces: [Piece] = []
    /// Whether the block's text changed since it was read: read again by the next search.
    private var textIsStale = true
    /// Whether highlights are set: with no match and none set, nothing is painted.
    private var hasHighlights = false

    /// A piece of the searched text: from `start` (UTF-16, in the searched text) `length` units, at the highlighter's
    /// `position`, where it takes `width` positions (its length, or none for an inline element's U+FFFC).
    struct Piece {
        var start: Int
        var length: Int
        var position: Int
        var width: Int
    }

    init(block: OpaquePointer) {
        self.block = block
    }

    /// "3 of 12", "No matches", or "" for an empty query; "Invalid expression" for a regular expression that does
    /// not compile (RichTextGtkFindController's words).
    var summary: String {
        if !query.unicodeScalars.contains(where: { !$0.properties.isWhitespace && $0 != "\u{200B}" }) {
            return ""
        }
        if !RichTextSearch.isValidQuery(query, options: options) {
            return "Invalid expression"
        }
        guard let currentIndex, !ranges.isEmpty else {
            return "No matches"
        }
        let capped = options.limit.map { ranges.count >= $0 } ?? false
        return "\(currentIndex + 1) of \(ranges.count)\(capped ? "+" : "")"
    }

    func next() {
        step(by: 1)
    }

    func previous() {
        step(by: -1)
    }

    /// Shows the bar. Its field takes the focus, unless `focus` is false: for a term from a search field of the
    /// host's (states["search"]), where the reader is typing.
    func present(focus: Bool = true) {
        isPresented = true
        focusRequested = focus
        changed()
    }

    /// Hides the bar and clears the query, so nothing stays painted.
    func dismiss() {
        isPresented = false
        focusRequested = false
        query = ""
        changed()
    }

    /// The block's text was built again (a new document or theme): search it again.
    func textChanged() {
        textIsStale = true
        recompute()
    }

    private func step(by delta: Int) {
        guard !ranges.isEmpty else { return }
        let count = ranges.count
        let base = currentIndex ?? (delta > 0 ? -1 : 0)
        currentIndex = ((base + delta) % count + count) % count
        changed()
    }

    private func recompute() {
        let previous = currentIndex.flatMap { ranges.indices.contains($0) ? ranges[$0] : nil }
        // No query, no reading: most elements never search.
        let blank = !query.unicodeScalars.contains(where: { !$0.properties.isWhitespace && $0 != "\u{200B}" })
        if !blank, textIsStale {
            readText()
            textIsStale = false
        }
        ranges = blank ? [] : RichTextSearch.ranges(in: text, query: query, options: options).compactMap(positions)
        if ranges.isEmpty {
            currentIndex = nil
        } else if let previous, let kept = ranges.firstIndex(of: previous) {
            currentIndex = kept
        } else {
            currentIndex = 0
        }
        changed()
    }

    private func changed() {
        if !ranges.isEmpty || hasHighlights {
            paint()
        }
        for run in onChange {
            run()
        }
    }

    private func paint() {
        hasHighlights = !ranges.isEmpty
        let starts = ranges.map { Int32(clamping: $0.lowerBound) }
        let lengths = ranges.map { Int32(clamping: $0.count) }
        let painted = starts.withUnsafeBufferPointer { starts in
            lengths.withUnsafeBufferPointer { lengths in
                actionUIWinUIRichTextBlockSetHighlights(block, starts.baseAddress, lengths.baseAddress,
                                                        Int32(clamping: ranges.count),
                                                        Int32(clamping: currentIndex ?? -1),
                                                        Self.matchColor, Self.currentColor)
            }
        }
        if !painted {
            ActionUIModel.shared.logger.log("RichText: highlighting the matches failed", .warning)
        }
    }

    // MARK: - The block's text

    /// Reads the block's text into `text` and `pieces`: a newline between paragraphs, which no text position holds.
    private func readText() {
        let reader = TextReader()
        let context = Unmanaged.passUnretained(reader).toOpaque()
        if !actionUIWinUIRichTextBlockVisitText(block, readRichTextPiece, context) {
            ActionUIModel.shared.logger.log("RichText: reading the text to find in failed", .warning)
        }
        text = reader.text
        pieces = reader.pieces
    }

    /// A range of the searched text (UTF-16) as the highlighter's positions: from where its first unit is to just
    /// after its last. A newline between paragraphs at either end is left out (no position holds it); nil for a
    /// range of nothing else.
    private func positions(_ range: Range<Int>) -> Range<Int>? {
        guard let first = pieceIndex(atOrAfter: range.lowerBound),
              let last = pieceIndex(atOrBefore: range.upperBound - 1), first <= last else {
            return nil
        }
        let firstPiece = pieces[first]
        let start = firstPiece.position + min(firstPiece.width, max(0, range.lowerBound - firstPiece.start))
        let lastPiece = pieces[last]
        let end = lastPiece.position + min(lastPiece.width, range.upperBound - lastPiece.start)
        return end > start ? start..<end : nil
    }

    // The first piece holding `unit` or starting after it.
    private func pieceIndex(atOrAfter unit: Int) -> Int? {
        var low = 0
        var high = pieces.count
        while low < high {
            let middle = (low + high) / 2
            if pieces[middle].start + pieces[middle].length <= unit {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < pieces.count ? low : nil
    }

    // The last piece holding `unit` or ending before it.
    private func pieceIndex(atOrBefore unit: Int) -> Int? {
        var low = 0
        var high = pieces.count
        while low < high {
            let middle = (low + high) / 2
            if pieces[middle].start <= unit {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low > 0 ? low - 1 : nil
    }
}

/// What actionUIWinUIRichTextBlockVisitText reports, gathered, with each piece's place among the positions a
/// TextHighlighter counts. Measured on Windows 11 (WinUI 3, Windows App SDK 2.7): a highlighter's index counts a
/// run's UTF-16 code units and a line break as one each, and neither a paragraph's start or end nor an inline element
/// (a spacer, an image); a TextPointer's Offset, which counts each element's edges too, is not that index.
private final class TextReader {
    var text = ""
    var pieces: [RichTextWinUIFind.Piece] = []
    private var units = 0
    private var position = 0
    private var paragraph: Int32?

    /// A run's text or a line break, or nil for an inline element: U+FFFC in the searched text, taking no position (a
    /// U+FFFC typed in the text is text, and takes one).
    func add(paragraph index: Int32, piece: String?) {
        if let paragraph, paragraph != index {
            // In the searched text only: no position holds it.
            text += "\n"
            units += 1
        }
        paragraph = index
        let shown = piece ?? "\u{FFFC}"
        let length = shown.utf16.count
        guard length > 0 else { return }
        let width = piece == nil ? 0 : length
        pieces.append(RichTextWinUIFind.Piece(start: units, length: length, position: position, width: width))
        text += shown
        units += length
        position += width
    }
}

private let readRichTextPiece: ActionUIWinUIRichTextPieceCallback = { context, paragraph, piece in
    guard let context else { return }
    Unmanaged<TextReader>.fromOpaque(context).takeUnretainedValue().add(paragraph: paragraph, piece: piece.map { String(cString: $0) })
}

#endif
