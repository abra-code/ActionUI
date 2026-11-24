// Add-ons/ActionUIDiff/Sources/ActionUIDiff/Diff+WinUI.swift
/*
 The Diff element on Windows, the counterpart of Diff.swift and Diff+Adwaita.swift: the same JSON (the sample and
 the properties are in Diff.swift) over DiffView's model and presentation (DiffComputer, DiffPresentation), drawn
 with WinUI as DiffView's GTK view draws it: a column of rows on a faint rounded background; each row the old and
 new line numbers, the +/- marker and the line, on a red tint for a removed line and a green one for an added line;
 "N unchanged lines" where context collapsed; and the same notes for identical texts, inputs too large to diff, and
 a diff cut at maxRenderedLines.

 As on Apple and Linux: display-only (no value), every property live, text winning over file per side
 (DiffInput.swift), and a file that cannot be read shown as a "Cannot read <path>" note instead of a diff. The
 element takes the width it is offered and is as tall as its rows; a long diff goes in a ScrollView. Each piece of
 text is a selectable TextBlock, and a long line wraps.

 Built only from ActionUI's interface for add-ons (ActionUIWinUIElement, RenderNode) and the shim's C functions
 (CWinUI). The look is the WinUI renderer's for the SwiftUI styles DiffView uses: caption text is 12 points
 (Cascadia Mono, else Consolas, for the lines); secondary text is the theme's secondary text brush; Color.red and
 Color.green are the renderer's at 12 percent; the background is the theme's subtle fill. A theme brush is taken
 when an object is made, so a change of theme builds the rows again.
*/

#if os(Windows)

import ActionUI
import CWinUI
import DiffView
import FoundationEssentials
import WinSDK

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

// MARK: - Panels

/// How a panel made by makePanel lays out its children.
@MainActor
protocol DiffPanelLayout: AnyObject {
    /// The size the panel wants for `available` (a dimension may be infinite); measures every child.
    func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize
    /// Places every child in `size`.
    func arrange(_ size: ActionUIWinUISize)
}

/// The callbacks' context: the layout, kept by the panel until the panel is gone. Main-actor isolated, so it may
/// cross into the main actor; the raw pointer may not.
@MainActor
private final class LayoutBox {
    let layout: any DiffPanelLayout

    init(_ layout: any DiffPanelLayout) {
        self.layout = layout
    }
}

private func layoutBox(_ context: UnsafeMutableRawPointer?) -> LayoutBox? {
    context.map { Unmanaged<LayoutBox>.fromOpaque($0).takeUnretainedValue() }
}

private let measureLayout: ActionUIWinUIMeasureCallback = { context, _, available in
    let box = layoutBox(context)
    return MainActor.assumeIsolated {
        guard let size = box?.layout.measure(available) else { return ActionUIWinUISize(width: 0, height: 0) }
        // WinUI gets no more than it offered.
        return ActionUIWinUISize(width: min(size.width, available.width), height: min(size.height, available.height))
    }
}

private let arrangeLayout: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let box = layoutBox(context)
    MainActor.assumeIsolated {
        box?.layout.arrange(finalSize)
    }
}

private let releaseLayout: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<LayoutBox>.fromOpaque(context).release()
}

/// A new panel laid out by `layout`, which the panel keeps until it is gone.
@MainActor
private func makePanel(_ layout: any DiffPanelLayout) -> ShimObject? {
    let context = Unmanaged.passRetained(LayoutBox(layout)).toOpaque()
    // On failure the shim has already called releaseLayout.
    return ShimObject(adopting: actionUIWinUIPanelCreate(measureLayout, arrangeLayout, context, releaseLayout))
}

/// A column: each child as wide as the column less its horizontal space, one under the other.
@MainActor
final class DiffColumnLayout: DiffPanelLayout {
    /// A child, and the space kept on each side of it (horizontal) and above and below it (vertical).
    struct Item {
        let object: ShimObject
        let horizontal: Double
        let vertical: Double
    }

    var items: [Item] = []
    private var heights: [Double] = []

