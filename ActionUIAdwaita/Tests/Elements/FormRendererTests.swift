// Tests/Elements/FormRendererTests.swift
/*
 Tests for the Form and Section renderers on GTK, against the rules measured on macOS 27: the
 titles of a Form's LabeledContent rows end at a label column as wide as the widest title, every
 row's content starts 8 points after it (an empty title makes a column of 0), a Section's rows and
 header are the Form's own rows, 8 points apart. (Rows without text are in the layout parity
 fixtures: form-rows-hug, form-sections-add-no-space, form-filling-row; with text, the font
 differs from macOS, so the rules are checked here.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class FormRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        windowUUID = "form-\(name)"
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

    private func block(_ id: Int, _ width: Int, _ height: Int) -> String {
        #"{"type": "Rectangle", "id": \#(id), "properties": {"w": \#(width), "h": \#(height)}}"#
    }

    private func labeled(_ id: Int, _ title: String, _ child: String) -> String {
        #"{"type": "LabeledContent", "id": \#(id), "properties": {"title": "\#(title)"}, "children": [\#(child)]}"#
    }

    /// The node with element id `id` among `root`'s descendants.
    private func node(_ id: Int, in root: RenderNode) -> RenderNode? {
        if root.element.id == id { return root }
        for child in root.childNodes.values {
            if let found = node(id, in: child) { return found }
        }
        return nil
    }

    /// [x, y, width, height] of `widget` in the Form's widget, after laying the Form out at its
    /// natural size.
    private func frame(_ widget: WidgetPointer, in form: RenderNode) -> [Int] {
        var minimum: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_measure(form.outerWidget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &width, nil, nil)
        gtk_widget_measure(form.outerWidget, GTK_ORIENTATION_VERTICAL, width, &minimum, &height, nil, nil)
        gtk_widget_allocate(form.outerWidget, width, height, -1, nil)
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, form.widget, &bounds)
        return [Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.size.width), Int(bounds.size.height)]
    }

    private func frame(_ id: Int, in form: RenderNode) throws -> [Int] {
        frame(try XCTUnwrap(node(id, in: form)).widget, in: form)
    }

    /// The title label of LabeledContent `id`.
    private func title(_ id: Int, in root: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(node(id, in: root)).widget))
    }

    func testTitlesEndAtOneColumnAndEveryRowsContentStartsAfterIt() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(labeled(2, "Name", block(3, 20, 20))), \#(labeled(4, "A much longer name", block(5, 40, 20))), \#(block(6, 30, 20))]}"#)
        let short = frame(try title(2, in: form), in: form)
        let long = frame(try title(4, in: form), in: form)
        XCTAssertEqual(long[0], 0, "the widest title starts at the Form's edge")
        XCTAssertEqual(short[0] + short[2], long[0] + long[2], "the titles end at one column")
        let column = long[2] + 8
        XCTAssertEqual(try frame(3, in: form)[0], column)
        XCTAssertEqual(try frame(5, in: form)[0], column)
        XCTAssertEqual(try frame(6, in: form)[0], column, "a row without a title starts at the content too")
    }

    func testAnEmptyTitleMakesAColumnOfZero() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(labeled(2, "", block(3, 20, 20))), \#(block(4, 40, 20))]}"#)
        XCTAssertEqual(try frame(3, in: form)[0], 8)
        XCTAssertEqual(try frame(4, in: form)[0], 8)
    }

    func testANegativeLeadingPaddingOnATitledRowMakesANegativeColumn() throws {
        // Measured on macOS 27: an empty title padded 3 points before the row's leading edge ends
        // at -3, the column is -3, and a row without a title starts 8 after it, at 5.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "LabeledContent", "id": 2, "properties": {"title": "", "padding": {"leading": -3}}, "children": [\#(block(3, 30, 20))]}, \#(block(4, 40, 20))]}"#)
        XCTAssertEqual(try frame(4, in: form)[0], 5)
    }

    func testWithoutTitlesTheRowsStartAtTheEdgeEightApart() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(block(2, 20, 20)), \#(block(3, 40, 20))]}"#)
        XCTAssertEqual(try frame(2, in: form), [0, 0, 20, 20])
        XCTAssertEqual(try frame(3, in: form), [0, 28, 40, 20])
    }

    func testASectionsRowsAndHeaderAreTheFormsRows() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(labeled(2, "Name", block(3, 20, 20))), {"type": "Section", "id": 4, "properties": {"header": "Head"}, "children": [\#(labeled(5, "A much longer name", block(6, 40, 20)))]}, {"type": "Section", "id": 7, "children": [\#(block(8, 30, 20))]}]}"#)
        let long = frame(try title(5, in: form), in: form)
        let column = long[2] + 8
        XCTAssertEqual(try frame(3, in: form)[0], column, "a title in a Section sets the Form's column")
        XCTAssertEqual(try frame(6, in: form)[0], column)
        XCTAssertEqual(try frame(8, in: form)[0], column)

        let section = try XCTUnwrap(node(4, in: form))
        let headerBox = try XCTUnwrap(gtk_widget_get_first_child(section.widget))
        let header = try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(ModifierBox.content(of: headerBox))))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(header))), "Head")
        let headerFrame = frame(header, in: form)
        XCTAssertEqual(headerFrame[0], column, "the header is in the content column")
        let first = try frame(3, in: form)
        XCTAssertEqual(headerFrame[1], first[1] + first[3] + 8, "8 below the row before")
        XCTAssertEqual(frame(try title(5, in: form), in: form)[1] >= headerFrame[1] + headerFrame[3] + 8, true,
                       "the Section's first row 8 below its header")

        let untitled = try XCTUnwrap(node(7, in: form))
        let hiddenBox = try XCTUnwrap(gtk_widget_get_first_child(untitled.widget))
        let hidden = try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(ModifierBox.content(of: hiddenBox))))
        XCTAssertEqual(gtk_widget_get_visible(hidden), 0, "no header, no label")
        let last = try frame(8, in: form)
        let before = try frame(6, in: form)
        XCTAssertEqual(last[1] - (before[1] + before[3]) >= 8, true, "a Section without a header adds no row")
    }

    func testATitleEndsWhereItsRowPutsItPaddingAndFrameIncluded() throws {
        // Measured on macOS 27: the column takes the title's trailing edge as the row lays it
        // out, so a leading padding of 30 on an empty-titled row makes a column of 30, and a row
        // framed 200 wide centers its 28 of content and makes a column of 86.
        let padded = try render(#"{"type": "Form", "id": 1, "children": [{"type": "LabeledContent", "id": 2, "properties": {"title": "", "padding": {"leading": 30}}, "children": [\#(block(3, 20, 20))]}, \#(block(4, 40, 20))]}"#)
        XCTAssertEqual(try frame(3, in: padded)[0], 38)
        XCTAssertEqual(try frame(4, in: padded)[0], 38, "the row without a title starts at the content column")
        let framed = try render(#"{"type": "Form", "id": 1, "children": [{"type": "LabeledContent", "id": 2, "properties": {"title": "", "frame": {"width": 200}}, "children": [\#(block(3, 20, 20))]}, \#(block(4, 40, 20))]}"#)
        XCTAssertEqual(try frame(3, in: framed)[0], 94)
        XCTAssertEqual(try frame(4, in: framed)[0], 94)
    }

    func testAGroupsPaddingMovesItsRowsTitlesAndTheColumnWithThem() throws {
        // Measured on macOS 27: the Group's leading padding of 30 goes on each of its rows; the
        // titled one's title ends at 30, the column; the untitled one starts at the content
        // column, its padding inside.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "Group", "id": 9, "properties": {"padding": {"leading": 30}}, "children": [{"type": "LabeledContent", "id": 2, "properties": {"title": ""}, "children": [\#(block(3, 20, 20))]}, \#(block(7, 30, 20))]}, \#(block(4, 40, 20))]}"#)
        XCTAssertEqual(try frame(3, in: form)[0], 38)
        XCTAssertEqual(try frame(7, in: form)[0], 68)
        XCTAssertEqual(try frame(4, in: form)[0], 38)
    }

    func testControlTitlesEndAtTheLabelColumn() throws {
        // Measured on macOS 27: a Picker's, a Stepper's, a ColorPicker's and a switch Toggle's
        // titles end at the column as a LabeledContent's does, and their controls start 8 after it.
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(labeled(2, "Name", block(3, 20, 20))), {"type": "Picker", "id": 4, "properties": {"title": "A much longer name", "options": ["One", "Two"]}}, {"type": "Stepper", "id": 5, "properties": {"label": "Count"}}, {"type": "ColorPicker", "id": 6, "properties": {"title": "Tint"}}, {"type": "Toggle", "id": 8, "properties": {"title": "On", "style": "switch"}}, \#(block(7, 30, 20))]}"#)
        let picker = try XCTUnwrap(node(4, in: form)).widget
        let pickerTitle = frame(try XCTUnwrap(gtk_widget_get_first_child(picker)), in: form)
        XCTAssertEqual(pickerTitle[0], 0, "the widest title starts at the Form's edge")
        let column = pickerTitle[2]
        for id in [2, 5, 6, 8] {
            let title = frame(try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(node(id, in: form)).widget)), in: form)
            XCTAssertEqual(title[0] + title[2], column, "row \(id)'s title ends at the column")
        }
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(picker)), in: form)[0], column + 8, "the dropdown")
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(try XCTUnwrap(node(5, in: form)).widget)), in: form)[0],
                       column + 8, "the stepper's buttons")
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(try XCTUnwrap(node(6, in: form)).widget)), in: form)[0],
                       column + 8, "the color button")
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(try XCTUnwrap(node(8, in: form)).widget)), in: form)[0],
                       column + 8, "the switch")
        XCTAssertEqual(try frame(3, in: form)[0], column + 8)
        XCTAssertEqual(try frame(7, in: form)[0], column + 8)
    }

    func testAnEmptyControlTitleMakesAColumnOfZero() throws {
        // Measured on macOS 27: as an empty LabeledContent title, the control starts at 8, and
        // so does every other row.
        for control in [#"{"type": "Picker", "id": 2, "properties": {"title": "", "options": ["One"]}}"#,
                        #"{"type": "Stepper", "id": 2, "properties": {"label": ""}}"#,
                        #"{"type": "ColorPicker", "id": 2, "properties": {"title": ""}}"#,
                        #"{"type": "Toggle", "id": 2, "properties": {"title": "", "style": "switch"}}"#] {
            let form = try render(#"{"type": "Form", "id": 1, "children": [\#(control), \#(block(3, 20, 20))]}"#)
            let widget = try XCTUnwrap(node(2, in: form)).widget
            XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(widget)), in: form)[0], 8, control)
            XCTAssertEqual(try frame(3, in: form)[0], 8, control)
        }
    }

    func testHiddenLabelsAndACheckboxToggleMakeNoColumn() throws {
        // Measured on macOS 27: a control under labelsHidden is a row without a title, and a
        // checkbox Toggle's title stays beside its checkbox.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "Picker", "id": 2, "properties": {"title": "Title", "labelsHidden": true, "options": ["One"]}}, {"type": "Toggle", "id": 4, "properties": {"title": "Toggle"}}, {"type": "Toggle", "id": 5, "properties": {"title": "Switch", "style": "switch", "labelsHidden": true}}, \#(block(3, 20, 20))]}"#)
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(try XCTUnwrap(node(2, in: form)).widget)), in: form)[0], 0)
        XCTAssertEqual(try frame(4, in: form)[0], 0)
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(try XCTUnwrap(node(5, in: form)).widget)), in: form)[0], 0)
        XCTAssertEqual(try frame(3, in: form)[0], 0)
    }

    func testATextFieldsTitleStandsBeforeItInTheLabelColumn() throws {
        // Measured on macOS 27: in a Form a TextField's and a SecureField's titles end at the
        // column and the field starts 8 after it; the placeholder is the prompt alone.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "Picker", "id": 2, "properties": {"title": "A much longer name", "options": ["One"]}}, {"type": "TextField", "id": 3, "properties": {"title": "Name"}}, {"type": "SecureField", "id": 4, "properties": {"title": "Password", "prompt": "Required"}}, \#(block(5, 30, 20))]}"#)
        let column = frame(try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(node(2, in: form)).widget)), in: form)[2]
        for id in [3, 4] {
            let widget = try XCTUnwrap(node(id, in: form)).widget
            let title = try XCTUnwrap(gtk_widget_get_first_child(widget))
            XCTAssertNotEqual(gtk_widget_get_visible(title), 0, "field \(id) shows its title")
            let titleFrame = frame(title, in: form)
            XCTAssertEqual(titleFrame[0] + titleFrame[2], column, "field \(id)'s title ends at the column")
            XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(widget)), in: form)[0], column + 8, "field \(id)")
        }
        XCTAssertEqual(try frame(5, in: form)[0], column + 8)

        let field = try XCTUnwrap(node(3, in: form)).widget
        let entry = try XCTUnwrap(gtk_widget_get_last_child(field))
        XCTAssertNil(swiftString(gtk_entry_get_placeholder_text(typed(entry))), "no prompt, no placeholder: the title is outside")
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(entry), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "the entry is named after the title")
        XCTAssertNotEqual(gtk_widget_get_hexpand(entry), 0, "the field still fills")
    }

    func testAnEmptyOrHiddenTextFieldTitle() throws {
        // Measured on macOS 27: an empty title makes a column of 0 (the field at 8); labelsHidden
        // makes no column (the field at 0).
        for (field, x) in [(#"{"type": "TextField", "id": 2, "properties": {"title": ""}}"#, 8),
                           (#"{"type": "SecureField", "id": 2, "properties": {"title": ""}}"#, 8),
                           (#"{"type": "TextField", "id": 2, "properties": {"title": "Name", "labelsHidden": true}}"#, 0),
                           (#"{"type": "SecureField", "id": 2, "properties": {"title": "Name", "labelsHidden": true}}"#, 0)] {
            let form = try render(#"{"type": "Form", "id": 1, "children": [\#(field), \#(block(3, 20, 20))]}"#)
            let widget = try XCTUnwrap(node(2, in: form)).widget
            XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(widget)), in: form)[0], x, field)
            XCTAssertEqual(try frame(3, in: form)[0], x, field)
        }
    }

    func testATextFieldInsertedIntoAFormShowsItsTitle() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "Picker", "id": 2, "properties": {"title": "A much longer name", "options": ["One"]}}]}"#)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1, json: #"{"type": "TextField", "id": 3, "properties": {"title": "Name"}}"#)
        AdwaitaTestHost.drainMainLoop()
        let column = frame(try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(node(2, in: form)).widget)), in: form)[2]
        let widget = try XCTUnwrap(node(3, in: form)).widget
        XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(widget)), in: form)[0], column + 8)
    }

    /// Where `widget`'s title (its first child) ends in the Form.
    private func titleEnd(_ widget: WidgetPointer, in form: RenderNode) throws -> Int {
        let title = frame(try XCTUnwrap(gtk_widget_get_first_child(widget)), in: form)
        return title[0] + title[2]
    }

    private func picker(_ id: Int, _ title: String) -> String {
        #"{"type": "Picker", "id": \#(id), "properties": {"title": "\#(title)", "options": ["One"]}}"#
    }

    func testATitleInsideAStackRowSetsTheColumn() throws {
        // Measured on macOS 27: an HStack row takes its label from the titled control in it, where
        // the row places it: after a 30-point Color, the title ends at 30 + 8 + its width.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "HStack", "id": 2, "children": [\#(block(3, 30, 20)), \#(picker(4, "Name"))]}, \#(block(5, 20, 20))]}"#)
        XCTAssertEqual(try frame(3, in: form)[0], 0, "the row is not moved: its label is the column")
        let column = try titleEnd(try XCTUnwrap(node(4, in: form)).widget, in: form)
        XCTAssertEqual(column, 30 + 8 + frame(try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(node(4, in: form)).widget)), in: form)[2])
        XCTAssertEqual(try frame(5, in: form)[0], column + 8)
    }

    func testTitlesInOneRowMakeTheirAverage() throws {
        // Measured on macOS 27: SwiftUI averages the alignment several children give, so two
        // titles in one HStack row make a column halfway between where they end.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "HStack", "id": 2, "children": [\#(picker(3, "Name")), \#(picker(4, "A longer name"))]}, \#(block(5, 20, 20))]}"#)
        let first = try titleEnd(try XCTUnwrap(node(3, in: form)).widget, in: form)
        let second = try titleEnd(try XCTUnwrap(node(4, in: form)).widget, in: form)
        let column = Int((Double(first + second) / 2).rounded(.toNearestOrAwayFromZero))
        XCTAssertEqual(try frame(5, in: form)[0], column + 8)
    }

    func testStackRowsLineUpTheirTitles() throws {
        // Measured on macOS 27: the row whose title ends sooner moves right to the column (20 here,
        // 30 - 10), and both pickers start at 30 + 8 + 0 + 8.
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "HStack", "id": 2, "children": [\#(block(3, 30, 20)), \#(picker(4, ""))]}, {"type": "HStack", "id": 5, "children": [\#(block(6, 10, 20)), \#(picker(7, ""))]}]}"#)
        XCTAssertEqual(try frame(3, in: form)[0], 0)
        XCTAssertEqual(try frame(6, in: form)[0], 20)
        for id in [4, 7] {
            XCTAssertEqual(frame(try XCTUnwrap(gtk_widget_get_last_child(try XCTUnwrap(node(id, in: form)).widget)), in: form)[0], 46)
        }
    }

    func testALabeledContentOrAZStackInsideARowGivesItsTitle() throws {
        // Measured on macOS 27: a LabeledContent in an HStack row gives its title as a control does;
        // a ZStack row gives the title of the control it holds, where it places the control.
        let labeled = try render(#"{"type": "Form", "id": 1, "children": [{"type": "HStack", "id": 2, "children": [\#(block(3, 30, 20)), \#(labeled(4, "Name", block(5, 20, 20)))]}, \#(block(6, 20, 20))]}"#)
        let column = try titleEnd(try XCTUnwrap(node(4, in: labeled)).widget, in: labeled)
        XCTAssertEqual(try frame(5, in: labeled)[0], column + 8)
        XCTAssertEqual(try frame(6, in: labeled)[0], column + 8)

        let layered = try render(#"{"type": "Form", "id": 1, "children": [{"type": "ZStack", "id": 2, "children": [\#(block(3, 200, 20)), {"type": "HStack", "id": 4, "children": [\#(block(5, 30, 20)), \#(picker(6, ""))]}]}, \#(block(7, 20, 20))]}"#)
        XCTAssertEqual(try frame(7, in: layered)[0], try frame(5, in: layered)[0] + 30 + 8 + 8,
                       "the centered HStack's empty title ends 30 + 8 after its start")
    }

    func testATitleChangedAtRunTimeMovesTheOtherRows() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(labeled(2, "A", block(3, 20, 20))), \#(labeled(4, "Name", block(5, 40, 20))), \#(block(6, 30, 20))]}"#)
        let before = try frame(5, in: form)[0]
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "title", value: "A much longer name")
        AdwaitaTestHost.drainMainLoop()
        let long = frame(try title(2, in: form), in: form)
        let column = long[2] + 8
        XCTAssertGreaterThan(column, before, "the longer title widens the column")
        XCTAssertEqual(try frame(3, in: form)[0], column)
        XCTAssertEqual(try frame(5, in: form)[0], column, "the other titled row moves to the new column")
        XCTAssertEqual(try frame(6, in: form)[0], column, "the untitled row moves to the new column")
    }

    func testASectionKeepsItsHeaderFirstThroughInsertsAndRemovals() throws {
        let form = try render(#"{"type": "Form", "id": 1, "children": [{"type": "Section", "id": 4, "properties": {"header": "Head"}, "children": [\#(block(5, 20, 20))]}]}"#)
        let section = try XCTUnwrap(node(4, in: form))
        func header() throws -> WidgetPointer {
            let headerBox = try XCTUnwrap(gtk_widget_get_first_child(section.widget))
            return try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(ModifierBox.content(of: headerBox))))
        }

        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 4, json: block(6, 30, 20), position: .prepend)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try header()))), "Head", "a prepended row goes after the header")
        var headerFrame = frame(try header(), in: form)
        let inserted = try frame(6, in: form)
        XCTAssertEqual(inserted[1], headerFrame[1] + headerFrame[3] + 8, "the prepended row 8 below the header")
        XCTAssertEqual(try frame(5, in: form)[1], inserted[1] + inserted[3] + 8)

        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 6)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(node(6, in: form))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try header()))), "Head")
        headerFrame = frame(try header(), in: form)
        XCTAssertEqual(try frame(5, in: form)[1], headerFrame[1] + headerFrame[3] + 8, "the remaining row moves up under the header")
    }

    func testAFormAtTheWindowRootIsCentered() throws {
        // Measured on macOS 27: a Form is as large as its rows and centered in its parent, like a
        // VStack; its rows keep to its leading edge.
        let form = try render(#"{"type": "Form", "id": 1, "children": [\#(block(2, 20, 20)), \#(block(3, 40, 20))]}"#)
        gtk_widget_allocate(form.outerWidget, 200, 200, -1, nil)
        func frame(_ id: Int) throws -> [Int] {
            var bounds = graphene_rect_t()
            _ = gtk_widget_compute_bounds(try XCTUnwrap(node(id, in: form)).widget, form.outerWidget, &bounds)
            return [Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.size.width), Int(bounds.size.height)]
        }
        XCTAssertEqual(try frame(2), [80, 76, 20, 20])
        XCTAssertEqual(try frame(3), [80, 104, 40, 20])
    }
}
