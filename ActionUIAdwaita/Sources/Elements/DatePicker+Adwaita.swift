// Sources/Elements/DatePicker+Adwaita.swift
/*
 DatePicker on GTK: its title, then the date, as macOS shows it (measured on macOS 27):
 - the automatic, compact, field and stepperField styles: a button showing the date as the locale
   writes it in numbers (CLDR yMd, "7/16/2024" in en_US; jm for a time, "2:30 PM"; both for
   dateAndTime, "7/16/2024, 2:30 PM"; DateFormatting), which opens a popover with a GtkCalendar
   for the date and hour and minute fields for the time; macOS shows a field with arrows that opens
   a calendar;
 - the graphical style: the calendar inline, with the hour and minute fields below it for a time.
 - The date is the value, else selectedDate, else now (DatePicker.initialValue). Picking a day keeps
   the time, and changing the time keeps the day, in the system's time zone.
 - A pick outside "range" is moved to the nearest end (GtkCalendar has no limits), and the picker
   shows the date it keeps, as SwiftUI's picker does not let one past its range.
 - Picking runs Core's DatePicker.userSelected (the value, then valueChangeActionID); an update
   fires nothing.
 - As on macOS, the calendar's month and year arrows only show another month; a click on a day,
   or Space on the focused one, picks it, also the day whose number the calendar already shows
   selected (GtkCalendar reports a pick only when the number changes).
 - labelsHidden hides the title, which still names the control; in a Form the title ends at the
   label column, and an empty one stays, 0 wide (FormLayout), as for a Picker.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

/// The parts of a DatePicker's widget, attached to it.
@MainActor
final class DatePickerParts {
    var button: WidgetPointer?
    var calendar: WidgetPointer?
    var hour: WidgetPointer?
    var minute: WidgetPointer?
}

let datePickerPartsKey = "actionui-date-picker"

extension DatePicker: ActionUIAdwaitaRenderer {
    /// The gap between the title and the control (SwiftUI's default spacing).
    static let titleSpacing: Int32 = 8

    /// Even: a button with a popover; odd: the graphical style, inline. Halved: the displayed
    /// components, which decide the parts (a calendar, time fields), so a change rebuilds them.
    static func widgetKind(_ node: RenderNode) -> Int {
        let props = Props(node.properties)
        let components = Props.DisplayedComponents.allCases.firstIndex(of: props.displayedComponents ?? .date) ?? 0
        return components * 2 + (props.displayStyle == .graphical ? 1 : 0)
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let props = Props(node.properties)
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, titleSpacing)!
        // Left out of the accessibility tree: the control carries the title as its name.
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        gtk_label_set_xalign(opaque(title), 0)
        gtk_widget_set_valign(title, GTK_ALIGN_CENTER)
        gtk_box_append(typed(box), title)
        let parts = DatePickerParts()
        attach(parts, to: box, key: datePickerPartsKey)
        // A Form lines its title up with the other rows' (FormLayout).
        attach(LabeledRowMarker(.box), to: box, key: labeledRowMarkerKey)

        let content = makeContent(node, parts, props)
        if node.widgetKind % 2 == 1 {
            gtk_widget_set_valign(content, GTK_ALIGN_CENTER)
            gtk_box_append(typed(box), content)
        } else {
            let button = gtk_menu_button_new()!
            gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
            let popover = gtk_popover_new()!
            gtk_popover_set_child(typed(popover), content)
            gtk_menu_button_set_popover(OpaquePointer(button), popover)
            gtk_box_append(typed(box), button)
            parts.button = button
        }
        return box
    }

    /// The calendar for a date and the hour and minute fields for a time, in a column.
    private static func makeContent(_ node: RenderNode, _ parts: DatePickerParts, _ props: Props) -> WidgetPointer {
        let column = gtk_box_new(GTK_ORIENTATION_VERTICAL, titleSpacing)!
        let components = props.displayedComponents ?? .date
        if components != .hourAndMinute {
            let calendar = gtk_calendar_new()!
            let pickDay: @MainActor () -> Void = { [weak node] in
                guard let node, let picked = gtk_calendar_get_date(OpaquePointer(calendar)) else { return }
                defer { g_date_time_unref(picked) }
                userPicked(node, year: Int(g_date_time_get_year(picked)), month: Int(g_date_time_get_month(picked)),
                           day: Int(g_date_time_get_day_of_month(picked)))
            }
            connectUserSignal(calendar, "day-selected", .instanceOnly, pickDay)
            whenADayIsChosen(calendar, pickDay)
            gtk_box_append(typed(column), calendar)
            parts.calendar = calendar
        }
        if components != .date {
            let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4)!
            gtk_widget_set_halign(row, GTK_ALIGN_CENTER)
            let hour = timeField(range: 23, name: "Hour")
            let minute = timeField(range: 59, name: "Minute")
            gtk_box_append(typed(row), hour)
            gtk_box_append(typed(row), gtk_label_new(":"))
            gtk_box_append(typed(row), minute)
            for field in [hour, minute] {
                connectUserSignal(field, "value-changed", .instanceOnly) { [weak node] in
                    guard let node else { return }
                    userPicked(node, hour: Int(gtk_spin_button_get_value_as_int(OpaquePointer(hour))),
                               minute: Int(gtk_spin_button_get_value_as_int(OpaquePointer(minute))))
                }
            }
            gtk_box_append(typed(column), row)
            parts.hour = hour
            parts.minute = minute
        }
        return column
    }

    /// Runs `pick` when the user chooses a day in `calendar` whose number is already selected, which
    /// GtkCalendar does not report: "day-selected" comes only when the day's number changes, and
    /// its month and year arrows move the selection to the same day of another month without it,
    /// so that day could not be chosen. As on macOS, navigating alone picks nothing: a click on a
    /// day (its label, of the class day-number; the calendar selects on the press, so the release
    /// reads it) or Space on the focused day (the keys GtkCalendar selects it with).
    private static func whenADayIsChosen(_ calendar: WidgetPointer, _ pick: @escaping @MainActor () -> Void) {
        var days: [WidgetPointer] = []
        func collect(_ widget: WidgetPointer) {
            if gtk_widget_has_css_class(widget, "day-number") != 0 {
                days.append(widget)
            }
            var child = gtk_widget_get_first_child(widget)
            while let part = child {
                collect(part)
                child = gtk_widget_get_next_sibling(part)
            }
        }
        collect(calendar)
        for day in days {
            let click = gtk_gesture_click_new()!
            connectSignal(UnsafeMutableRawPointer(click), "released", .press, pick)
            gtk_widget_add_controller(day, click)
        }
        let keys = gtk_event_controller_key_new()!
        // Only keys sent to the calendar itself: Space on a focused month or year arrow (a child)
        // moves the month and its release would bubble here and pick the moved day.
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_TARGET)
        connectKeyReleased(UnsafeMutableRawPointer(keys)) { keyval in
            // GtkCalendar's Space chooses the focused day and does nothing before one is focused
            // (by a click or an arrow key); its label is then marked focused.
            guard keyval == guint(GDK_KEY_space) || keyval == guint(GDK_KEY_KP_Space),
                  days.contains(where: { (gtk_widget_get_state_flags($0).rawValue & GTK_STATE_FLAG_FOCUSED.rawValue) != 0 })
            else { return }
            pick()
        }
        gtk_widget_add_controller(calendar, keys)
    }

    /// A field for 0 through `range`, two digits wide, wrapping around.
    private static func timeField(range: Double, name: String) -> WidgetPointer {
        let field = gtk_spin_button_new_with_range(0, range, 1)!
        gtk_spin_button_set_wrap(OpaquePointer(field), 1)
        gtk_spin_button_set_numeric(OpaquePointer(field), 1)
        gtk_editable_set_width_chars(OpaquePointer(field), 2)
        setAccessibleLabel(field, name)
        return field
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let parts = attached(DatePickerParts.self, on: widget, key: datePickerPartsKey),
              let title = gtk_widget_get_first_child(widget) else { return }
        let props = Props(node.properties)
        if swiftString(gtk_label_get_text(opaque(title))) != props.title {
            gtk_label_set_text(opaque(title), props.title)
        }
        let showsTitle: gboolean = (!props.title.isEmpty || node.environment.inForm) && !node.environment.labelsHidden ? 1 : 0
        if gtk_widget_get_visible(title) != showsTitle {
            gtk_widget_set_visible(title, showsTitle)
        }
        show(currentDate(node), parts, props)
    }

    /// The control, which assistive technologies read (the box only holds it and the title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        guard let parts = attached(DatePickerParts.self, on: widget, key: datePickerPartsKey) else { return widget }
        return parts.button ?? parts.calendar ?? parts.hour ?? widget
    }

    /// Named after its title, also when labelsHidden hides it, as in SwiftUI.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// The CLDR skeleton macOS's DatePicker shows the date in (measured: numbers, not month names).
    static func skeleton(_ components: Props.DisplayedComponents?) -> String {
        switch components ?? .date {
        case .date: return "yMd"
        case .hourAndMinute: return "jm"
        case .dateAndTime: return "yMdjm"
        }
    }

    private static func currentDate(_ node: RenderNode) -> Date {
        node.model.value as? Date ?? DatePicker.initialValue(node.model) as? Date ?? Date()
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Makes the parts show `date`, setting only what differs.
    private static func show(_ date: Date, _ parts: DatePickerParts, _ props: Props) {
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let button = parts.button {
            let text = DateFormatting.string(date, skeleton: skeleton(props.displayedComponents))
            if swiftString(gtk_menu_button_get_label(OpaquePointer(button))) != text {
                gtk_menu_button_set_label(OpaquePointer(button), text)
            }
        }
        if let calendarWidget = parts.calendar, let year = local.year, let month = local.month, let day = local.day {
            let shown = OpaquePointer(calendarWidget)
            if Int(gtk_calendar_get_year(shown)) != year || Int(gtk_calendar_get_month(shown)) + 1 != month
                || Int(gtk_calendar_get_day(shown)) != day, let day = g_date_time_new_local(Int32(year), Int32(month), Int32(day), 0, 0, 0) {
                gtk_calendar_select_day(shown, day)
                g_date_time_unref(day)
            }
        }
        for (field, value) in [(parts.hour, local.hour), (parts.minute, local.minute)] {
            if let field, let value, Int(gtk_spin_button_get_value_as_int(OpaquePointer(field))) != value {
                gtk_spin_button_set_value(OpaquePointer(field), Double(value))
            }
        }
    }

    /// The user picked a day: the value's time on that day.
    private static func userPicked(_ node: RenderNode, year: Int, month: Int, day: Int) {
        var local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: currentDate(node))
        local.year = year
        local.month = month
        local.day = day
        commit(node, calendar.date(from: local))
    }

    /// The user changed the time: that time on the value's day.
    private static func userPicked(_ node: RenderNode, hour: Int, minute: Int) {
        var local = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: currentDate(node))
        local.hour = hour
        local.minute = minute
        local.second = 0
        commit(node, calendar.date(from: local))
    }

    /// Keeps `picked` in the range, stores it, and shows the kept date when it moved.
    private static func commit(_ node: RenderNode, _ picked: Date?) {
        guard let picked else { return }
        let props = Props(node.properties)
        let kept = clamped(picked, to: dateRange(props))
        let before = currentDate(node)
        userSelected(kept, element: node.element, model: node.model, windowUUID: node.windowUUID, props: props)
        // When the pick was moved into the range, or changed nothing (an hour in a daylight saving
        // gap composes the time it had), the calendar or a field still shows the pick: after the
        // signal, it is set back to the value.
        guard kept != picked || kept == before else { return }
        _ = runAfter(milliseconds: 0) { [weak node] in
            guard let node, node.isAttached,
                  let parts = attached(DatePickerParts.self, on: node.widget, key: datePickerPartsKey) else { return }
            UpdateGuard.applying { show(currentDate(node), parts, Props(node.properties)) }
        }
    }
}
