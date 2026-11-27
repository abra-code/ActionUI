// Add-ons/ActionUIRichText/Sources/RichText+WinUIFindBar.swift
/*
 The RichText element's find bar on Windows ("showFindBar"), the counterpart of RichTextGtkFindBar in the RichText
 package's GTK view: a row above the text with a search box, the count ("3 of 12"), previous and next, a menu of
 the search options and a close button. It edits the element's RichTextWinUIFind (RichText+WinUIFind.swift) and
 shows what it holds; the element places it and handles the keys (RichText+WinUI.swift).

 Built from the shim's controls only: a TextBox, a TextBlock, borderless Buttons with symbols, and a DropDownButton
 whose menu has a check item per option. The field takes the width the other parts leave.
*/

#if os(Windows)

import ActionUI
import CWinUI
import FoundationEssentials
import RichText

@MainActor
final class RichTextWinUIFindBar {
    /// The room around the row's parts and between them, and the least width of the field.
    static let horizontalPadding = 10.0
    static let verticalPadding = 6.0
    static let spacing = 6.0
    static let fieldMinimumWidth = 160.0
    /// The side of the symbols on the buttons, a standard button's.
    static let iconSide = 16.0
    /// The bar's fill, the code card's: a band above the text.
    static let fillBrush = "SubtleFillColorSecondaryBrush"

    /// The row (a panel laid out here), and the field the reader types in.
    let panel: ShimObject
    let field: ShimObject
    private let count: ShimObject
    private let previousButton: ShimObject
    private let nextButton: ShimObject
    private let optionsButton: ShimObject
    private let closeButton: ShimObject
    private let icon: ShimObject?
    /// The options menu's check items, each with the option it turns over.
    private var optionItems: [(item: ShimObject, option: WritableKeyPath<RichTextSearchOptions, Bool>)] = []
    let find: RichTextWinUIFind
    /// The parts' sizes, as the last measure found them, in the row's order.
    private var desired: [ActionUIWinUISize] = []

    /// The options, in the GTK bar's order, with the menu's titles.
    private static let options: [(title: String, option: WritableKeyPath<RichTextSearchOptions, Bool>)] = [
        ("Match case", \.caseSensitive),
        ("Match diacritics", \.diacriticSensitive),
        ("Whole words", \.wholeWord),
        ("Regular expression", \.regularExpression),
    ]

    init?(find: RichTextWinUIFind) {
        self.find = find
        let context = Unmanaged.passRetained(WeakFindBar()).toOpaque()
        guard let panel = ShimObject(adopting: actionUIWinUIPanelCreate(measureFindBar, arrangeFindBar, context,
                                                                        releaseWeakFindBar)),
              let field = ShimObject(adopting: actionUIWinUITextBoxCreate()),
              let count = ShimObject(adopting: actionUIWinUITextBlockCreate()),
              let previousButton = Self.button(symbol: "chevron.up", fallback: "Previous", name: "Previous match"),
              let nextButton = Self.button(symbol: "chevron.down", fallback: "Next", name: "Next match"),
              let optionsButton = ShimObject(adopting: actionUIWinUIMenuButtonCreate()),
              let closeButton = Self.button(symbol: "xmark", fallback: "Close", name: "Close find") else {
            return nil
        }
        self.panel = panel
        self.field = field
        self.count = count
        self.previousButton = previousButton
        self.nextButton = nextButton
        self.optionsButton = optionsButton
        self.closeButton = closeButton
        icon = Self.symbol("magnifyingglass")
        Unmanaged<WeakFindBar>.fromOpaque(context).takeUnretainedValue().bar = self
        if let icon {
            _ = actionUIWinUIElementSetAccessibilityHidden(icon.pointer, true)
        }
        applyBrushes()

        _ = actionUIWinUITextBoxSetPlaceholder(field.pointer, "Find")
        _ = actionUIWinUIElementSetAccessibleName(field.pointer, "Find")

        _ = actionUIWinUIButtonSetStyle(optionsButton.pointer, ActionUIWinUIButtonStyleBorderless)
        if let more = Self.symbol("ellipsis") {
            _ = actionUIWinUIButtonSetContent(optionsButton.pointer, more.pointer)
        } else {
            _ = actionUIWinUIButtonSetTitle(optionsButton.pointer, "Options")
        }
        _ = actionUIWinUIElementSetToolTip(optionsButton.pointer, "Search options")
        _ = actionUIWinUIElementSetAccessibleName(optionsButton.pointer, "Search options")
        if let menu = ShimObject(adopting: actionUIWinUIMenuButtonCopyMenu(optionsButton.pointer)) {
            for (title, option) in Self.options {
                guard let item = ShimObject(adopting: actionUIWinUIMenuAppend(menu.pointer, ActionUIWinUIMenuItemToggle, title, true,
                                                                              find.options[keyPath: option], nil)) else { continue }
                let target = Unmanaged.passRetained(FindOptionTarget(find: find, option: option)).toOpaque()
                _ = actionUIWinUIMenuItemOnClick(item.pointer, findOptionChosen, target, releaseFindOptionTarget)
                optionItems.append((item, option))
            }
        }

        for (part, action) in [(previousButton, FindBarAction.previous), (nextButton, .next), (closeButton, .close)] {
            let target = Unmanaged.passRetained(FindBarTarget(bar: self, action: action)).toOpaque()
            _ = actionUIWinUIButtonOnClick(part.pointer, findBarClicked, target, releaseFindBarTarget)
        }
        let typed = Unmanaged.passRetained(FindBarTarget(bar: self, action: .typed)).toOpaque()
        _ = actionUIWinUITextBoxOnTextChanged(field.pointer, findBarClicked, typed, releaseFindBarTarget)

        for (index, part) in parts.enumerated() where !actionUIWinUIPanelInsertChild(panel.pointer, Int32(index), part.pointer) {
            ActionUIModel.shared.logger.log("RichText: placing a part of the find bar failed", .warning)
        }
        update()
    }

