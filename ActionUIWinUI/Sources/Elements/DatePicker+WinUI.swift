// Sources/Elements/DatePicker+WinUI.swift
/*
 DatePicker on WinUI: its title, 8, then Windows' own date and time controls (TitledControlLayout, as a
 Picker), as macOS and Linux put the title before the control:
 - a date (displayedComponents date, the default): a CalendarDatePicker, a field showing the day that
   opens a calendar; with the graphical style, a CalendarView, the month's calendar inline;
 - a time (hourAndMinute): a TimePicker, its hour and minute (and AM/PM as the locale has it) fields;
 - both (dateAndTime): the day's control, then the TimePicker, 8 apart.

 - The date is the value, else selectedDate, else now (DatePicker.initialValue). Picking a day keeps the
   time, and changing the time keeps the day, in the system's time zone, as on Linux.
 - "range" limits the days the field and the calendar offer; a time outside it (a pick on its first or
   last day) is moved to the nearest end, and the controls show the date kept, as SwiftUI's picker does
   not let one past its range. A value outside the range is shown at the nearest end without being
   changed (WinUI's field would move it and report that as a pick), and picks build on the date shown.
 - Picking runs Core's DatePicker.userSelected (the value, then valueChangeActionID). The controls also
   report the renderer's own changes: the day or time it set is remembered and its report skipped.
 - A day clicked off in the calendar (CalendarView lets the selected day be clicked again to clear it)
   shows the value's day again: a DatePicker always has a date.
 - labelsHidden hides the title. The title keeps its color when the DatePicker is disabled, as a Picker's.

 Not yet: a change of displayedComponents or of the graphical style keeps the controls made first (they
 are chosen when the element is made); the field's and the time's own formats follow Windows' locale
 settings, where macOS writes the date in numbers; a value more than a hundred years from today with
 no range is moved by WinUI's own limits and stored as a pick; an accessible name from the title; a title in a Form's
 label column; controlSize.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

/// A local calendar day.
struct LocalDay: Equatable {
    var year: Int
    var month: Int
    var day: Int
}

/// Two controls side by side, `spacing` apart, centered on each other's middle.
@MainActor final class ControlRow {
    static let spacing = 8.0

    let panel: LayoutPanel
    let first: WinUIObject
    let second: WinUIObject
    private var measuredFirst = ActionUIWinUISize(width: 0, height: 0)
    private var measuredSecond = ActionUIWinUISize(width: 0, height: 0)

    init(_ first: WinUIObject, _ second: WinUIObject) throws(WinUIError) {
        panel = try LayoutPanel()
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
        return ActionUIWinUISize(width: measuredFirst.width + Self.spacing + measuredSecond.width,
                                 height: max(measuredFirst.height, measuredSecond.height))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        first.arrange(ActionUIWinUIRect(x: 0, y: (finalSize.height - measuredFirst.height) / 2,
                                        width: measuredFirst.width, height: measuredFirst.height))
        second.arrange(ActionUIWinUIRect(x: measuredFirst.width + Self.spacing, y: (finalSize.height - measuredSecond.height) / 2,
                                         width: measuredSecond.width, height: measuredSecond.height))
    }
}

/// A DatePicker's layout, its controls and what they show.
@MainActor final class DatePickerState {
    let layout: TitledControlLayout
    /// The day's control (a field or a calendar) and the time's; one of them at least.
    let dayControl: WinUIObject?
    let timeControl: WinUIObject?
    /// Both, side by side, kept alive with the layout.
    let row: ControlRow?
    /// The day and time the renderer last showed or read: a change event reporting them is the renderer's
    /// own.
    var shownDay: LocalDay?
    var shownMinutes: Int?
    var shownRange: ClosedRange<Date>??
    var appliedAppearance: TextAppearance?

    init(layout: TitledControlLayout, dayControl: WinUIObject?, timeControl: WinUIObject?, row: ControlRow?) {
        self.layout = layout
        self.dayControl = dayControl
        self.timeControl = timeControl
        self.row = row
    }
}

extension DatePicker: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        // Chosen at creation, untracked (see the header).
        let props = UntrackedReads.perform { Props(node.properties) }
        let components = props.displayedComponents ?? .date
        var dayControl: WinUIObject?
        var timeControl: WinUIObject?
        if components != .hourAndMinute {
            let kind = props.displayStyle == .graphical ? ActionUIWinUIDateCalendar : ActionUIWinUIDateField
            guard let control = WinUIObject(adopting: actionUIWinUIDateControlCreate(kind)) else {
                throw WinUIError.last("creating a DatePicker's day control")
            }
            dayControl = control
        }
        if components != .date {
            guard let control = WinUIObject(adopting: actionUIWinUIDateControlCreate(ActionUIWinUIDateTime)) else {
                throw WinUIError.last("creating a DatePicker's time control")
            }
            timeControl = control
        }
        var row: ControlRow?
        let control: WinUIObject
        if let dayControl, let timeControl {
            let both = try ControlRow(dayControl, timeControl)
            row = both
            control = both.panel.object
        } else if let single = dayControl ?? timeControl {
            control = single
        } else {
            throw WinUIError.last("making a DatePicker's controls")
        }
        let layout = try TitledControlLayout(control: control)
        let state = DatePickerState(layout: layout, dayControl: dayControl, timeControl: timeControl, row: row)
        node.state = state
        if let dayControl {
            WinUIEvents.connect(dayControl, actionUIWinUIDateControlOnChanged, "a DatePicker's day") { [weak node, weak state, weak dayControl] in
                guard let node, let state, let dayControl, node.isAttached else { return }
                guard let day = shownDay(dayControl) else {
                    // Clicked off: the value's day is shown again. Also the renderer's own clearing
                    // before it selects a day, whose report of that day then matches shownDay.
                    SyncScheduler.shared.markDirty(node)
                    return
                }
                guard day != state.shownDay else { return }
                state.shownDay = day
                userPicked(node, day: day)
            }
        }
        if let timeControl {
            WinUIEvents.connect(timeControl, actionUIWinUIDateControlOnChanged, "a DatePicker's time") { [weak node, weak state, weak timeControl] in
                guard let node, let state, let timeControl, node.isAttached else { return }
                let minutes = Int(actionUIWinUIDateControlGetTime(timeControl.pointer))
                guard minutes >= 0, minutes != state.shownMinutes else { return }
                state.shownMinutes = minutes
                userPicked(node, minutes: minutes)
            }
        }
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? DatePickerState else { return }
        let layout = state.layout
        let props = Props(node.properties)
        layout.setTitle(props.title)
        layout.titleHidden = node.isLabelsHidden
        let controls = [state.dayControl, state.timeControl].compactMap { $0 }
        if state.appliedAppearance != node.textAppearance {
            state.appliedAppearance = node.textAppearance
            node.textAppearance.apply(to: layout.title, what: "a DatePicker's title")
            for control in controls {
                node.textAppearance.apply(to: control, what: "a DatePicker")
            }
        }
        node.applyAccessibilityHidden(to: layout.title)
        // The title keeps its color when disabled, as a Picker's; the controls are enabled here (the
        // view is the layout's panel, no Control).
        let enabled = !(node.isDisabled || node.isHidden)
        for control in controls {
            node.applyAccessibilityHidden(to: control)
            if !actionUIWinUIElementSetEnabled(control.pointer, enabled) {
                ActionUIModel.shared.logger.log("DatePicker: \(WinUIError.last("enabling a control"))", .error)
            }
        }
        let range = dateRange(props)
        if let dayControl = state.dayControl, state.shownRange != .some(range) {
            let start = range.map { localDay($0.lowerBound) }
            let end = range.map { localDay($0.upperBound) }
            let limited = actionUIWinUIDateControlSetRange(dayControl.pointer, range != nil,
                                                           Int32(start?.year ?? 0), Int32(start?.month ?? 0), Int32(start?.day ?? 0),
                                                           Int32(end?.year ?? 0), Int32(end?.month ?? 0), Int32(end?.day ?? 0))
            if limited {
                state.shownRange = .some(range)
            } else {
                ActionUIModel.shared.logger.log("DatePicker: \(WinUIError.last("limiting the days"))", .error)
            }
        }
        show(shownDate(node, props), state)
    }

    /// Makes the controls show `date`, remembering what they show as the renderer's own.
    private static func show(_ date: Date, _ state: DatePickerState) {
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let dayControl = state.dayControl {
            let day = LocalDay(year: local.year ?? 1, month: local.month ?? 1, day: local.day ?? 1)
            // Before the call, whose event can come at once; after it, what the control shows.
            state.shownDay = day
            if !actionUIWinUIDateControlSetDay(dayControl.pointer, Int32(day.year), Int32(day.month), Int32(day.day)) {
                ActionUIModel.shared.logger.log("DatePicker: \(WinUIError.last("showing the day"))", .error)
            }
            state.shownDay = shownDay(dayControl)
        }
        if let timeControl = state.timeControl {
            let minutes = (local.hour ?? 0) * 60 + (local.minute ?? 0)
            state.shownMinutes = minutes
            if !actionUIWinUIDateControlSetTime(timeControl.pointer, Int32(minutes)) {
                ActionUIModel.shared.logger.log("DatePicker: \(WinUIError.last("showing the time"))", .error)
            }
            let shown = Int(actionUIWinUIDateControlGetTime(timeControl.pointer))
            state.shownMinutes = shown >= 0 ? shown : nil
        }
    }

    /// The day a field or calendar shows; nil when none is picked.
    private static func shownDay(_ control: WinUIObject) -> LocalDay? {
        var year: Int32 = 0
        var month: Int32 = 0
        var day: Int32 = 0
        guard actionUIWinUIDateControlGetDay(control.pointer, &year, &month, &day) else { return nil }
        return LocalDay(year: Int(year), month: Int(month), day: Int(day))
    }

    private static func currentDate(_ node: RenderNode) -> Date {
        node.model.value as? Date ?? DatePicker.initialValue(node.model) as? Date ?? Date()
    }

    /// The date the controls show: the value kept in the range (see the header).
    private static func shownDate(_ node: RenderNode, _ props: Props) -> Date {
        clamped(currentDate(node), to: dateRange(props))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func localDay(_ date: Date) -> LocalDay {
        let local = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: local.year ?? 1, month: local.month ?? 1, day: local.day ?? 1)
    }

    /// The user picked a day: the value's time on that day.
    private static func userPicked(_ node: RenderNode, day: LocalDay) {
        var local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: shownDate(node, Props(node.properties)))
        local.year = day.year
        local.month = day.month
        local.day = day.day
        commit(node, calendar.date(from: local))
    }

    /// The user changed the time: that time on the value's day.
    private static func userPicked(_ node: RenderNode, minutes: Int) {
        var local = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shownDate(node, Props(node.properties)))
        local.hour = minutes / 60
        local.minute = minutes % 60
        local.second = 0
        commit(node, calendar.date(from: local))
    }

    /// Keeps `picked` in the range and stores it; when that moved it, or changed nothing (a time in a
    /// daylight saving gap composes the one it had), the controls still show the pick and are shown the
    /// value again.
    private static func commit(_ node: RenderNode, _ picked: Date?) {
        guard let picked else { return }
        let props = Props(node.properties)
        let kept = clamped(picked, to: dateRange(props))
        let before = currentDate(node)
        userSelected(kept, element: node.element, model: node.model, windowUUID: node.windowModel.windowUUID, props: props)
        if kept != picked || kept == before {
            SyncScheduler.shared.markDirty(node)
        }
    }
}