    func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        heights = []
        var width = 0.0
        var height = 0.0
        for item in items {
            let offered = ActionUIWinUISize(width: available.width.isFinite ? max(available.width - 2 * item.horizontal, 0) : .infinity,
                                            height: .infinity)
            let size = actionUIWinUIElementMeasure(item.object.pointer, offered)
            heights.append(size.height)
            width = max(width, size.width + 2 * item.horizontal)
            height += size.height + 2 * item.vertical
        }
        // The width it is offered, as the SwiftUI view takes it.
        return ActionUIWinUISize(width: available.width.isFinite ? available.width : width, height: height)
    }

    func arrange(_ size: ActionUIWinUISize) {
        var y = 0.0
        for (index, item) in items.enumerated() {
            let height = index < heights.count ? heights[index] : 0
            _ = actionUIWinUIElementArrange(item.object.pointer,
                                            ActionUIWinUIRect(x: item.horizontal, y: y + item.vertical,
                                                              width: max(size.width - 2 * item.horizontal, 0), height: height))
            y += height + 2 * item.vertical
        }
    }
}

/// A diff row: the old and new line numbers right-aligned in 34-point columns with 4 points after each, the marker
/// centered in 14 points, and the line in the rest, wrapping; all at the top, with a point above and below, as the
/// GTK view's row.
@MainActor
final class DiffRowLayout: DiffPanelLayout {
    static let numberWidth = 34.0
    static let numberGap = 4.0
    static let markerWidth = 14.0
    static let padding = 1.0

    /// Where the line starts, after numbers measured `oldWidth` and `newWidth` wide.
    static func textX(oldWidth: Double, newWidth: Double) -> Double {
        max(numberWidth, oldWidth) + max(numberWidth, newWidth) + 2 * numberGap + markerWidth
    }

    let oldNumber: ShimObject
    let newNumber: ShimObject
    let marker: ShimObject
    let text: ShimObject
    private var sizes: [ActionUIWinUISize] = []

    init(oldNumber: ShimObject, newNumber: ShimObject, marker: ShimObject, text: ShimObject) {
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.marker = marker
        self.text = text
    }

    var cells: [ShimObject] { [oldNumber, newNumber, marker, text] }

    func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let unbounded = ActionUIWinUISize(width: .infinity, height: .infinity)
        let oldSize = actionUIWinUIElementMeasure(oldNumber.pointer, unbounded)
        let newSize = actionUIWinUIElementMeasure(newNumber.pointer, unbounded)
        let markerSize = actionUIWinUIElementMeasure(marker.pointer, unbounded)
        // The line is measured for the width arrange gives it, after numbers wider than their columns too.
        let textX = Self.textX(oldWidth: oldSize.width, newWidth: newSize.width)
        let textOffer = ActionUIWinUISize(width: available.width.isFinite ? max(available.width - textX, 0) : .infinity,
                                          height: .infinity)
        sizes = [oldSize, newSize, markerSize, actionUIWinUIElementMeasure(text.pointer, textOffer)]
        let height = sizes.map(\.height).max() ?? 0
        let width = available.width.isFinite ? available.width : textX + sizes[3].width
        return ActionUIWinUISize(width: width, height: height + 2 * Self.padding)
    }

    func arrange(_ size: ActionUIWinUISize) {
        guard sizes.count == 4 else { return }
        // A number wider than its column (five digits and more) takes the width it needs, as a GTK label does.
        let oldWidth = max(Self.numberWidth, sizes[0].width)
        let newWidth = max(Self.numberWidth, sizes[1].width)
        let frames = [
            ActionUIWinUIRect(x: 0, y: Self.padding, width: oldWidth, height: sizes[0].height),
            ActionUIWinUIRect(x: oldWidth + Self.numberGap, y: Self.padding, width: newWidth, height: sizes[1].height),
            ActionUIWinUIRect(x: oldWidth + newWidth + 2 * Self.numberGap, y: Self.padding, width: Self.markerWidth,
                              height: sizes[2].height),
        ]
        let textX = Self.textX(oldWidth: sizes[0].width, newWidth: sizes[1].width)
        for (cell, frame) in zip(cells, frames + [ActionUIWinUIRect(x: textX, y: Self.padding, width: max(size.width - textX, 0),
                                                                     height: sizes[3].height)]) {
            _ = actionUIWinUIElementArrange(cell.pointer, frame)
        }
    }
}

// MARK: - The element's state

