// Sources/Layout/ControlRow.swift
// Two controls in a row, as DatePicker's day and time and Stepper's buttons are shown.

import CWinUI

/// Two controls side by side, `spacing` apart, centered on each other's middle, each at its own size.
@MainActor final class ControlRow {
    let panel: LayoutPanel
    let spacing: Double
    let first: WinUIObject
    let second: WinUIObject
    private var measuredFirst = ActionUIWinUISize(width: 0, height: 0)
    private var measuredSecond = ActionUIWinUISize(width: 0, height: 0)

    init(_ first: WinUIObject, _ second: WinUIObject, spacing: Double = 8) throws(WinUIError) {
        panel = try LayoutPanel()
        self.spacing = spacing
        self.first = first
        self.second = second
        try panel.append(first)
        try panel.append(second)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let unbounded = ActionUIWinUISize(width: .infinity, height: available.height)
        measuredFirst = first.measure(unbounded)
        measuredSecond = second.measure(unbounded)
        return ActionUIWinUISize(width: measuredFirst.width + spacing + measuredSecond.width,
                                 height: max(measuredFirst.height, measuredSecond.height))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        first.arrange(ActionUIWinUIRect(x: 0, y: (finalSize.height - measuredFirst.height) / 2,
                                        width: measuredFirst.width, height: measuredFirst.height))
        second.arrange(ActionUIWinUIRect(x: measuredFirst.width + spacing, y: (finalSize.height - measuredSecond.height) / 2,
                                         width: measuredSecond.width, height: measuredSecond.height))
    }
}
