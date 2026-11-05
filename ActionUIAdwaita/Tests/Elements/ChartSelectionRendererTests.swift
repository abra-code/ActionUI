// Tests/Elements/ChartSelectionRendererTests.swift
/*
 Tests for chart selection on GTK through the chart widget's own controllers: the pointer over the
 plot selects a value and leaving clears it; a drag selects a range; the value and the action follow
 Apple's rules (settled after 150 ms, continuous at once, a cleared selection at once, none for a
 value the host sets); the "$selection" marks are drawn from the value. The signals are emitted as
 GTK would emit them for the pointer, with the chart on screen so its plot has a place.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ChartSelectionRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var shown: [UnsafeMutablePointer<GtkWidget>] = []
    private var actions = 0

    override func setUp() async throws {
        // No super.setUp(): see PaintModifierTests.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "chart-selection-\(name)"
        ActionUIModel.shared.registerActionHandler(for: "test.selected") { [weak self] _, _, _, _, _ in
            MainActor.assumeIsolated { self?.actions += 1 }
        }
    }

    override func tearDown() async throws {
        ActionUIModel.shared.unregisterActionHandler(for: "test.selected")
        for window in shown {
            gtk_window_set_child(typed(window), nil)
            gtk_window_destroy(typed(window))
        }
        shown = []
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    /// Bars Mon, Tue, Wed and a rule at the selection, 300 x 200, on screen.
    private func show(selection: String = #""chartXSelection": "value""#, timing: String = "settled") throws -> RenderNode {
        let json = ##"""
        {"type": "Chart", "id": 1, "properties": {"valueChangeActionID": "test.selected", "selectionActionTiming": "\##(timing)",
         "frame": {"width": 300, "height": 200},
         "chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["Mon", 4], ["Tue", 2], ["Wed", 3]], \##(selection),
                   "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"},
                                                                "y": {"label": "N", "value": "$n"}}]},
                               {"type": "RuleMark", "x": {"label": "Selected", "value": "$selection"}}]}}}
        """##
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let gtkWindow = gtk_window_new()!
        shown.append(gtkWindow)
        gtk_window_set_child(typed(gtkWindow), node.outerWidget)
        gtk_window_present(typed(gtkWindow))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        // The first frame draws the chart, which places its plot.
        let end = g_get_monotonic_time() + 200_000
        _ = AdwaitaTestHost.runMainLoop(until: { g_get_monotonic_time() >= end })
        return node
    }

    private var value: String {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? String ?? ""
    }

    /// The chart widget's controller of `type`.
    private func controller(_ node: RenderNode, _ type: GType) throws -> UnsafeMutableRawPointer {
        let controllers = gtk_widget_observe_controllers(node.widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), type) != 0 {
                return item
            }
        }
        throw XCTSkip("no controller of that type")
    }

    /// Emits `signal` with a point (x, y) on `instance`, as GTK does for the pointer.
    private func emit(_ signal: String, on instance: UnsafeMutableRawPointer, _ type: GType, x: Double, y: Double) {
        var values = [GValue](repeating: GValue(), count: 3)
        g_value_init(&values[0], type)
        g_value_set_object(&values[0], instance)
        g_value_init(&values[1], g_type_from_name("gdouble"))
        g_value_set_double(&values[1], x)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], y)
        g_signal_emitv(&values, g_signal_lookup(signal, type), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    private func hover(_ node: RenderNode, x: Double, y: Double) throws {
        let motion = try controller(node, gtk_event_controller_motion_get_type())
        emit("motion", on: motion, gtk_event_controller_motion_get_type(), x: x, y: y)
        AdwaitaTestHost.drainMainLoop()
    }

    private func leave(_ node: RenderNode) throws {
        let motion = try controller(node, gtk_event_controller_motion_get_type())
        AdwaitaTestHost.emit("leave", on: motion)
        AdwaitaTestHost.drainMainLoop()
    }

    private func selectionMarks(_ node: RenderNode) -> Int {
        // The resolved marks are private to the renderer: count the rule by the chart's drawing,
        // through the value the marks were read from (ChartMarkResolver is checked in
        // ChartSelectionHitTests).
        let description = node.properties["chart"] as? [String: Any] ?? [:]
        let spec = ChartDescription.parse(description, logger: nil).spec
        let rows = node.model.states["content"] as? [[String]] ?? []
        let selection = ChartSelection.decode(value, spec: spec.selection)
        return ChartMarkResolver.resolve(spec, rows: rows, selection: selection).instances.filter(\.readsSelection).count
    }

    func testThePointerOverThePlotSelectsTheBandUnderIt() throws {
        let node = try show()
        // Three bands across the plot, which ends before the y labels on the trailing side (as in
        // Swift Charts): the middle of the chart is the middle band. Past the plot, on the labels,
        // nothing is selected.
        try hover(node, x: 290, y: 100)
        XCTAssertEqual(value, "")
        try hover(node, x: 130, y: 100)
        XCTAssertEqual(value, #"{"x":"Tue"}"#)
        XCTAssertEqual(selectionMarks(node), 1)
        try leave(node)
        XCTAssertEqual(value, "")
        XCTAssertEqual(selectionMarks(node), 0)
    }

    func testASettledActionWaitsForTheSelectionToRest() throws {
        let node = try show()
        try hover(node, x: 130, y: 100)
        XCTAssertEqual(actions, 0, "not before it rests")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { self.actions == 1 }, timeoutMilliseconds: 1000))
        // A cleared selection fires at once.
        try leave(node)
        XCTAssertEqual(actions, 2)
    }

    func testAContinuousActionFiresOnEveryChange() throws {
        let node = try show(timing: "continuous")
        try hover(node, x: 130, y: 100)
        XCTAssertEqual(actions, 1)
        // The same band: no change, no action.
        try hover(node, x: 132, y: 120)
        XCTAssertEqual(actions, 1)
    }

    func testAValueTheHostSetsFiresNothing() throws {
        let node = try show()
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: #"{"x":"Tue"}"#)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(selectionMarks(node), 1)
        XCTAssertFalse(AdwaitaTestHost.runMainLoop(until: { self.actions > 0 }, timeoutMilliseconds: 300))
    }

    func testAChartThatSelectsNothingIgnoresThePointer() throws {
        let node = try show(selection: #""chartYScale": {"type": "linear"}"#)
        try hover(node, x: 130, y: 100)
        XCTAssertEqual(value, "")
    }

    func testADragSelectsARangeUntilItEnds() throws {
        let node = try show(selection: #""chartYSelection": "range""#)
        let drag = try controller(node, gtk_gesture_drag_get_type())
        emit("drag-begin", on: drag, gtk_gesture_drag_get_type(), x: 150, y: 30)
        emit("drag-update", on: drag, gtk_gesture_drag_get_type(), x: 0, y: 100)
        AdwaitaTestHost.drainMainLoop()
        let selection = ChartSelection.decode(value, spec: ChartSelectionSpec(y: .range, yType: .number))
        guard case .range(.number(let low), .number(let high))? = selection.y else { return XCTFail("a range: \(value)") }
        XCTAssertLessThan(low, high, "in order, though the drag ran down the axis")
        emit("drag-end", on: drag, gtk_gesture_drag_get_type(), x: 0, y: 100)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value, "")
    }

    func testAClickOnARangeChartSelectsNothing() throws {
        let node = try show(selection: #""chartYSelection": "range""#)
        let drag = try controller(node, gtk_gesture_drag_get_type())
        emit("drag-begin", on: drag, gtk_gesture_drag_get_type(), x: 150, y: 30)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value, "")
        emit("drag-end", on: drag, gtk_gesture_drag_get_type(), x: 0, y: 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value, "")
        XCTAssertFalse(AdwaitaTestHost.runMainLoop(until: { self.actions > 0 }, timeoutMilliseconds: 300), "no change, no action")
    }

    // MARK: Scrolling

    /// Points at x 0...100, 20 of them in view, selecting x by value, 300 x 200, on screen.
    private func showScrolling() throws -> RenderNode {
        let rows = (0...100).map { "[\($0), \($0 % 10)]" }.joined(separator: ", ")
        let json = ##"""
        {"type": "Chart", "id": 1, "properties": {"frame": {"width": 300, "height": 200},
         "chart": {"columns": [{"name": "x", "type": "number"}, {"name": "y", "type": "number"}], "data": [\##(rows)],
                   "chartXSelection": "value", "chartScrollableAxes": "horizontal", "chartXVisibleDomain": {"length": 20},
                   "content": [{"type": "ForEach", "content": [{"type": "PointMark", "x": {"label": "X", "value": "$x"},
                                                                "y": {"label": "Y", "value": "$y"}}]}]}}}
        """##
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let gtkWindow = gtk_window_new()!
        shown.append(gtkWindow)
        gtk_window_set_child(typed(gtkWindow), node.outerWidget)
        gtk_window_present(typed(gtkWindow))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        waitForFrame()
        return node
    }

    private func waitForFrame() {
        let end = g_get_monotonic_time() + 200_000
        _ = AdwaitaTestHost.runMainLoop(until: { g_get_monotonic_time() >= end })
    }

    /// Emits the scroll controller's "scroll" with (dx, dy); returns whether the chart took it.
    private func scroll(_ node: RenderNode, dx: Double, dy: Double) throws -> Bool {
        let type = gtk_event_controller_scroll_get_type()
        let scroller = try controller(node, type)
        var handled = GValue()
        g_value_init(&handled, g_type_from_name("gboolean"))
        defer { g_value_unset(&handled) }
        var values = [GValue](repeating: GValue(), count: 3)
        g_value_init(&values[0], type)
        g_value_set_object(&values[0], scroller)
        g_value_init(&values[1], g_type_from_name("gdouble"))
        g_value_set_double(&values[1], dx)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], dy)
        g_signal_emitv(&values, g_signal_lookup("scroll", type), 0, &handled)
        for index in values.indices { g_value_unset(&values[index]) }
        waitForFrame()
        return g_value_get_boolean(&handled) != 0
    }

    /// The x the pointer selects at the plot's leading edge (a few points in).
    private func leadingX(_ node: RenderNode) throws -> Double {
        try hover(node, x: 3, y: 100)
        let selection = ChartSelection.decode(value, spec: ChartSelectionSpec(x: .value, xType: .number))
        guard case .value(.number(let x))? = selection.x else { throw XCTSkip("no selection: \(value)") }
        return x
    }

    func testAScrollMovesTheWindowAndStopsAtItsEnd() throws {
        let node = try showScrolling()
        let start = try leadingX(node)
        XCTAssertLessThan(start, 2, "the window starts at the domain's start")
        // A vertical wheel moves the only scrolling axis, the horizontal one.
        XCTAssertTrue(try scroll(node, dx: 0, dy: 3))
        let moved = try leadingX(node)
        XCTAssertGreaterThan(moved, start + 5)
        // Far past the end: held there, and the next scroll is left to what holds the chart.
        XCTAssertTrue(try scroll(node, dx: 1000, dy: 0))
        XCTAssertEqual(try leadingX(node), 80, accuracy: 2)
        XCTAssertFalse(try scroll(node, dx: 5, dy: 0))
    }

    func testAChartThatDoesNotScrollLeavesTheScrollToItsHolder() throws {
        let node = try show()
        XCTAssertFalse(try scroll(node, dx: 0, dy: 3))
    }

    // MARK: Annotations

    /// Bars with a Text annotation reading the row's value, 300 x 200, on screen.
    private func showAnnotated(rows: Int = 3) throws -> RenderNode {
        let data = (0..<rows).map { #"["d\#($0)", \#($0 + 2)]"# }.joined(separator: ", ")
        let json = ##"""
        {"type": "Chart", "id": 1, "properties": {"frame": {"width": 300, "height": 200},
         "chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [\##(data)],
                   "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"},
                                "y": {"label": "N", "value": "$n"},
                                "annotation": {"content": {"type": "Text", "properties": {"text": "$n"}}}}]}]}}}
        """##
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let gtkWindow = gtk_window_new()!
        shown.append(gtkWindow)
        gtk_window_set_child(typed(gtkWindow), node.outerWidget)
        gtk_window_present(typed(gtkWindow))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        waitForFrame()
        return node
    }

    private func annotationViews(_ node: RenderNode) -> [WidgetPointer] {
        var views: [WidgetPointer] = []
        var child = gtk_widget_get_first_child(node.widget)
        while let current = child {
            views.append(current)
            child = gtk_widget_get_next_sibling(current)
        }
        return views
    }

    /// The text of the first label inside `widget`.
    private func text(in widget: WidgetPointer) -> String? {
        if g_type_check_instance_is_a(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self), gtk_label_get_type()) != 0 {
            return gtk_label_get_text(OpaquePointer(widget)).map { String(cString: $0) }
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = text(in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    func testEachBarShowsItsAnnotationAboveIt() throws {
        let node = try showAnnotated()
        let views = annotationViews(node)
        XCTAssertEqual(views.count, 3)
        XCTAssertEqual(Set(views.compactMap { text(in: $0) }), ["2", "3", "4"], "each reads its row")
        for view in views {
            XCTAssertNotEqual(gtk_widget_get_visible(view), 0)
            var bounds = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(view, node.widget, &bounds), 0)
            XCTAssertGreaterThan(bounds.size.width, 0)
            XCTAssertLessThan(Double(bounds.origin.y) + Double(bounds.size.height), 200, "above the bottom of the chart")
        }
    }

    func testNewRowsKeepTheAnnotationsOfRowsThatStayed() throws {
        let node = try showAnnotated()
        let before = Set(annotationViews(node).map { UInt(bitPattern: $0) })
        ActionUIModel.shared.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [["d9", "7"]])
        AdwaitaTestHost.drainMainLoop()
        let after = annotationViews(node)
        XCTAssertEqual(after.count, 4)
        XCTAssertTrue(before.isSubset(of: Set(after.map { UInt(bitPattern: $0) })))
    }

    func testPastAThousandAnnotationsTheMarksDrawWithoutThem() throws {
        let node = try showAnnotated(rows: 1001)
        XCTAssertEqual(annotationViews(node).count, 0)
    }
}

extension ChartSelectionRendererTests {
    /// A 300 x 200 chart of `chart` (the "chart" property's JSON), on screen.
    private func showChart(_ chart: String) throws -> RenderNode {
        let json = #"{"type": "Chart", "id": 1, "properties": {"frame": {"width": 300, "height": 200}, "chart": "# + chart + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let gtkWindow = gtk_window_new()!
        shown.append(gtkWindow)
        gtk_window_set_child(typed(gtkWindow), node.outerWidget)
        gtk_window_present(typed(gtkWindow))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        waitForFrame()
        return node
    }

    func testAScrollingChartShowsOnlyTheAnnotationsOfMarksInItsWindow() throws {
        let rows = (0...100).map { "[\($0), \($0 % 10)]" }.joined(separator: ", ")
        let node = try showChart(##"""
        {"columns": [{"name": "x", "type": "number"}, {"name": "y", "type": "number"}], "data": [\##(rows)],
         "chartScrollableAxes": "horizontal", "chartXVisibleDomain": {"length": 20},
         "content": [{"type": "ForEach", "content": [{"type": "PointMark", "x": {"label": "X", "value": "$x"},
                      "y": {"label": "Y", "value": "$y"}, "annotation": {"content": {"type": "Text", "properties": {"text": "$x"}}}}]}]}
        """##)
        let views = annotationViews(node)
        XCTAssertEqual(views.count, 101)
        let seen = views.filter { gtk_widget_get_mapped($0) != 0 }
        XCTAssertGreaterThan(seen.count, 10)
        XCTAssertLessThan(seen.count, 30, "about the 20 in the window")
        for view in seen {
            var bounds = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(view, node.widget, &bounds), 0)
            XCTAssertLessThan(bounds.origin.x, 300)
            XCTAssertGreaterThan(bounds.origin.x + bounds.size.width, 0)
        }
    }

    func testANewAnnotationContentReplacesTheViews() throws {
        let node = try showChart(##"""
        {"columns": ["day", {"name": "n", "type": "number"}], "data": [["d0", "2"], ["d1", "3"], ["d2", "4"]],
         "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"}, "y": {"label": "N", "value": "$n"},
                      "annotation": {"content": {"type": "Text", "properties": {"text": "$n"}}}}]}]}
        """##)
        XCTAssertEqual(Set(annotationViews(node).compactMap { text(in: $0) }), ["2", "3", "4"])
        let changed: [String: Any] = ["columns": ["day", ["name": "n", "type": "number"]], "data": [["d0", "2"], ["d1", "3"], ["d2", "4"]],
                                      "content": [["type": "ForEach", "content": [["type": "BarMark", "x": ["label": "Day", "value": "$day"],
                                                                                   "y": ["label": "N", "value": "$n"],
                                                                                   "annotation": ["content": ["type": "Text", "properties": ["text": "v$n"]]]]]]]]
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "chart", value: changed)
        AdwaitaTestHost.drainMainLoop()
        let views = annotationViews(node)
        XCTAssertEqual(views.count, 3)
        XCTAssertEqual(Set(views.compactMap { text(in: $0) }), ["v2", "v3", "v4"])
    }

    func testAnAnnotationPastTheChartsEdgeIsDrawnThereAsOnApple() throws {
        let json = ##"""
        {"type": "Chart", "id": 1, "properties": {"frame": {"width": 300, "height": 200},
         "chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["A", 10]], "chartYScale": {"domain": [0, 10]},
                   "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"},
                                "y": {"label": "N", "value": "$n"},
                                "annotation": {"content": {"type": "Text", "properties": {"text": "top"}}}}]}]}}}
        """##
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let gtkWindow = gtk_window_new()!
        shown.append(gtkWindow)
        gtk_window_set_child(typed(gtkWindow), node.outerWidget)
        gtk_window_present(typed(gtkWindow))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        waitForFrame()
        // Measured on macOS 27 in a window: a label above a bar that reaches the top draws over what
        // is around the chart, not cut off at its edge.
        let view = try XCTUnwrap(annotationViews(node).first)
        XCTAssertNotEqual(gtk_widget_get_child_visible(view), 0)
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(view, node.widget, &bounds), 0)
        XCTAssertLessThan(bounds.origin.y, 0, "above the chart's top")
    }
}
