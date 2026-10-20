// Core/Elements/PickerPropsTests.swift
/*
 Tests for Picker.Props: the title, the two option formats (plain strings numbered from 1, or
 title/tag dictionaries with section and divider entries), the skipped entries, the style names and
 the radio layout flag. "wheel" exists off macOS and is not in the validation comparison, which
 runs on macOS, where validation drops it; Props keeps the name and the renderer applies nothing.
*/

import XCTest
@testable import ActionUI

final class PickerPropsTests: XCTestCase {

    func testDefaults() {
        let props = Picker.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertEqual(props.sections, [])
        XCTAssertEqual(props.options, [])
        XCTAssertNil(props.style)
        XCTAssertFalse(props.horizontalRadioGroupLayout)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = Picker.Props([
            "title": "Size", "options": ["S", "M"] as [Any], "pickerStyle": "segmented",
            "horizontalRadioGroupLayout": true, "actionID": "picked",
        ])
        XCTAssertEqual(props.title, "Size")
        XCTAssertEqual(props.options.map(\.title), ["S", "M"])
        XCTAssertEqual(props.style, .segmented)
        XCTAssertTrue(props.horizontalRadioGroupLayout)
        XCTAssertEqual(props.actionID, "picked")
    }

    func testStringOptionsAreNumberedFromOne() {
        let props = Picker.Props(["options": ["A", "B", "C"] as [Any]])
        XCTAssertEqual(props.options.map(\.tag), ["1", "2", "3"])
        XCTAssertEqual(props.sections.count, 1)
        XCTAssertNil(props.sections[0].title)
        XCTAssertEqual(props.sections[0].index, 0)
    }

    func testEmptyOptionsAreOneEmptySection() {
        let props = Picker.Props(["options": [Any]()])
        XCTAssertEqual(props.sections.count, 1)
        XCTAssertEqual(props.options, [])
    }

    func testDictionaryOptions() {
        let props = Picker.Props(["options": [["title": "Red", "tag": "r"], ["title": "Blue", "tag": "b"]] as [Any]])
        XCTAssertEqual(props.options, [.init(title: "Red", tag: "r"), .init(title: "Blue", tag: "b")])
        XCTAssertEqual(props.sections.count, 1)
        XCTAssertNil(props.sections[0].title)
    }

    func testEntriesWithoutATitleOrATagAreSkipped() {
        let props = Picker.Props(["options": [
            ["title": "Red", "tag": "r"], ["title": "", "tag": "x"], ["title": "NoTag"], ["tag": "notitle"],
            ["title": 5, "tag": "t"], ["title": "Blue", "tag": ""], ["title": "Green", "tag": "g"],
        ] as [Any]])
        XCTAssertEqual(props.options.map(\.tag), ["r", "g"])
    }

    func testSectionsAndDividers() {
        let props = Picker.Props(["options": [
            ["title": "A", "tag": "a"],
            ["section": "More"],
            ["title": "B", "tag": "b"],
            ["divider": true],
            ["title": "C", "tag": "c"],
        ] as [Any]])
        XCTAssertEqual(props.sections.map(\.title), [nil, "More", nil])
        XCTAssertEqual(props.sections.map(\.index), [0, 1, 2])
        XCTAssertEqual(props.sections.map { $0.items.map(\.tag) }, [["a"], ["b"], ["c"]])
        XCTAssertEqual(props.sections.map(\.id), ["_section_0", "More", "_section_2"])
        XCTAssertEqual(props.options.map(\.tag), ["a", "b", "c"])
    }

    func testLeadingSectionHeaderStartsTheFirstSection() {
        let props = Picker.Props(["options": [["section": "First"], ["title": "A", "tag": "a"]] as [Any]])
        XCTAssertEqual(props.sections.map(\.title), ["First"])
        XCTAssertEqual(props.options.map(\.tag), ["a"])
    }

    func testDividerFlagMustBeTrue() {
        let props = Picker.Props(["options": [["divider": false], ["title": "A", "tag": "a"]] as [Any]])
        XCTAssertEqual(props.sections.count, 1)
        XCTAssertEqual(props.options.map(\.tag), ["a"])
    }

    func testOptionsOfAnotherShapeAreNone() {
        for options: Any in ["x", 5, [1, 2] as [Any], [["title": "A", "tag": "a"], "B"] as [Any]] {
            XCTAssertEqual(Picker.Props(["options": options]).sections, [], "\(options)")
        }
    }

    func testStyleNames() {
        XCTAssertEqual(Picker.Props(["pickerStyle": "menu"]).style, .menu)
        XCTAssertEqual(Picker.Props(["pickerStyle": "radioGroup"]).style, .radioGroup)
        // Kept on every platform; the renderer applies nothing where it does not exist.
        XCTAssertEqual(Picker.Props(["pickerStyle": "wheel"]).style, .wheel)
        XCTAssertNil(Picker.Props(["pickerStyle": "fancy"]).style)
        XCTAssertNil(Picker.Props(["pickerStyle": 5]).style)
    }

    func testRadioLayoutMustBeTrue() {
        XCTAssertFalse(Picker.Props(["horizontalRadioGroupLayout": "true"]).horizontalRadioGroupLayout)
        XCTAssertFalse(Picker.Props(["horizontalRadioGroupLayout": false]).horizontalRadioGroupLayout)
    }

    func testWrongTypesFallBack() {
        let props = Picker.Props(["title": 5, "actionID": 5])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.actionID)
    }
}