/// What an element instance keeps (RenderNode.state): the rounded box, its column, and what the column shows.
@MainActor
final class DiffElementState {
    /// What the column shows: a diff, or the note for files that cannot be read.
    enum Shown: Equatable {
        case diff(oldText: String, newText: String, contextLines: Int, maxRenderedLines: Int)
        case unreadable([String])
    }

    static let monospaceFamily = "Cascadia Mono, Consolas"
    /// The WinUI renderer's caption and caption2 size.
    static let captionSize = 12.0
    /// The WinUI renderer's Color.red and Color.green (SwiftUI's), at 12 percent.
    static let removedTint = ActionUIWinUIColor(red: 255.0 / 255, green: 59.0 / 255, blue: 48.0 / 255, alpha: 0.12)
    static let addedTint = ActionUIWinUIColor(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 0.12)

    let box: ShimObject
    private let columnPanel: ShimObject
    private let column: DiffColumnLayout
    private var shown: Shown?

    init?(logger: any ActionUILogger) {
        let column = DiffColumnLayout()
        guard let panel = makePanel(column) else {
            logger.log("Diff: making its column failed: \(lastShimError())", .error)
            return nil
        }
        guard let box = ShimObject(adopting: actionUIWinUIRoundedBoxCreate(panel.pointer)) else {
            logger.log("Diff: making its box failed: \(lastShimError())", .error)
            return nil
        }
        self.column = column
        columnPanel = panel
        self.box = box
        _ = actionUIWinUIRoundedBoxSetCornerRadius(box.pointer, 6)
        paintBackground()
        // Theme brushes are taken when an object is made: a new theme builds everything again.
        let context = Unmanaged.passRetained(WeakDiffState(self)).toOpaque()
        if !actionUIWinUIElementOnActualThemeChanged(box.pointer, diffThemeChanged, context, releaseWeakDiffState) {
            logger.log("Diff: following the theme failed: \(lastShimError())", .warning)
        }
    }

    /// Shows `what`; the same as shown changes nothing.
    func show(_ what: Shown) {
        guard what != shown else { return }
        shown = what
        rebuild()
    }

    /// Builds the column again, as the theme has it now.
    func themeChanged() {
        paintBackground()
        rebuild()
    }

    private func paintBackground() {
        _ = actionUIWinUIElementSetBrush(box.pointer, ActionUIWinUIBrushBackground, nil, "SubtleFillColorSecondaryBrush")
    }

    private func rebuild() {
        while actionUIWinUIPanelChildCount(columnPanel.pointer) > 0 {
            guard actionUIWinUIPanelRemoveChild(columnPanel.pointer, 0) else { break }
        }
        column.items = []
        switch shown {
        case .diff(let oldText, let newText, let contextLines, let maxRenderedLines):
            let result = DiffComputer.compute(oldText: oldText, newText: newText, context: contextLines)
            if result.exceedsSizeLimit {
                append(note(DiffPresentation.tooLargeNote), horizontal: 4, vertical: 4)
                append(label(DiffPresentation.fallbackText(newText), secondary: false, monospace: true, wraps: true),
                       horizontal: 6, vertical: 6)
            } else if result.isIdentical {
                append(note(DiffPresentation.identicalNote), horizontal: 4, vertical: 4)
            } else {
                appendHunks(result, maxRenderedLines: maxRenderedLines)
            }
        case .unreadable(let paths):
            // As the Linux element's note: secondary monospaced text, 6 points from the edges, not selectable.
            let text = paths.map { "Cannot read \($0)" }.joined(separator: "\n")
            let note = label(text, secondary: true, monospace: true, wraps: true)
            if let note {
                _ = actionUIWinUITextBlockSetSelectable(note.pointer, false)
            }
            append(note, horizontal: 6, vertical: 6)
        case nil:
            break
        }
        _ = actionUIWinUIElementInvalidateMeasure(columnPanel.pointer)
    }

