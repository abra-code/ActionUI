// Sources/Elements/LabeledContent+WinUI.swift
/*
 LabeledContent on WinUI: its title, then its children in a row, as macOS lays it out outside a Form
 (measured on macOS 27) and as the Linux renderer does: the title, 8 points, the children 8 points
 apart, all centered vertically. It is as large as that unless a child fills, which then takes the
 rest of the row. An empty title keeps its gap, as in SwiftUI (measured: the content starts at 8).

 Not yet: a Form's alignment of titles on the content's first baseline.
*/

import CWinUI

@MainActor
final class LabeledContentLayout {
    /// The gap between the title and the content.
    static let spacing = 8.0

    let panel: LayoutPanel
    let title: WinUIObject
    let content: StackLayout
    private var shownTitle: String?
    /// The title's and the content's sizes from the last measure pass, for arrange.
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)
    private var measuredContent = ActionUIWinUISize(width: 0, height: 0)

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a LabeledContent's title")
        }
        self.title = title
        content = try StackLayout(axis: .horizontal)
        try panel.append(title)
        try panel.append(content.panel.object)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    func setTitle(_ text: String) {
        guard text != shownTitle else { return }
        if !actionUIWinUITextBlockSetText(title.pointer, text) {
            ActionUIModel.shared.logger.log("LabeledContent: \(WinUIError.last("setting the title"))", .error)
            return
        }
        shownTitle = text
        panel.invalidateLayout()
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        // Unbounded: its one line, even when its stack probes the row's smallest height with nothing
        // offered (WinUI caps a desired size at the offer, which would lose the title's line).
        measuredTitle = title.measure(ActionUIWinUISize(width: .infinity, height: .infinity))
        let left = measuredTitle.width + Self.spacing
        let offer = ActionUIWinUISize(width: available.width.isFinite ? max(available.width - left, 0) : .infinity,
                                      height: available.height)
        measuredContent = content.panel.object.measureRequested(offer)
        return ActionUIWinUISize(width: left + measuredContent.width, height: max(measuredTitle.height, measuredContent.height))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let left = measuredTitle.width + Self.spacing
        title.arrange(ActionUIWinUIRect(x: 0, y: (finalSize.height - measuredTitle.height) / 2,
                                        width: measuredTitle.width, height: measuredTitle.height))
        content.panel.object.arrange(ActionUIWinUIRect(x: left, y: 0, width: max(finalSize.width - left, 0), height: finalSize.height))
    }
}

extension LabeledContent: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try LabeledContentLayout()
        node.state = layout
        return layout.panel.object
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? LabeledContentLayout else { return }
        layout.setTitle(Props(node.properties).title)
        node.applyTextAppearance(to: layout.title, what: "a LabeledContent's title")
        node.applyAccessibilityHidden(to: layout.title)
        StackViews.configure(layout.content, spacing: nil, alignment: .center)
        syncStackContent(node, layout.content)
    }
}
