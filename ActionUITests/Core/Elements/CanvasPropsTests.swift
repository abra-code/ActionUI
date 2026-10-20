// Core/Elements/CanvasPropsTests.swift
/*
 Tests for Canvas.Props: the drawing operations that survive filtering (a path, text and frame,
 exactly one image source and a frame, a blur radius, a layer frame; unknown types dropped; a
 layer's own operations filtered the same way), the background color, the coordinate mode and the
 tap action. The operations stay raw dictionaries: CanvasRenderer parses them.
*/

import XCTest
@testable import ActionUI

final class CanvasPropsTests: XCTestCase {
    private let path: [String: Any] = ["type": "circle", "center": [0.5, 0.5] as [Any], "radius": 0.4]
    private let frame: [Any] = [0.1, 0.1, 0.8, 0.8]

    private func types(_ operations: [Any]) -> [String] {
        Canvas.Props(["operations": operations]).operations.compactMap { $0["type"] as? String }
    }

    func testDefaults() {
        let props = Canvas.Props([:])
        XCTAssertEqual(props.operations.count, 0)
        XCTAssertNil(props.backgroundColor)
        XCTAssertEqual(props.coordinateMode, .normalized)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = Canvas.Props([
            "operations": [["type": "fill", "path": path, "color": "#FF0000"]] as [Any],
            "backgroundColor": "#F5F5F5", "coordinateMode": "points", "actionID": "tap",
        ])
        XCTAssertEqual(props.operations.count, 1)
        XCTAssertEqual(props.operations[0]["color"] as? String, "#FF0000")
        XCTAssertEqual(props.backgroundColor, "#F5F5F5")
        XCTAssertEqual(props.coordinateMode, .points)
        XCTAssertEqual(props.actionID, "tap")
    }

    func testWrongTypesFallBack() {
        let props = Canvas.Props(["operations": "x", "backgroundColor": 5, "coordinateMode": 5, "actionID": 5])
        XCTAssertEqual(props.operations.count, 0)
        XCTAssertNil(props.backgroundColor)
        XCTAssertEqual(props.coordinateMode, .normalized)
        XCTAssertNil(props.actionID)
    }

    func testCoordinateModeMustBeAKnownName() {
        XCTAssertEqual(Canvas.Props(["coordinateMode": "normalized"]).coordinateMode, .normalized)
        XCTAssertEqual(Canvas.Props(["coordinateMode": "pixels"]).coordinateMode, .normalized)
        XCTAssertEqual(Canvas.Props(["coordinateMode": "Points"]).coordinateMode, .normalized)
    }

    func testOperationsThatAreNotAllDictionariesAreNone() {
        for operations: Any in [[1, 2] as [Any], [["type": "fill", "path": path], "x"] as [Any], 5] {
            XCTAssertEqual(Canvas.Props(["operations": operations]).operations.count, 0, "\(operations)")
        }
    }

    func testPathOperationsNeedAPathDictionary() {
        XCTAssertEqual(types([["type": "fill", "path": path], ["type": "stroke", "path": path], ["type": "clip", "path": path]]), ["fill", "stroke", "clip"])
        XCTAssertEqual(types([["type": "fill"], ["type": "stroke", "path": "circle"], ["type": "clip", "path": 5]]), [])
    }

    func testTypeNamesAreMatchedInAnyCaseAndKeptAsWritten() {
        XCTAssertEqual(types([["type": "FILL", "path": path], ["type": "ROTATE"]]), ["FILL", "ROTATE"])
    }

    func testOperationsWithoutATypeAreDropped() {
        XCTAssertEqual(types([["path": path], ["type": 5, "path": path], ["type": "spin"]]), [])
    }

    func testTextNeedsTextAndAFrameOfFour() {
        XCTAssertEqual(types([["type": "text", "text": "Hi", "frame": frame]]), ["text"])
        XCTAssertEqual(types([["type": "text", "text": "Hi", "frame": [0.1, 0.2] as [Any]], ["type": "text", "text": 5, "frame": frame], ["type": "text", "frame": frame]]), [])
    }

    func testImageNeedsExactlyOneSourceAndAFrameOfFour() {
        XCTAssertEqual(types([
            ["type": "image", "systemName": "star", "frame": frame],
            ["type": "image", "filePath": "/tmp/a.png", "frame": frame],
        ]), ["image", "image"])
        // Several sources drop the operation; none drops it too.
        XCTAssertEqual(types([
            ["type": "image", "systemName": "star", "assetName": "a", "frame": frame],
            ["type": "image", "frame": frame],
            ["type": "image", "systemName": "star"],
            ["type": "image", "systemName": "star", "frame": [1, 2, 3] as [Any]],
        ]), [])
    }

    func testBlurNeedsANumericRadius() {
        XCTAssertEqual(types([["type": "blur", "radius": 0.015], ["type": "blur", "radius": 3], ["type": "blur", "radius": 0], ["type": "blur", "radius": -1]]), ["blur", "blur", "blur", "blur"])
        XCTAssertEqual(types([["type": "blur"], ["type": "blur", "radius": "big"]]), [])
    }

    func testShadowAndTransformsNeedNothing() {
        XCTAssertEqual(types([["type": "shadow"], ["type": "translate"], ["type": "scale"], ["type": "rotate"]]), ["shadow", "translate", "scale", "rotate"])
    }

    func testLayerNeedsAFrameAndFiltersItsOwnOperations() {
        let props = Canvas.Props(["operations": [
            ["type": "layer", "frame": frame, "operations": [["type": "fill", "path": path], ["type": "bogus"], ["type": "blur"]] as [Any]],
            ["type": "layer", "frame": frame, "operations": "none"],
            ["type": "layer"],
        ] as [Any]])
        XCTAssertEqual(props.operations.count, 2)
        let inner = props.operations[0]["operations"] as? [[String: Any]]
        XCTAssertEqual(inner?.compactMap { $0["type"] as? String }, ["fill"])
        // A layer operations value of another shape is left for the renderer, as it was.
        XCTAssertEqual(props.operations[1]["operations"] as? String, "none")
    }
}