    private func appendHunks(_ result: DiffResult, maxRenderedLines: Int) {
        let visible = DiffPresentation.visibleLines(of: result, limit: maxRenderedLines)
        for hunk in result.hunks.prefix(visible.hunkCount) {
            if hunk.skippedBefore > 0 {
                append(gap(hunk.skippedBefore), horizontal: 0, vertical: 2)
            }
            let isLastVisible = hunk.id == visible.hunkCount - 1
            for line in isLastVisible ? Array(hunk.lines.prefix(visible.linesInLastHunk)) : hunk.lines {
                append(row(line), horizontal: 0, vertical: 0)
            }
        }
        if visible.truncatedLineCount > 0 {
            append(note(DiffPresentation.truncatedNote(Self.grouped(visible.truncatedLineCount))), horizontal: 4, vertical: 4)
        } else if result.trailingSkippedLines > 0 {
            append(gap(result.trailingSkippedLines), horizontal: 0, vertical: 2)
        }
    }

    private func append(_ object: ShimObject?, horizontal: Double, vertical: Double) {
        guard let object else { return }
        guard actionUIWinUIPanelInsertChild(columnPanel.pointer, Int32(column.items.count), object.pointer) else {
            ActionUIModel.shared.logger.log("Diff: adding a row failed: \(lastShimError())", .error)
            return
        }
        column.items.append(DiffColumnLayout.Item(object: object, horizontal: horizontal, vertical: vertical))
    }

    // MARK: Rows

    /// The numbers, the marker and the line, on the line's tint.
    private func row(_ line: DiffLine) -> ShimObject? {
        let marker = label(DiffPresentation.marker(line.kind), secondary: true, monospace: true, wraps: false)
        // An empty line keeps one line's height, as the SwiftUI view's " " does.
        let text = label(line.text.isEmpty ? " " : line.text, secondary: false, monospace: true, wraps: true)
        guard let oldNumber = number(line.oldNumber), let newNumber = number(line.newNumber), let marker, let text else {
            return nil
        }
        _ = actionUIWinUITextBlockSetAlignment(marker.pointer, ActionUIWinUITextCenter)
        let layout = DiffRowLayout(oldNumber: oldNumber, newNumber: newNumber, marker: marker, text: text)
        guard let row = makePanel(layout) else {
            ActionUIModel.shared.logger.log("Diff: making a row failed: \(lastShimError())", .error)
            return nil
        }
        for (index, cell) in layout.cells.enumerated() {
            _ = actionUIWinUIPanelInsertChild(row.pointer, Int32(index), cell.pointer)
        }
        switch line.kind {
        case .context:
            break
        case .removed:
            var tint = Self.removedTint
            _ = actionUIWinUIElementSetBrush(row.pointer, ActionUIWinUIBrushBackground, &tint, nil)
        case .added:
            var tint = Self.addedTint
            _ = actionUIWinUIElementSetBrush(row.pointer, ActionUIWinUIBrushBackground, &tint, nil)
        }
        return row
    }

    /// A line number, right-aligned; nothing for the side a line is not on.
    private func number(_ value: Int?) -> ShimObject? {
        let number = label(value.map(String.init) ?? "", secondary: true, monospace: true, wraps: false)
        if let number {
            _ = actionUIWinUITextBlockSetAlignment(number.pointer, ActionUIWinUITextTrailing)
        }
        return number
    }

    /// "N unchanged lines", centered.
    private func gap(_ count: Int) -> ShimObject? {
        let gap = label(DiffPresentation.gap(count, Self.grouped(count)), secondary: true, monospace: false, wraps: false)
        if let gap {
            _ = actionUIWinUITextBlockSetAlignment(gap.pointer, ActionUIWinUITextCenter)
        }
        return gap
    }

    /// A note at the left.
    private func note(_ text: String) -> ShimObject? {
        label(text, secondary: true, monospace: false, wraps: true)
    }

    /// A selectable text block in the caption size; `secondary` in the theme's secondary text color.
    private func label(_ text: String, secondary: Bool, monospace: Bool, wraps: Bool) -> ShimObject? {
        guard let label = ShimObject(adopting: actionUIWinUITextBlockCreate()) else {
            ActionUIModel.shared.logger.log("Diff: making a text failed: \(lastShimError())", .error)
            return nil
        }
        _ = actionUIWinUITextBlockSetText(label.pointer, text)
        _ = actionUIWinUITextBlockSetSelectable(label.pointer, true)
        _ = actionUIWinUITextBlockSetWraps(label.pointer, wraps)
        _ = actionUIWinUIElementSetFont(label.pointer, monospace ? Self.monospaceFamily : nil, Self.captionSize, 0)
        if secondary {
            _ = actionUIWinUIElementSetBrush(label.pointer, ActionUIWinUIBrushForeground, nil, "TextFillColorSecondaryBrush")
        }
        return label
    }

