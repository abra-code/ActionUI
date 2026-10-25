// Tests/Styling/ControlSizeTests.swift
/*
 Tests for controlSize on the controls other than Button (ButtonRendererTests has Button's): a menu
 and a segmented Picker, a Stepper, a compact DatePicker, a ColorPicker and a Menu are shorter at
 mini and taller at large than at regular, in macOS's proportions (a ColorPicker's swatch keeps a
 mini one 22 px tall), with a smaller title font at mini;
 a TextField and a SecureField are shorter at mini and no taller at large, as macOS's are; a control
 with a font of its own keeps it; a checkbox, a switch, a slider and a button toggle step up from
 mini to large, a progress bar, a ring and a spinner are smaller at mini and no larger past regular.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ControlSizeTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "controlsize-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func height(_ widget: WidgetPointer?) -> Int32 {
        guard let widget else { return 0 }
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, -1, &minimum, &natural, nil, nil)
        return natural
    }

    private func width(_ widget: WidgetPointer?) -> Int32 {
        guard let widget else { return 0 }
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        return natural
    }

    /// The controls, each in a VStack of the given size; ids are 10 * row + column.
    private static func controls(_ size: String, _ row: Int) -> String {
        #"""
        {"type": "VStack", "id": \#(row * 10), "properties": {"controlSize": "\#(size)"}, "children": [
          {"type": "Picker", "id": \#(row * 10 + 1), "properties": {"title": "Kind", "options": ["One", "Two"]}},
          {"type": "Picker", "id": \#(row * 10 + 2), "properties": {"title": "Kind", "options": ["One", "Two"], "pickerStyle": "segmented"}},
          {"type": "Stepper", "id": \#(row * 10 + 3), "properties": {"label": "Count"}},
          {"type": "DatePicker", "id": \#(row * 10 + 4), "properties": {"title": "Day", "displayedComponents": "date"}},
          {"type": "ColorPicker", "id": \#(row * 10 + 5), "properties": {"title": "Tint"}},
          {"type": "Menu", "id": \#(row * 10 + 6), "properties": {"title": "Actions"}, "children": [{"type": "Button", "id": \#(row * 10 + 7), "properties": {"title": "One"}}]},
          {"type": "TextField", "id": \#(row * 10 + 8), "properties": {"title": "Name"}},
          {"type": "SecureField", "id": \#(row * 10 + 9), "properties": {"title": "Password"}}]}
        """#
    }

    func testEachControlTakesItsSizeAsMacOSDoes() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "children": [\#(Self.controls("mini", 1)), \#(Self.controls("regular", 2)), \#(Self.controls("large", 3))]}"#)
        func widget(_ row: Int, _ column: Int) -> WidgetPointer? {
            root.childNodes[row * 10]?.childNodes[row * 10 + column]?.widget
        }
        for (column, name) in [(1, "menu Picker"), (2, "segmented Picker"), (3, "Stepper"), (4, "DatePicker"), (5, "ColorPicker"), (6, "Menu")] {
            let (mini, regular, large) = (height(widget(1, column)), height(widget(2, column)), height(widget(3, column)))
            XCTAssertLessThan(mini, regular, "\(name): \(mini) \(regular) \(large)")
            XCTAssertLessThan(regular, large, "\(name): \(mini) \(regular) \(large)")
            // A ColorPicker's swatch holds a 16 px part, which keeps a mini one 22 px tall.
            if name != "ColorPicker" && name != "Stepper" {
                XCTAssertEqual(Double(mini) / Double(regular), 0.54, accuracy: 0.03, "\(name): \(mini) \(regular)")
            }
        }
        for (column, name) in [(8, "TextField"), (9, "SecureField")] {
            let (mini, regular, large) = (height(widget(1, column)), height(widget(2, column)), height(widget(3, column)))
            XCTAssertLessThan(mini, regular, "\(name): \(mini) \(regular)")
            XCTAssertEqual(large, regular, "\(name): no taller than regular, as on macOS")
        }
        XCTAssertLessThan(width(widget(1, 3)), width(widget(2, 3)), "the Stepper's title is smaller at mini")
        // A Stepper's buttons are its own sizes, about 0.82 of a button's: 16, 28 and 34 px.
        XCTAssertEqual([1, 2, 3].map { height(widget($0, 3)) }, [16, 28, 34])
    }

    func testAControlWithAFontOfItsOwnKeepsIt() throws {
        let root = try render(#"""
            {"type": "HStack", "id": 1, "properties": {"controlSize": "mini"}, "children": [
              {"type": "Stepper", "id": 2, "properties": {"label": "Count"}},
              {"type": "Stepper", "id": 3, "properties": {"label": "Count", "font": "body"}}]}
            """#)
        let inherited = try XCTUnwrap(root.childNodes[2]).widget
        let own = try XCTUnwrap(root.childNodes[3]).widget
        XCTAssertLessThan(width(inherited), width(own), "the own font is not made smaller")
    }

    /// The indicators, each in a VStack of the given size; ids are 10 * row + column.
    private static func indicators(_ size: String, _ row: Int) -> String {
        #"""
        {"type": "VStack", "id": \#(row * 10), "properties": {"controlSize": "\#(size)"}, "children": [
          {"type": "Toggle", "id": \#(row * 10 + 1), "properties": {"title": "Check", "style": "checkbox"}},
          {"type": "Toggle", "id": \#(row * 10 + 2), "properties": {"title": "Switch", "style": "switch"}},
          {"type": "Slider", "id": \#(row * 10 + 3), "properties": {"value": 0.5}},
          {"type": "Toggle", "id": \#(row * 10 + 4), "properties": {"title": "Button", "style": "button"}},
          {"type": "ProgressView", "id": \#(row * 10 + 5), "properties": {"value": 0.5, "total": 1}},
          {"type": "ProgressView", "id": \#(row * 10 + 6)},
          {"type": "ProgressView", "id": \#(row * 10 + 7), "properties": {"value": 0.5, "total": 1, "progressViewStyle": "circular"}}]}
        """#
    }

    func testIndicatorsTakeMacOSsSteps() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "children": [\#(Self.indicators("mini", 1)), \#(Self.indicators("regular", 2)), \#(Self.indicators("large", 3))]}"#)
        func widget(_ row: Int, _ column: Int) -> WidgetPointer? {
            root.childNodes[row * 10]?.childNodes[row * 10 + column]?.widget
        }
        for (column, name) in [(1, "checkbox"), (2, "switch"), (3, "slider"), (4, "button toggle")] {
            let (mini, regular, large) = (height(widget(1, column)), height(widget(2, column)), height(widget(3, column)))
            XCTAssertLessThan(mini, regular, "\(name): \(mini) \(regular) \(large)")
            XCTAssertLessThan(regular, large, "\(name): \(mini) \(regular) \(large)")
        }
        // The slider's track keeps its 4 px at each size (a knob's margins larger than half its
        // size less the track's collapse it).
        for row in 1...3 {
            let track = Gtk.Widget(try XCTUnwrap(widget(row, 3))).firstChild?.pointer
            XCTAssertEqual(height(track), 4, "row \(row)")
        }
        let switches = (1...3).map { width(widget($0, 2)) }
        XCTAssertLessThan(switches[0], switches[1], "a switch narrows with its height: \(switches)")
        XCTAssertLessThan(switches[1], switches[2], "\(switches)")
        let bars = (1...3).map { height(widget($0, 5)) }
        XCTAssertLessThan(bars[0], bars[1], "a progress bar is thinner at mini: \(bars)")
        XCTAssertEqual(bars[2], bars[1], "and no thicker at large, as on macOS")
        func side(_ row: Int, _ column: Int) throws -> Int32 {
            width(ProgressView.accessibleWidget(try XCTUnwrap(widget(row, column))))
        }
        XCTAssertEqual(try (1...3).map { try side($0, 7) }, [10, 32, 32], "macOS's ring sides")
        XCTAssertEqual(try (1...3).map { try side($0, 6) }, [16, 32, 32], "a spinner: libadwaita's 16 px minimum at mini")
    }
}
