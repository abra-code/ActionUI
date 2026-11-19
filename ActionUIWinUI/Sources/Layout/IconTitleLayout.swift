// Sources/Layout/IconTitleLayout.swift
/*
 An icon beside a title, as SwiftUI's Label and a button's label lay them out and as the Linux
 renderer does: the icon (a symbol, ImageLayout.symbolSide square) and the title (one line of text)
 side by side, 8 apart, each at its own size, centered vertically; without a title the icon alone,
 without an icon the title alone. Label shows one; a Button with an image and a title holds one as its
 content, whose text and icon then take the button's text color.
*/

import CWinUI

@MainActor
final class IconTitleLayout {
    /// The gap between the icon and the title (SwiftUI's Label on macOS and the Linux renderer).
    static let spacing = 8.0

    let panel: LayoutPanel
    /// The title's TextBlock: always a child (WinUI arranges only children it measured).
    let title: WinUIObject
    private(set) var icon: WinUIObject?
    /// Whether the title has text (an empty one takes no room and no gap).
    private(set) var hasTitle = false
    private var shownTitle: String?
    /// The icon's side.
    private(set) var iconSide = 14.0 * ImageLayout.symbolFontFactor
    /// The side the icon's outline was last scaled to.
    private var appliedSide = -1.0
    /// The title's size from the last measure pass, for arrange.
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a label's title")
        }
        self.title = title
        try panel.append(title)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows `text` as the title (empty: none).
    func setTitle(_ text: String) {
        guard text != shownTitle else { return }
        if !actionUIWinUITextBlockSetText(title.pointer, text) {
            ActionUIModel.shared.logger.log("IconTitleLayout: \(WinUIError.last("setting a title"))", .error)
            return
        }
        shownTitle = text
        hasTitle = !text.isEmpty
        panel.invalidateLayout()
    }

    /// Shows `newIcon` before the title (nil: none), replacing the icon shown before.
    func setIcon(_ newIcon: WinUIObject?) {
        do {
            if icon != nil {
                try panel.remove(at: 0)
            }
            if let newIcon {
                try panel.insert(newIcon, at: 0)
            }
        } catch {
            ActionUIModel.shared.logger.log("IconTitleLayout: \(error)", .error)
        }
        icon = newIcon
        appliedSide = -1
        panel.invalidateLayout()
    }

    func setIconSide(_ side: Double) {
        guard side != iconSide else { return }
        iconSide = side
        panel.invalidateLayout()
    }

    private var iconWidth: Double { icon != nil ? iconSide : 0 }
    private var gap: Double { icon != nil && hasTitle ? Self.spacing : 0 }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        if let icon {
            if appliedSide != iconSide {
                appliedSide = iconSide
                if !actionUIWinUISymbolSetSize(icon.pointer, iconSide) {
                    ActionUIModel.shared.logger.log("IconTitleLayout: \(WinUIError.last("sizing a symbol"))", .error)
                }
            }
            _ = icon.measure(ActionUIWinUISize(width: iconSide, height: iconSide))
        }
        let titleWidth = available.width.isFinite ? max(available.width - iconWidth - gap, 0) : available.width
        let titleSize = title.measure(ActionUIWinUISize(width: titleWidth, height: available.height))
        measuredTitle = hasTitle ? titleSize : ActionUIWinUISize(width: 0, height: 0)
        return ActionUIWinUISize(width: iconWidth + gap + measuredTitle.width,
                                 height: max(icon != nil ? iconSide : 0, measuredTitle.height))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        if let icon {
            icon.arrange(ActionUIWinUIRect(x: 0, y: (finalSize.height - iconSide) / 2, width: iconSide, height: iconSide))
        }
        title.arrange(ActionUIWinUIRect(x: iconWidth + gap, y: (finalSize.height - measuredTitle.height) / 2,
                                        width: measuredTitle.width, height: measuredTitle.height))
    }
}