    /// `count` with the user's digit grouping ("1,234" in English, "1 234" in French): Windows' number format for
    /// the user's locale, its fraction cut off at the locale's decimal separator; the plain digits when Windows
    /// gives none.
    static func grouped(_ count: Int) -> String {
        let digits = String(count)
        var buffer = [WCHAR](repeating: 0, count: 64)
        let written = digits.withCString(encodedAs: UTF16.self) { value in
            GetNumberFormatEx(nil, 0, value, nil, &buffer, Int32(buffer.count))
        }
        guard written > 1 else { return digits }
        var text = Array(buffer.prefix(Int(written) - 1))
        var separator = [WCHAR](repeating: 0, count: 8)
        let length = GetLocaleInfoEx(nil, LCTYPE(LOCALE_SDECIMAL), &separator, Int32(separator.count))
        if length > 1 {
            let mark = Array(separator.prefix(Int(length) - 1))
            var start = text.count - mark.count
            while start >= 0 {
                if Array(text[start..<start + mark.count]) == mark {
                    text = Array(text[..<start])
                    break
                }
                start -= 1
            }
        }
        return String(decoding: text, as: UTF16.self)
    }
}

/// The theme callback's context: the state, not kept alive by it.
@MainActor
private final class WeakDiffState {
    weak var state: DiffElementState?

    init(_ state: DiffElementState) {
        self.state = state
    }
}

private let diffThemeChanged: ActionUIWinUICallback = { context in
    let weak = context.map { Unmanaged<WeakDiffState>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        weak?.state?.themeChanged()
    }
}

private let releaseWeakDiffState: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<WeakDiffState>.fromOpaque(context).release()
}

// MARK: - The element

struct Diff: ActionUIWinUIElement {
    // Display-only element: no observable runtime value.
    static var valueType: Any.Type { Void.self }
    static var initialValue: (ViewModel) -> Any? { { model in model.value } }
    static var initialStates: (ViewModel) -> [String: Any] { { model in model.states } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeView(_ node: RenderNode) -> OpaquePointer? {
        guard let state = DiffElementState(logger: ActionUIModel.shared.logger) else { return nil }
        node.state = state
        // The node takes over a reference of its own; the state keeps its own.
        return actionUIWinUIRetain(state.box.pointer)
    }

    static func update(_ view: OpaquePointer, _ node: RenderNode) {
        guard let state = node.state as? DiffElementState else { return }
        let properties = node.properties
        let logger = ActionUIModel.shared.logger
        // The trust policy is asked about each file, as for the built-in Image's; DiffInput asks about the full
        // path Windows opens.
        let readsFile: (String) -> Bool = { node.readsLocalFile($0) }
        let oldInput = resolveInput(text: properties["oldText"], file: properties["oldFile"], side: "old", logger: logger, readsFile: readsFile)
        let newInput = resolveInput(text: properties["newText"], file: properties["newFile"], side: "new", logger: logger, readsFile: readsFile)

        // A file that could not be read is a note listing the path(s), not a diff against an empty side, which
        // would look like a whole file removed or added.
        var unreadablePaths: [String] = []
        if case .unreadable(let path) = oldInput {
            unreadablePaths.append(path)
        }
        if case .unreadable(let path) = newInput {
            unreadablePaths.append(path)
        }
        guard unreadablePaths.isEmpty, case .text(let oldText) = oldInput, case .text(let newText) = newInput else {
            state.show(.unreadable(unreadablePaths))
            return
        }

        let contextLines = intProperty(properties, key: "contextLines", default: 3, minimum: 0, logger: logger)
        let maxRenderedLines = intProperty(properties, key: "maxRenderedLines", default: 300, minimum: 1, logger: logger)
        state.show(.diff(oldText: oldText, newText: newText, contextLines: contextLines, maxRenderedLines: maxRenderedLines))
    }

    static func expansion(_ node: RenderNode) -> ActionUIExpansion {
        .horizontal
    }

    /// A row's line wraps, so a stack can make the element narrower, as a Text.
    static func compression(_ node: RenderNode) -> ActionUIExpansion {
        .horizontal
    }
}

#endif