    /// The row's parts, from the left: the field is the one that takes the width left over.
    private var parts: [ShimObject] {
        (icon.map { [$0] } ?? []) + [field, count, previousButton, nextButton, optionsButton, closeButton]
    }

    /// Whether the keyboard focus is in the bar (its field or one of its buttons).
    var hasFocus: Bool {
        parts.contains { actionUIWinUIElementHasFocus($0.pointer) }
    }

    /// Moves the keyboard focus on from the part that has it, as Tab would.
    func giveUpFocus() {
        for part in parts where actionUIWinUIElementHasFocus(part.pointer) {
            _ = actionUIWinUIElementGiveUpFocus(part.pointer)
        }
    }

    /// The theme brushes of the fill, the icon and the count. A theme brush is the theme's at the time it is set: the
    /// element sets them again when the theme changes.
    func applyBrushes() {
        _ = actionUIWinUIElementSetBrush(panel.pointer, ActionUIWinUIBrushBackground, nil, Self.fillBrush)
        if let icon {
            _ = actionUIWinUIElementSetBrush(icon.pointer, ActionUIWinUIBrushForeground, nil, RichTextWinUIState.secondaryBrush)
        }
        _ = actionUIWinUIElementSetBrush(count.pointer, ActionUIWinUIBrushForeground, nil, RichTextWinUIState.secondaryBrush)
    }

    /// Shows what the find holds: the query, the count, whether there is a match to step to, the options.
    func update() {
        if let copied = actionUIWinUITextBoxCopyText(field.pointer) {
            let current = String(cString: copied)
            actionUIWinUIFreeString(copied)
            // Only when it differs: setting the text moves the caret, and the reader may be typing.
            if current != find.query {
                _ = actionUIWinUITextBoxSetText(field.pointer, find.query)
            }
        }
        _ = actionUIWinUITextBlockSetText(count.pointer, find.summary)
        // As on Apple platforms and Linux, stepping is off without matches.
        _ = actionUIWinUIElementSetEnabled(previousButton.pointer, !find.ranges.isEmpty)
        _ = actionUIWinUIElementSetEnabled(nextButton.pointer, !find.ranges.isEmpty)
        for (item, option) in optionItems {
            _ = actionUIWinUIMenuItemSetChecked(item.pointer, find.options[keyPath: option])
        }
    }

    // MARK: - Layout

