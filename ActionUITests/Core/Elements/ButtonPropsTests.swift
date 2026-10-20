// Core/Elements/ButtonPropsTests.swift
/*
 Tests for Button.Props: the title default, the role names, the image scale (any letter case, unknown means medium) and the action keys.
*/

import XCTest
@testable import ActionUI

final class ButtonPropsTests: XCTestCase {

    func testDefaults() {
        let props = Button.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.assetImage)
        XCTAssertNil(props.imageScale)
        XCTAssertNil(props.role)
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.popoverActionID)
    }

    func testValidValues() {
        let props = Button.Props([
            "title": "Delete", "systemImage": "trash", "assetImage": "Logo", "imageScale": "large",
            "role": "destructive", "actionID": "delete", "popoverActionID": "popped",
        ])
        XCTAssertEqual(props.title, "Delete")
        XCTAssertEqual(props.systemImage, "trash")
        XCTAssertEqual(props.assetImage, "Logo")
        XCTAssertEqual(props.imageScale, .large)
        XCTAssertEqual(props.role, .destructive)
        XCTAssertEqual(props.actionID, "delete")
        XCTAssertEqual(props.popoverActionID, "popped")
    }

    func testRoleNames() {
        XCTAssertEqual(Button.Props(["role": "cancel"]).role, .cancel)
        XCTAssertNil(Button.Props(["role": "primary"]).role)
        XCTAssertNil(Button.Props(["role": 5]).role)
    }

    func testImageScaleIsMatchedInAnyLetterCase() {
        XCTAssertEqual(Button.Props(["imageScale": "Small"]).imageScale, .small)
        XCTAssertEqual(Button.Props(["imageScale": "MEDIUM"]).imageScale, .medium)
        XCTAssertEqual(Button.Props(["imageScale": "large"]).imageScale, .large)
    }

    func testUnknownImageScaleIsNone() {
        // The renderer keeps the medium scale for none.
        XCTAssertNil(Button.Props(["imageScale": "huge"]).imageScale)
        XCTAssertNil(Button.Props(["imageScale": 5]).imageScale)
    }

    func testWrongTypesFallBack() {
        let props = Button.Props(["title": 5, "systemImage": 5, "assetImage": 5, "actionID": 5, "popoverActionID": 5])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.assetImage)
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.popoverActionID)
    }
}
