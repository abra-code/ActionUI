// ActionUIWinUIApplication/WinUIApplication+Mark.swift
/*
 The yellow and black mark a host puts above a window's content (WindowOptions.mark), as actionui-mcp
 marks the windows an AI agent asked for on macOS and Linux: a band under the title bar, outside the
 window's content, so nothing the window's ActionUI JSON does reaches it.

 - A strip (12 tall) or a line (3 tall, black stripes across it), or a bar (26 tall) with a row under its
   notches: where the window's content came from (shortened in its middle to the room it has, its whole
   text in its tooltip, selectable), a button after it (one that reveals the file), then at the trailing
   edge a time and one button (a Save or Copy URL), each with the host's title and tooltip. Its text is
   dark on the yellow in light and dark mode alike.
 - Its buttons never take the keyboard focus (a window's first focus would land on them when its
   content has nothing to focus); a pointer, UI Automation and screen readers press them.
 - The row counts in the window's least width: a window is never narrower than its buttons, its time and
   a little of its source need (WinUIWindow.fit's minimumWidth).
 - WinUIApplication.revealInFileExplorer and copyToClipboard are what a host's buttons usually do.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
import CWinUI

extension WinUIApplication {
    /// The yellow and black mark above a window's content.
    public struct WindowMark: Sendable {
        public enum Kind: Sendable {
            /// A band with black notches along its top edge.
            case strip
            /// A thin line with black stripes across its whole height.
            case line
        }

        /// A button in a bar's row: its title, its tooltip, and what it does.
        public struct Button: Sendable {
            public var title: String
            public var toolTip: String?
            public var action: @MainActor @Sendable () -> Void

            public init(title: String, toolTip: String? = nil, action: @escaping @MainActor @Sendable () -> Void) {
                self.title = title
                self.toolTip = toolTip
                self.action = action
            }
        }

        /// The row of a bar: a strip tall enough to hold it.
        public struct Row: Sendable {
            /// Where the window's content came from (a file's path, a web address), shown shortened in its
            /// middle to the room the row leaves it, its whole text in its tooltip; nil: none.
            public var source: String?
            /// The button after the source (revealing the file); nil: none.
            public var reveal: Button?
            /// The text at the trailing edge (when the window was shown), and its tooltip.
            public var time: String
            public var timeToolTip: String?
            /// The last button (Save..., Copy URL); nil: none.
            public var button: Button?

            public init(source: String? = nil, reveal: Button? = nil, time: String, timeToolTip: String? = nil,
                        button: Button? = nil) {
                self.source = source
                self.reveal = reveal
                self.time = time
                self.timeToolTip = timeToolTip
                self.button = button
            }
        }

        public var kind: Kind
        /// A strip's row; nil: the plain strip.
        public var row: Row?

        public init(kind: Kind, row: Row? = nil) {
            self.kind = kind
            self.row = row
        }

        static let stripHeight = 12.0
        static let lineHeight = 3.0
        static let barHeight = 26.0
    }

    /// Opens File Explorer at the folder holding `path` with `path` selected, without opening it.
    @discardableResult
    public static func revealInFileExplorer(path: String) -> Bool {
        guard actionUIWinUIRevealInFileExplorer(path) else {
            ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("revealing \(path)"))", .warning)
            return false
        }
        return true
    }

    /// Puts `text` on the clipboard as plain text.
    @discardableResult
    public static func copyToClipboard(_ text: String) -> Bool {
        guard actionUIWinUIClipboardSetText(text) else {
            ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("copying to the clipboard"))", .warning)
            return false
        }
        return true
    }
}

/// A WindowMark made into WinUI objects: the band and, for a bar, its row.
@MainActor
final class MarkView {
    let band: WinUIObject
    private let row: MarkRow?

    init?(_ mark: WinUIApplication.WindowMark) {
        let isBar = mark.kind == .strip && mark.row != nil
        let height = mark.kind == .line ? WinUIApplication.WindowMark.lineHeight
                                        : isBar ? WinUIApplication.WindowMark.barHeight : WinUIApplication.WindowMark.stripHeight
        guard let band = WinUIObject(adopting: actionUIWinUIMarkCreate(mark.kind == .line ? ActionUIWinUIMarkLine : ActionUIWinUIMarkStrip, height)) else {
            ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("making a window's mark"))", .error)
            return nil
        }
        self.band = band
        if isBar, let content = mark.row {
            row = MarkRow(content)
            if let row, !actionUIWinUIMarkSetRow(band.pointer, row.panel.object.pointer) {
                ActionUIModel.shared.logger.log("WinUIApplication: \(WinUIError.last("putting the row in a window's bar"))", .error)
            }
        } else {
            row = nil
        }
    }

    /// The least width the mark needs: its row's buttons, time and a little of its source.
    var minimumWidth: Double {
        row?.minimumWidth ?? 0
    }
}

/// A bar's row: the source and its reveal button at the leading edge, the time and the last button at
/// the trailing edge, the source shortened in its middle to the room between them.
@MainActor
final class MarkRow {
    let panel: LayoutPanel
    private let source: WinUIObject?
    private let fullSource: String
    private let leading: [WinUIObject]
    private let trailing: [WinUIObject]
    private var sizes: [ObjectIdentifier: ActionUIWinUISize] = [:]

    static let inset = 10.0
    static let spacing = 6.0
    static let fontSize = 12.0
    /// The least of the source a narrow window keeps: a few characters and the ellipsis.
    static let leastSource = 60.0

    init?(_ content: WinUIApplication.WindowMark.Row) {
        guard let panel = try? LayoutPanel() else { return nil }
        self.panel = panel
        fullSource = content.source.map(Self.shownCharacters) ?? ""
        var leading: [WinUIObject] = []
        var trailing: [WinUIObject] = []
        var source: WinUIObject?
        if content.source != nil, let text = Self.text(fullSource, selectable: true) {
            _ = actionUIWinUIElementSetToolTip(text.pointer, fullSource)
            source = text
            leading.append(text)
        }
        if let reveal = content.reveal, let button = Self.button(reveal) {
            leading.append(button)
        }
        if let time = Self.text(content.time, selectable: false) {
            if let toolTip = content.timeToolTip {
                _ = actionUIWinUIElementSetToolTip(time.pointer, toolTip)
            }
            trailing.append(time)
        }
        if let last = content.button, let button = Self.button(last) {
            trailing.append(button)
        }
        self.source = source
        self.leading = leading
        self.trailing = trailing
        for part in leading + trailing {
            try? panel.append(part)
        }
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// The least width: every part at its size but the source, which keeps leastSource.
    var minimumWidth: Double {
        let fixed = (leading + trailing).filter { $0 !== source }.reduce(0) { $0 + natural($1).width }
        let gaps = Self.spacing * Double(max(leading.count + trailing.count - 1, 0)) + Self.spacing
        return (2 * Self.inset + fixed + gaps + (source == nil ? 0 : Self.leastSource)).rounded(.up)
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        sizes = [:]
        var height = 0.0
        for part in leading + trailing where part !== source {
            let size = natural(part)
            sizes[ObjectIdentifier(part)] = size
            height = max(height, size.height)
        }
        if let source {
            let fixed = (leading + trailing).filter { $0 !== source }.reduce(0) { $0 + (sizes[ObjectIdentifier($1)]?.width ?? 0) }
            let gaps = Self.spacing * Double(max(leading.count + trailing.count - 1, 0)) + Self.spacing
            let room = available.width.isFinite ? max(available.width - 2 * Self.inset - fixed - gaps, 0) : .infinity
            // Set before the text is measured in this pass, and every pass: the search leaves the block
            // holding the last text it tried, which need not be the one it found.
            let shown = shortened(fullSource, toFit: room, in: source)
            _ = actionUIWinUITextBlockSetText(source.pointer, shown)
            let size = source.measure(ActionUIWinUISize(width: .infinity, height: .infinity))
            sizes[ObjectIdentifier(source)] = ActionUIWinUISize(width: min(size.width, room), height: size.height)
            height = max(height, size.height)
        }
        return ActionUIWinUISize(width: available.width.isFinite ? available.width : minimumWidth, height: height)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        var x = Self.inset
        for part in leading {
            let size = sizes[ObjectIdentifier(part)] ?? ActionUIWinUISize(width: 0, height: 0)
            part.arrange(ActionUIWinUIRect(x: x, y: ((finalSize.height - size.height) / 2).rounded(), width: size.width, height: size.height))
            x += size.width + Self.spacing
        }
        var trailingX = finalSize.width - Self.inset
        for part in trailing.reversed() {
            let size = sizes[ObjectIdentifier(part)] ?? ActionUIWinUISize(width: 0, height: 0)
            trailingX -= size.width
            part.arrange(ActionUIWinUIRect(x: trailingX, y: ((finalSize.height - size.height) / 2).rounded(), width: size.width, height: size.height))
            trailingX -= Self.spacing
        }
    }

    /// `part`'s size with unbounded room.
    private func natural(_ part: WinUIObject) -> ActionUIWinUISize {
        part.measure(ActionUIWinUISize(width: .infinity, height: .infinity))
    }

    /// `text` with characters from its middle replaced by "..." until it fits `room` in `block`'s font;
    /// the whole text when it fits.
    private func shortened(_ text: String, toFit room: Double, in block: WinUIObject) -> String {
        func width(_ candidate: String) -> Double {
            _ = actionUIWinUITextBlockSetText(block.pointer, candidate)
            return block.measure(ActionUIWinUISize(width: .infinity, height: .infinity)).width
        }
        guard room.isFinite, width(text) > room else { return text }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        var best = "..."
        // The most characters kept, half from each end, that still fit.
        while low <= high {
            let kept = (low + high) / 2
            let head = String(characters.prefix((kept + 1) / 2))
            let tail = String(characters.suffix(kept / 2))
            let candidate = head + "..." + tail
            if width(candidate) <= room {
                best = candidate
                low = kept + 1
            } else {
                high = kept - 1
            }
        }
        return best
    }

    /// Control and direction characters as "?": a line break would make the row taller than the bar, and
    /// a direction override could make "x<RLO>txt.app" read as a text file (as the MCP server's bars show).
    static func shownCharacters(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) { return "?" }
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return "?"
            default: return scalar
            }
        }))
    }

    private static func text(_ string: String, selectable: Bool) -> WinUIObject? {
        guard let text = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else { return nil }
        _ = actionUIWinUITextBlockSetText(text.pointer, string)
        _ = actionUIWinUITextBlockSetWraps(text.pointer, false)
        _ = actionUIWinUITextBlockSetTrimmed(text.pointer, true)
        _ = actionUIWinUITextBlockSetSelectable(text.pointer, selectable)
        _ = actionUIWinUIElementSetFont(text.pointer, nil, fontSize, 0)
        return text
    }

    private static func button(_ content: WinUIApplication.WindowMark.Button) -> WinUIObject? {
        guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()) else { return nil }
        _ = actionUIWinUIButtonSetTitle(button.pointer, content.title)
        if let toolTip = content.toolTip {
            _ = actionUIWinUIElementSetToolTip(button.pointer, toolTip)
        }
        let action = content.action
        _ = actionUIWinUIElementSetFont(button.pointer, nil, fontSize, 0)
        _ = actionUIWinUIControlSetPadding(button.pointer, 8, 1, 8, 2)
        // Never the keyboard focus (as a macOS title bar's buttons): a window whose content has nothing
        // to focus would give it to the bar's first button, and a key the user meant elsewhere, as the
        // window opened, would press it. A pointer, UI Automation and screen readers still press it.
        _ = actionUIWinUIElementSetFocusable(button.pointer, false)
        WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a window bar's button") {
            action()
        }
        return button
    }
}