    /// The parts at their own sizes, the field at the width they leave; the row as wide as the parts and the field's
    /// least width, as tall as its tallest part.
    fileprivate func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let parts = self.parts
        let unbounded = ActionUIWinUISize(width: .infinity, height: .infinity)
        desired = parts.map { $0 === field ? ActionUIWinUISize(width: 0, height: 0) : actionUIWinUIElementMeasure($0.pointer, unbounded) }
        let fixed = fixedWidth
        let fieldWidth = available.width.isFinite ? max(Self.fieldMinimumWidth, available.width - fixed) : Self.fieldMinimumWidth
        if let index = parts.firstIndex(where: { $0 === field }) {
            desired[index] = actionUIWinUIElementMeasure(field.pointer, ActionUIWinUISize(width: fieldWidth, height: .infinity))
            desired[index].width = fieldWidth
        }
        let height = (desired.map(\.height).max() ?? 0) + 2 * Self.verticalPadding
        return ActionUIWinUISize(width: fixed + Self.fieldMinimumWidth, height: height)
    }

    /// From the left, each part centered in the row's height; the field takes what the others leave.
    fileprivate func arrange(_ size: ActionUIWinUISize) {
        let parts = self.parts
        guard desired.count == parts.count else { return }
        let fieldWidth = max(Self.fieldMinimumWidth, size.width - fixedWidth)
        var x = Self.horizontalPadding
        for (part, wanted) in zip(parts, desired) {
            let width = part === field ? fieldWidth : wanted.width
            let height = part === field ? min(wanted.height, size.height) : wanted.height
            let y = max(0, (size.height - height) / 2)
            _ = actionUIWinUIElementArrange(part.pointer, ActionUIWinUIRect(x: x, y: y, width: width, height: height))
            x += width + Self.spacing
        }
    }

    /// The width of everything but the field: the padding, the other parts and the room between all of them.
    private var fixedWidth: Double {
        let parts = self.parts
        let others = zip(parts, desired).filter { $0.0 !== field }.map { $0.1.width }.reduce(0, +)
        return 2 * Self.horizontalPadding + others + Self.spacing * Double(max(0, parts.count - 1))
    }

    // MARK: - Parts

    private static func symbol(_ name: String) -> ShimObject? {
        guard actionUIWinUISymbolExists(name), let symbol = ShimObject(adopting: actionUIWinUISymbolCreate(name)) else { return nil }
        _ = actionUIWinUISymbolSetSize(symbol.pointer, iconSide)
        return symbol
    }

    /// A borderless button showing the symbol `symbol` (its title `fallback` when the shim has no such symbol), named
    /// `name` for accessibility tools and in its tooltip.
    private static func button(symbol: String, fallback: String, name: String) -> ShimObject? {
        guard let button = ShimObject(adopting: actionUIWinUIButtonCreate()) else { return nil }
        _ = actionUIWinUIButtonSetStyle(button.pointer, ActionUIWinUIButtonStyleBorderless)
        if let icon = Self.symbol(symbol) {
            _ = actionUIWinUIButtonSetContent(button.pointer, icon.pointer)
        } else {
            _ = actionUIWinUIButtonSetTitle(button.pointer, fallback)
        }
        _ = actionUIWinUIElementSetToolTip(button.pointer, name)
        _ = actionUIWinUIElementSetAccessibleName(button.pointer, name)
        return button
    }
}

// MARK: - Callbacks

/// What a part of the bar does: step, close, or take the field's text as the query.
private enum FindBarAction {
    case previous
    case next
    case close
    case typed
}

/// A button's or the field's context: the bar, which it does not keep alive (a part's handler lives as long as the
/// part, which the bar holds), and what to do.
@MainActor
private final class FindBarTarget {
    weak var bar: RichTextWinUIFindBar?
    let action: FindBarAction

    init(bar: RichTextWinUIFindBar, action: FindBarAction) {
        self.bar = bar
        self.action = action
    }

    func run() {
        guard let bar else { return }
        let find = bar.find
        switch action {
        case .previous: find.previous()
        case .next: find.next()
        case .close: find.dismiss()
        case .typed:
            // Also after the bar set the text itself (WinUI reports both): the same text changes nothing.
            guard let copied = actionUIWinUITextBoxCopyText(bar.field.pointer) else { return }
            let text = String(cString: copied)
            actionUIWinUIFreeString(copied)
            if text != find.query {
                find.query = text
            }
        }
    }
}

/// An option's check item: WinUI has turned it over, and the option follows.
@MainActor
private final class FindOptionTarget {
    weak var find: RichTextWinUIFind?
    let option: WritableKeyPath<RichTextSearchOptions, Bool>

    init(find: RichTextWinUIFind, option: WritableKeyPath<RichTextSearchOptions, Bool>) {
        self.find = find
        self.option = option
    }
}

/// The row's layout context: the bar, not kept alive by it (the element's state keeps the bar).
@MainActor
private final class WeakFindBar {
    weak var bar: RichTextWinUIFindBar?
}

private let measureFindBar: ActionUIWinUIMeasureCallback = { context, _, available in
    let weak = context.map { Unmanaged<WeakFindBar>.fromOpaque($0).takeUnretainedValue() }
    return MainActor.assumeIsolated {
        guard let size = weak?.bar?.measure(available) else { return ActionUIWinUISize(width: 0, height: 0) }
        // WinUI gets no more than it offered.
        return ActionUIWinUISize(width: min(size.width, available.width), height: min(size.height, available.height))
    }
}

private let arrangeFindBar: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let weak = context.map { Unmanaged<WeakFindBar>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        weak?.bar?.arrange(finalSize)
    }
}

private let releaseWeakFindBar: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<WeakFindBar>.fromOpaque(context).release()
}

private let findBarClicked: ActionUIWinUICallback = { context in
    let target = context.map { Unmanaged<FindBarTarget>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        target?.run()
    }
}

private let releaseFindBarTarget: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<FindBarTarget>.fromOpaque(context).release()
}

private let findOptionChosen: ActionUIWinUICallback = { context in
    let target = context.map { Unmanaged<FindOptionTarget>.fromOpaque($0).takeUnretainedValue() }
    MainActor.assumeIsolated {
        guard let target, let find = target.find else { return }
        find.options[keyPath: target.option].toggle()
    }
}

private let releaseFindOptionTarget: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<FindOptionTarget>.fromOpaque(context).release()
}

#endif
