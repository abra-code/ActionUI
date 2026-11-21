// Sources/Elements/GroupBox+WinUI.swift
/*
 GroupBox on WinUI: its children in a card, under its title when it has one, as macOS puts a
 GroupBox's title above its box and as the Linux renderer does. The card is Windows 11's (the theme's
 card fill and stroke, rounded by the control corner radius, as Settings and Expander draw theirs);
 the layout is SwiftUI's, measured on macOS 27: the content inset 5 points on every side, the children
 centered and 8 points apart (none next to a Spacer), the box as large as its children unless one of
 them fills. The title is the body font in semibold (Fluent's Body Strong, a section header's style)
 unless the element or an ancestor sets a font (as SwiftUI's environment font reaches the title), 4
 points above the card.

 The content is the children, or one template instance per content row (TemplateRows).
*/

import CWinUI

@MainActor
final class GroupBoxLayout {
    /// The content's inset on every side, measured on macOS 27.
    static let contentPadding = 5.0
    /// The gap between the title and the card.
    static let titleSpacing = 4.0
    /// WinUI's ControlCornerRadius, which its cards use.
    static let cornerRadius = 4.0

    let panel: LayoutPanel
    let title: WinUIObject
    let card: WinUIObject
    let content: StackLayout
    private(set) var hasTitle = false
    private var shownTitle: String?
    /// The title's and the content's sizes from the last measure pass, for arrange.
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)
    private var measuredContent = ActionUIWinUISize(width: 0, height: 0)

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        guard let card = WinUIObject(adopting: actionUIWinUIShapeCreate(ActionUIWinUIShapeRoundedRectangle)) else {
            throw WinUIError.last("creating a GroupBox's card")
        }
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a GroupBox's title")
        }
        self.card = card
        self.title = title
        content = try StackLayout(axis: .vertical)
        try panel.append(card)
        try panel.append(content.panel.object)
        try panel.append(title)
        Paint.apply(.theme("CardBackgroundFillColorDefaultBrush"), ActionUIWinUIBrushFill, to: card, what: "a GroupBox's card")
        Paint.apply(.theme("CardStrokeColorDefaultBrush"), ActionUIWinUIBrushStroke, to: card, what: "a GroupBox's card")
        if !actionUIWinUIShapeSetStrokeThickness(card.pointer, 1) || !actionUIWinUIShapeSetCornerRadius(card.pointer, Self.cornerRadius) {
            ActionUIModel.shared.logger.log("GroupBox: \(WinUIError.last("drawing the card"))", .error)
        }
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows `text` as the title (nil or empty: none).
    func setTitle(_ text: String?) {
        let text = text ?? ""
        guard text != shownTitle else { return }
        if !actionUIWinUITextBlockSetText(title.pointer, text) {
            ActionUIModel.shared.logger.log("GroupBox: \(WinUIError.last("setting the title"))", .error)
            return
        }
        shownTitle = text
        hasTitle = !text.isEmpty
        panel.invalidateLayout()
    }

    private var titleBlock: Double { hasTitle ? measuredTitle.height + Self.titleSpacing : 0 }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let inset = 2 * Self.contentPadding
        let titleSize = title.measure(ActionUIWinUISize(width: available.width, height: .infinity))
        measuredTitle = hasTitle ? titleSize : ActionUIWinUISize(width: 0, height: 0)
        let inner = ActionUIWinUISize(width: available.width.isFinite ? max(available.width - inset, 0) : .infinity,
                                      height: available.height.isFinite ? max(available.height - titleBlock - inset, 0) : .infinity)
        measuredContent = content.panel.object.measureRequested(inner)
        _ = card.measure(ActionUIWinUISize(width: 0, height: 0))
        return ActionUIWinUISize(width: max(measuredTitle.width, measuredContent.width + inset),
                                 height: titleBlock + measuredContent.height + inset)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let inset = 2 * Self.contentPadding
        let top = titleBlock
        title.arrange(ActionUIWinUIRect(x: 0, y: 0, width: measuredTitle.width, height: measuredTitle.height))
        let cardHeight = max(finalSize.height - top, 0)
        card.arrange(ActionUIWinUIRect(x: 0, y: top, width: finalSize.width, height: cardHeight))
        content.panel.object.arrange(ActionUIWinUIRect(x: Self.contentPadding, y: top + Self.contentPadding,
                                                       width: max(finalSize.width - inset, 0), height: max(cardHeight - inset, 0)))
    }
}

extension GroupBox: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try GroupBoxLayout()
        node.state = layout
        return layout.panel.object
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? GroupBoxLayout else { return }
        layout.setTitle(Props(node.properties).title)
        // The font in effect (the element's or an ancestor's), else Body Strong; its foregroundStyle,
        // else the inherited text color.
        let (family, size, weight) = TextAppearance.winUIFont(node.textAppearance.font)
        if !actionUIWinUIElementSetFont(layout.title.pointer, family, size, node.textAppearance.font == nil ? 600 : weight) {
            ActionUIModel.shared.logger.log("GroupBox: \(WinUIError.last("setting the title's font"))", .error)
        }
        Paint.apply(Paint.parse(node.textAppearance.foreground, role: .foreground, tint: node.textAppearance.tint), ActionUIWinUIBrushForeground,
                    to: layout.title, what: "a GroupBox's title")
        node.applyAccessibilityHidden(to: layout.title)
        StackViews.configure(layout.content, spacing: nil, alignment: .center)
        syncStackContent(node, layout.content)
    }
}
