// Tests/Elements/DatePickerRendererTests.swift
/*
 Tests for the DatePicker renderer on GTK: the title beside a button showing the date in numbers as
 the locale writes it (yMd, jm, yMdjm, as macOS shows them), whose popover holds a calendar and hour
 and minute fields; the graphical style shows the calendar inline. Picking a day keeps the time and
 changing the time keeps the day; a pick outside the range is kept at its nearest end; picking
 fires valueChangeActionID once, a host value nothing; the control is named after the title.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class DatePickerRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "datepicker-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.picked") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.picked")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func parts(_ node: RenderNode) throws -> DatePickerParts {
        try XCTUnwrap(attached(on: node.widget, key: datePickerPartsKey))
    }

    private var value: Date? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? Date
    }

    /// A local date and time.
    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func label(_ node: RenderNode) throws -> String? {
        swiftString(gtk_menu_button_get_label(OpaquePointer(try XCTUnwrap(try parts(node).button))))
    }

    private func select(_ calendar: WidgetPointer, _ year: Int32, _ month: Int32, _ day: Int32) {
        let date = g_date_time_new_local(year, month, day, 0, 0, 0)
        gtk_calendar_select_day(OpaquePointer(calendar), date)
        g_date_time_unref(date)
    }

    func testTheButtonShowsTheDateInNumbersAsMacOSDoes() throws {
        let date = try render(#"{"type": "DatePicker", "id": 1, "properties": {"title": "Start", "selectedDate": "2024-07-16"}}"#)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try XCTUnwrap(gtk_widget_get_first_child(date.widget))))), "Start")
        XCTAssertEqual(try label(date), DateFormatting.string(local(2024, 7, 16), skeleton: "yMd"))
        XCTAssertNotNil(try parts(date).calendar)
        XCTAssertNil(try parts(date).hour, "no time fields for a date")

        ActionUIModel.shared.windowModels[windowUUID] = nil
        let time = try render(#"{"type": "DatePicker", "id": 1, "properties": {"displayedComponents": "hourAndMinute", "selectedDate": "2024-07-16T14:30:00"}}"#)
        XCTAssertEqual(try label(time), DateFormatting.string(local(2024, 7, 16, 14, 30), skeleton: "jm"))
        XCTAssertNil(try parts(time).calendar, "no calendar for a time")
        XCTAssertEqual(gtk_spin_button_get_value_as_int(OpaquePointer(try XCTUnwrap(try parts(time).hour))), 14)
        XCTAssertEqual(gtk_spin_button_get_value_as_int(OpaquePointer(try XCTUnwrap(try parts(time).minute))), 30)

        ActionUIModel.shared.windowModels[windowUUID] = nil
        let both = try render(#"{"type": "DatePicker", "id": 1, "properties": {"displayedComponents": "dateAndTime", "selectedDate": "2024-07-16T14:30:00"}}"#)
        XCTAssertEqual(try label(both), DateFormatting.string(local(2024, 7, 16, 14, 30), skeleton: "yMdjm"))
    }

    func testPickingADayKeepsTheTimeAndFiresOnce() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"displayedComponents": "dateAndTime", "selectedDate": "2024-07-16T14:30:00", "valueChangeActionID": "test.picked"}}"#)
        select(try XCTUnwrap(try parts(node).calendar), 2024, 7, 20)
        XCTAssertEqual(value, local(2024, 7, 20, 14, 30))
        XCTAssertEqual(fired, ["test.picked"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try label(node), DateFormatting.string(local(2024, 7, 20, 14, 30), skeleton: "yMdjm"))
    }

    func testChangingTheTimeKeepsTheDay() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"displayedComponents": "dateAndTime", "selectedDate": "2024-07-16T14:30:00"}}"#)
        gtk_spin_button_set_value(OpaquePointer(try XCTUnwrap(try parts(node).hour)), 9)
        XCTAssertEqual(value, local(2024, 7, 16, 9, 30))
        gtk_spin_button_set_value(OpaquePointer(try XCTUnwrap(try parts(node).minute)), 5)
        XCTAssertEqual(value, local(2024, 7, 16, 9, 5))
    }

    func testAPickOutsideTheRangeIsKeptAtItsEnd() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"selectedDate": "2024-07-16", "range": {"start": "2024-07-01", "end": "2024-07-31"}}}"#)
        let calendar = try XCTUnwrap(try parts(node).calendar)
        // Core reads a day ("2024-07-31") as its noon, so the ends and the picks are at 12:00.
        select(calendar, 2024, 8, 5)
        XCTAssertEqual(value, local(2024, 7, 31, 12))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_calendar_get_month(OpaquePointer(calendar)), 6, "the calendar shows July again")
        XCTAssertEqual(gtk_calendar_get_day(OpaquePointer(calendar)), 31)
        select(calendar, 2024, 6, 1)
        XCTAssertEqual(value, local(2024, 7, 1, 12))
    }

    /// Emits `signal` on `instance` with `arguments`, each set into its GValue by its setter.
    private func emit(_ signal: String, on instance: UnsafeMutableRawPointer, _ arguments: [(GType, (UnsafeMutablePointer<GValue>) -> Void)]) {
        let type = instance.assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type
        let id = g_signal_lookup(signal, type)
        precondition(id != 0, "\(signal) is not a signal of this object")
        var values = [GValue](repeating: GValue(), count: arguments.count + 1)
        g_value_init(&values[0], type)
        g_value_set_object(&values[0], instance)
        for (index, argument) in arguments.enumerated() {
            g_value_init(&values[index + 1], argument.0)
            argument.1(&values[index + 1])
        }
        g_signal_emitv(&values, id, 0, nil)
        for index in values.indices {
            g_value_unset(&values[index])
        }
    }

    /// The controllers of `widget` of `type`.
    private func controllers(of widget: WidgetPointer, _ type: GType) -> [UnsafeMutableRawPointer] {
        let list = gtk_widget_observe_controllers(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(list)) }
        return (0..<g_list_model_get_n_items(list)).compactMap { index in
            guard let item = g_list_model_get_item(list, index) else { return nil }
            g_object_unref(item)
            return g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), type) != 0 ? item : nil
        }
    }

    /// The calendar's first day label (class day-number).
    private func dayLabel(in widget: WidgetPointer) -> WidgetPointer? {
        if gtk_widget_has_css_class(widget, "day-number") != 0 { return widget }
        var child = gtk_widget_get_first_child(widget)
        while let part = child {
            if let found = dayLabel(in: part) { return found }
            child = gtk_widget_get_next_sibling(part)
        }
        return nil
    }

    func testAfterNavigatingTheShownDayCanBeChosenAsOnMacOS() throws {
        // GtkCalendar reports a pick only when the day's number changes; its arrows move the
        // selection to the same day of another month without reporting it.
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"selectedDate": "2024-07-16", "valueChangeActionID": "test.picked"}}"#)
        let calendar = try XCTUnwrap(try parts(node).calendar)
        gtk_calendar_set_month(OpaquePointer(calendar), 5)
        XCTAssertEqual(value, local(2024, 7, 16, 12), "navigating picks nothing, as on macOS")
        XCTAssertTrue(fired.isEmpty)

        let day = try XCTUnwrap(dayLabel(in: calendar))
        let click = try XCTUnwrap(controllers(of: day, gtk_gesture_click_get_type()).first)
        emit("released", on: click, [(GType(6 << G_TYPE_FUNDAMENTAL_SHIFT), { g_value_set_int($0, 1) }),
                                     (GType(15 << G_TYPE_FUNDAMENTAL_SHIFT), { g_value_set_double($0, 0) }),
                                     (GType(15 << G_TYPE_FUNDAMENTAL_SHIFT), { g_value_set_double($0, 0) })])
        XCTAssertEqual(value, local(2024, 6, 16, 12), "a click on a day picks the shown day")
        XCTAssertEqual(fired, ["test.picked"])

        // GTK lists a widget's newest controller first: the picker's, after the calendar's own.
        let keys = try XCTUnwrap(controllers(of: calendar, gtk_event_controller_key_get_type()).first)
        func release(_ keyval: Int32) {
            emit("key-released", on: keys, [(GType(7 << G_TYPE_FUNDAMENTAL_SHIFT), { g_value_set_uint($0, guint(keyval)) }),
                                            (GType(7 << G_TYPE_FUNDAMENTAL_SHIFT), { g_value_set_uint($0, 0) }),
                                            (gdk_modifier_type_get_type(), { g_value_set_flags($0, 0) })])
        }
        gtk_calendar_set_month(OpaquePointer(calendar), 4)
        release(GDK_KEY_space)
        XCTAssertEqual(value, local(2024, 6, 16, 12), "Space before a day is focused chooses nothing, as in GtkCalendar")
        // The calendar's own key controller (the older one) focuses a day with an arrow key.
        let calendarKeys = try XCTUnwrap(controllers(of: calendar, gtk_event_controller_key_get_type()).last)
        XCTAssertNotEqual(calendarKeys, keys)
        var handled = GValue()
        g_value_init(&handled, GType(5 << G_TYPE_FUNDAMENTAL_SHIFT))
        var arguments = [GValue](repeating: GValue(), count: 4)
        g_value_init(&arguments[0], gtk_event_controller_key_get_type())
        g_value_set_object(&arguments[0], calendarKeys)
        g_value_init(&arguments[1], GType(7 << G_TYPE_FUNDAMENTAL_SHIFT))
        g_value_set_uint(&arguments[1], guint(GDK_KEY_Right))
        g_value_init(&arguments[2], GType(7 << G_TYPE_FUNDAMENTAL_SHIFT))
        g_value_init(&arguments[3], gdk_modifier_type_get_type())
        g_signal_emitv(&arguments, g_signal_lookup("key-pressed", gtk_event_controller_key_get_type()), 0, &handled)
        for index in arguments.indices { g_value_unset(&arguments[index]) }
        g_value_unset(&handled)
        release(GDK_KEY_Return)
        XCTAssertEqual(value, local(2024, 6, 16, 12), "Return does not choose a day in GtkCalendar")
        // GtkCalendar reports nothing when the focused day is the shown one; the picker's Space does.
        release(GDK_KEY_space)
        XCTAssertEqual(value, local(2024, 5, 16, 12), "Space chooses once a day is focused")
    }

    func testAHostValueShowsAndFiresNothing() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"selectedDate": "2024-07-16", "valueChangeActionID": "test.picked"}}"#)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: local(2025, 1, 2))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try label(node), DateFormatting.string(local(2025, 1, 2), skeleton: "yMd"))
        XCTAssertEqual(gtk_calendar_get_year(OpaquePointer(try XCTUnwrap(try parts(node).calendar))), 2025)
        XCTAssertTrue(fired.isEmpty)
    }

    func testTheGraphicalStyleShowsTheCalendarInline() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"title": "Day", "displayStyle": "graphical", "selectedDate": "2024-07-16"}}"#)
        let parts = try parts(node)
        XCTAssertNil(parts.button)
        let calendar = try XCTUnwrap(parts.calendar)
        XCTAssertNotEqual(gtk_widget_is_ancestor(calendar, node.widget), 0, "in the picker, not in a popover")
        XCTAssertEqual(gtk_calendar_get_day(OpaquePointer(calendar)), 16)
    }

    func testChangingTheDisplayedComponentsRebuildsTheParts() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"displayedComponents": "dateAndTime", "selectedDate": "2024-07-16T14:30:00"}}"#)
        XCTAssertNotNil(try parts(node).hour)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "displayedComponents", value: "date")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(try parts(node).hour, "no time fields once the picker shows a date only")
        XCTAssertNotNil(try parts(node).calendar)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "displayedComponents", value: "hourAndMinute")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(try parts(node).calendar, "no calendar once the picker shows a time only")
        XCTAssertEqual(gtk_spin_button_get_value_as_int(OpaquePointer(try XCTUnwrap(try parts(node).hour))), 14)
    }

    func testTheControlIsNamedAfterTheTitleAlsoWhenLabelsAreHidden() throws {
        let node = try render(#"{"type": "DatePicker", "id": 1, "properties": {"title": "Start", "labelsHidden": true}}"#)
        XCTAssertEqual(gtk_widget_get_visible(try XCTUnwrap(gtk_widget_get_first_child(node.widget))), 0)
        let button = try XCTUnwrap(try parts(node).button)
        XCTAssertEqual(DatePicker.accessibleWidget(node.widget), button)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(button), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
    }
}
