// Sources/Elements/Gauge+WinUI.swift
/*
 Gauge on WinUI, in the form its style has on macOS (measured on macOS 27, as the Linux renderer
 follows it):
 - no style, and accessoryLinearCapacity: Windows' ProgressBar under the title (centered without a
   style, at the leading edge for capacity), as wide as it is offered, the title 4 above it.
 - accessoryLinear: a drawn bar with a dot at the value, as wide as it is offered, 8 points tall; its
   title is not shown, as on macOS.
 - accessoryCircular: a drawn open arc, its gap at the bottom, with a dot at the value and the title
   small (Caption, 12) in the gap; 58 x 58.
 - accessoryCircularCapacity: a drawn ring filled clockwise from the top, the title large (Subtitle,
   20 semibold) in the middle; 58 x 58.
 The drawn forms (the shim's gauge drawings) use the accent color, as WinUI's ProgressBar does.

 - The value is the value, else the value property (Gauge.initialValue), shown inside the range.

 Not yet: a change of style keeps the form made first (it is chosen when the element is made); the
 drawn forms keep the accent color of the theme they were made in (a later light or dark, or accent,
 change is not followed); a long
 title in a circular form is clipped, where SwiftUI cuts it with an ellipsis; an accessible name and
 value (a meter with the title as its name); controlSize.
*/

import CWinUI

/// A Gauge's layout: its indicator (a ProgressBar or a drawing) and its title.
@MainActor final class GaugeLayout {
    enum Kind {
        case levelBar, linear, circular, circularCapacity
    }

    static let titleSpacing = 4.0
    static let circularSide = 58.0
    static let linearHeight = 8.0

    let kind: Kind
    let panel: LayoutPanel
    let indicator: WinUIObject
    /// Nil for the drawn bar, which shows none.
    let title: WinUIObject?
    var shownTitle: String?
    var hasTitle = false
    /// The title centered over a level bar (no style), else at its leading edge.
    var centersTitle = true
    var fraction: Double?
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)
    private var measuredIndicator = ActionUIWinUISize(width: 0, height: 0)

    init(_ kind: Kind) throws(WinUIError) {
        self.kind = kind
        panel = try LayoutPanel()
        let made: WinUIObject?
        switch kind {
        case .levelBar: made = WinUIObject(adopting: actionUIWinUIProgressCreate(ActionUIWinUIProgressBar))
        case .linear: made = WinUIObject(adopting: actionUIWinUIGaugeDrawingCreate(ActionUIWinUIGaugeBar))
        case .circular: made = WinUIObject(adopting: actionUIWinUIGaugeDrawingCreate(ActionUIWinUIGaugeArc))
        case .circularCapacity: made = WinUIObject(adopting: actionUIWinUIGaugeDrawingCreate(ActionUIWinUIGaugeRing))
        }
        guard let made else {
            throw WinUIError.last("creating a Gauge's indicator")
        }
        indicator = made
        try panel.append(made)
        if kind == .linear {
            title = nil
        } else {
            guard let text = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
                throw WinUIError.last("creating a Gauge's title")
            }
            title = text
            try panel.append(text)
        }
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let titleSize = title?.measure(ActionUIWinUISize(width: .infinity, height: .infinity)) ?? ActionUIWinUISize(width: 0, height: 0)
        measuredTitle = hasTitle ? titleSize : ActionUIWinUISize(width: 0, height: 0)
        switch kind {
        case .levelBar:
            measuredIndicator = indicator.measure(available)
            let gap = hasTitle ? Self.titleSpacing : 0
            let width = available.width.isFinite ? available.width : measuredTitle.width
            return ActionUIWinUISize(width: width, height: measuredTitle.height + gap + measuredIndicator.height)
        case .linear:
            _ = indicator.measure(available)
            return ActionUIWinUISize(width: available.width.isFinite ? available.width : 0, height: Self.linearHeight)
        case .circular, .circularCapacity:
            let side = ActionUIWinUISize(width: Self.circularSide, height: Self.circularSide)
            measuredIndicator = indicator.measure(side)
            return side
        }
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        switch kind {
        case .levelBar:
            let gap = hasTitle ? Self.titleSpacing : 0
            let titleWidth = min(measuredTitle.width, finalSize.width)
            let titleX = centersTitle ? (finalSize.width - titleWidth) / 2 : 0
            title?.arrange(ActionUIWinUIRect(x: titleX, y: 0, width: titleWidth, height: measuredTitle.height))
            indicator.arrange(ActionUIWinUIRect(x: 0, y: measuredTitle.height + gap, width: finalSize.width,
                                                height: measuredIndicator.height))
        case .linear:
            indicator.arrange(ActionUIWinUIRect(x: 0, y: (finalSize.height - Self.linearHeight) / 2, width: finalSize.width,
                                                height: Self.linearHeight))
        case .circular, .circularCapacity:
            let side = Self.circularSide
            let x = (finalSize.width - side) / 2
            let y = (finalSize.height - side) / 2
            indicator.arrange(ActionUIWinUIRect(x: x, y: y, width: side, height: side))
            // The title within the ring (clipped to it): in the arc's gap at the bottom, or in the middle.
            let titleWidth = min(measuredTitle.width, side)
            let titleY = kind == .circular ? y + side - measuredTitle.height : y + (side - measuredTitle.height) / 2
            title?.arrange(ActionUIWinUIRect(x: x + (side - titleWidth) / 2, y: titleY, width: titleWidth, height: measuredTitle.height))
        }
    }
}

