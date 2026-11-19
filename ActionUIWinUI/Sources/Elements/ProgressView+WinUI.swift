// Sources/Elements/ProgressView+WinUI.swift
/*
 ProgressView on WinUI, in the forms macOS shows (measured on macOS 27), as on Linux, with Windows' own
 indicators:
 - a bar (ProgressBar) for a known progress, or for any progress with progressViewStyle "linear": as
   wide as it is offered, the title above it. Without a progress the bar moves, as SwiftUI's
   indeterminate linear bar does. It wants no width of its own.
 - a spinner (an indeterminate ProgressRing) for an unknown progress: 32 x 32, the title under it.
 - a ring (a ProgressRing filled to the progress) for a known progress with progressViewStyle
   "circular": 32 x 32, the title under it.
 The title is 4 from the indicator (an empty one still takes its line, as in SwiftUI); under a ring it is in the secondary color, as macOS draws it. The indicator changes when the progress becomes known or unknown
 (a host setting states["progress"]).

 - The progress is Core's ProgressView.determinateProgress: states["progress"], else the value, out of
   total (1.0 when not given); none, or more than the total, is an unknown progress.

 Not yet: a tap running actionID; an accessible name from the title; controlSize.
*/

import CWinUI

/// A ProgressView's layout: the indicator and its title, above it (a bar) or under it (a ring).
@MainActor final class ProgressLayout {
    static let spacing = 4.0

    enum Kind: Equatable {
        case bar, ring
    }

    let panel: LayoutPanel
    let title: WinUIObject
    private(set) var indicator: WinUIObject?
    private(set) var kind: Kind?
    private var shownTitle: String?
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)
    private var measuredIndicator = ActionUIWinUISize(width: 0, height: 0)

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a ProgressView's title")
        }
        self.title = title
        try panel.append(title)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows a `kind` indicator, making it when the kind changes; nil when it could not be made.
    func show(_ kind: Kind) -> WinUIObject? {
        if kind == self.kind, let indicator {
            return indicator
        }
        guard let made = WinUIObject(adopting: actionUIWinUIProgressCreate(kind == .bar ? ActionUIWinUIProgressBar : ActionUIWinUIProgressRing)) else {
            ActionUIModel.shared.logger.log("ProgressView: \(WinUIError.last("creating the indicator"))", .error)
            return nil
        }
        do {
            // Forgotten only once it is out of the panel: one that failed to go stays the indicator,
            // and a later update tries again (else a second one would be appended beside it).
            if indicator != nil {
                try panel.remove(at: 1)
                indicator = nil
                self.kind = nil
            }
            try panel.append(made)
        } catch {
            ActionUIModel.shared.logger.log("ProgressView: \(error)", .error)
            return nil
        }
        indicator = made
        self.kind = kind
        panel.invalidateLayout()
        return made
    }

    /// The title; nil: none (and no gap). An empty title still takes its line, as in SwiftUI (measured on
    /// macOS 27, as on Linux).
    func setTitle(_ text: String?) {
        if (text != nil) != hasTitle {
            hasTitle = text != nil
            panel.invalidateLayout()
        }
        let text = text ?? ""
        guard text != shownTitle else { return }
        if !actionUIWinUITextBlockSetText(title.pointer, text) {
            ActionUIModel.shared.logger.log("ProgressView: \(WinUIError.last("setting the title"))", .error)
            return
        }
        shownTitle = text
        panel.invalidateLayout()
    }

    private var hasTitle = false

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let titleSize = title.measure(available)
        measuredTitle = hasTitle ? titleSize : ActionUIWinUISize(width: 0, height: 0)
        let gap = hasTitle ? Self.spacing : 0
        guard let indicator else { return measuredTitle }
        let offer = ActionUIWinUISize(width: available.width,
                                      height: available.height.isFinite ? max(available.height - measuredTitle.height - gap, 0) : .infinity)
        measuredIndicator = indicator.measure(offer)
        switch kind {
        case .bar?:
            // As wide as offered, wanting none of its own (as SwiftUI's bar: 0 wide unoffered).
            let width = available.width.isFinite ? available.width : max(measuredTitle.width, 0)
            return ActionUIWinUISize(width: width, height: measuredTitle.height + gap + measuredIndicator.height)
        case .ring?, nil:
            return ActionUIWinUISize(width: max(measuredTitle.width, measuredIndicator.width),
                                     height: measuredIndicator.height + gap + measuredTitle.height)
        }
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let gap = hasTitle ? Self.spacing : 0
        switch kind {
        case .bar?:
            title.arrange(ActionUIWinUIRect(x: 0, y: 0, width: min(measuredTitle.width, finalSize.width), height: measuredTitle.height))
            indicator?.arrange(ActionUIWinUIRect(x: 0, y: measuredTitle.height + gap, width: finalSize.width, height: measuredIndicator.height))
        case .ring?, nil:
            // Centered on each other, the ring above its title.
            let ringX = (finalSize.width - measuredIndicator.width) / 2
            indicator?.arrange(ActionUIWinUIRect(x: ringX, y: 0, width: measuredIndicator.width, height: measuredIndicator.height))
            title.arrange(ActionUIWinUIRect(x: (finalSize.width - measuredTitle.width) / 2, y: measuredIndicator.height + gap,
                                            width: measuredTitle.width, height: measuredTitle.height))
        }
    }
}

extension ProgressView: ActionUIWinUIRenderer {
    static func expansion(_ node: RenderNode) -> Expansion {
        // The bar takes the width offered; the ring keeps its size.
        kind(node, Props(node.properties)) == .bar ? .horizontal : []
    }

    /// The indicator for the style and the progress (see the header).
    static func kind(_ node: RenderNode, _ props: Props) -> ProgressLayout.Kind {
        switch props.style {
        case .linear?: return .bar
        case .circular?: return .ring
        case .automatic?, nil: return determinateProgress(node.model, props) == nil ? .ring : .bar
        }
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let layout = try ProgressLayout()
        node.state = layout
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? ProgressLayout else { return }
        let props = Props(node.properties)
        let progress = determinateProgress(node.model, props)
        let kind = kind(node, props)
        layout.setTitle(props.title)
        let indicator = layout.show(kind)
        // A ring's title in the secondary color, as macOS draws it (measured), unless a foregroundStyle
        // is in effect; a bar's in the text color.
        var appearance = node.textAppearance
        if kind == .ring && appearance.foreground == nil {
            appearance.foreground = "secondary"
        }
        appearance.apply(to: layout.title, what: "a ProgressView's title")
        node.applyAccessibilityHidden(to: layout.title)
        guard let indicator else { return }
        node.applyAccessibilityHidden(to: indicator)
        if !actionUIWinUIProgressSet(indicator.pointer, progress != nil, progress?.value ?? 0, progress?.total ?? 1) {
            ActionUIModel.shared.logger.log("ProgressView: \(WinUIError.last("showing the progress"))", .error)
        }
    }
}