extension Gauge: ActionUIWinUIRenderer {
    static func kind(_ style: Props.Style?) -> GaugeLayout.Kind {
        switch style {
        case nil, .accessoryLinearCapacity?: return .levelBar
        case .accessoryLinear?: return .linear
        case .accessoryCircular?: return .circular
        case .accessoryCircularCapacity?: return .circularCapacity
        }
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        switch (node.state as? GaugeLayout)?.kind ?? kind(Props(node.properties).style) {
        case .levelBar, .linear: return .horizontal
        case .circular, .circularCapacity: return []
        }
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        // Chosen at creation, untracked (see the header).
        let style = UntrackedReads.perform { Props(node.properties).style }
        let layout = try GaugeLayout(kind(style))
        node.state = layout
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let layout = node.state as? GaugeLayout else { return }
        let props = Props(node.properties)
        let value = Gauge.initialValue(node.model) as? Double ?? props.initialValue
        // Not a number (a host can set one): the minimum.
        let shown = value.isNaN ? props.min : Swift.min(Swift.max(value, props.min), props.max)
        let span = props.max - props.min
        let fraction = span > 0 ? (shown - props.min) / span : 0
        var ok = true
        if let title = layout.title {
            let text = props.title ?? ""
            if text != layout.shownTitle {
                ok = actionUIWinUITextBlockSetText(title.pointer, text)
                layout.shownTitle = ok ? text : nil
                layout.panel.invalidateLayout()
            }
            let hasTitle = props.title != nil
            let centers = props.style == nil
            if hasTitle != layout.hasTitle || centers != layout.centersTitle {
                layout.hasTitle = hasTitle
                layout.centersTitle = centers
                layout.panel.invalidateLayout()
            }
            // The circular forms' own sizes (Caption 12; Subtitle 20 semibold) in the text color in
            // effect, the level bar's the inherited text's.
            switch layout.kind {
            case .circular, .circularCapacity:
                let (size, weight): (Double, Int32) = layout.kind == .circular ? (12, 0) : (20, 600)
                ok = actionUIWinUIElementSetFont(title.pointer, nil, size, weight) && ok
                Paint.apply(Paint.parse(node.textAppearance.foreground, role: .foreground), ActionUIWinUIBrushForeground,
                            to: title, what: "a Gauge's title")
            case .levelBar, .linear:
                node.textAppearance.apply(to: title, what: "a Gauge's title")
            }
            node.applyAccessibilityHidden(to: title)
        }
        node.applyAccessibilityHidden(to: layout.indicator)
        if fraction != layout.fraction {
            let set: Bool
            switch layout.kind {
            case .levelBar:
                set = actionUIWinUIProgressSet(layout.indicator.pointer, true, fraction, 1)
            case .linear, .circular, .circularCapacity:
                set = actionUIWinUIGaugeDrawingSetFraction(layout.indicator.pointer, fraction)
            }
            layout.fraction = set ? fraction : nil
            ok = ok && set
        }
        if !ok {
            ActionUIModel.shared.logger.log("Gauge: \(WinUIError.last("showing a Gauge"))", .error)
        }
    }
}
