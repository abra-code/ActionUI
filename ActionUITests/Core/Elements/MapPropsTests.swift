// Core/Elements/MapPropsTests.swift
/*
 Tests for Map.Props: the coordinate, the user location flag, the interaction modes (all three
 unless every entry is a mode name), the annotations (one without a valid coordinate is skipped)
 and the two actions. The map's value, the center coordinate, is not a property.
*/

import XCTest
@testable import ActionUI

final class MapPropsTests: XCTestCase {
    private let apple: [String: Any] = ["latitude": 37.33, "longitude": -122.03]

    func testDefaults() {
        let props = Map.Props([:])
        XCTAssertNil(props.coordinate)
        XCTAssertFalse(props.showsUserLocation)
        XCTAssertEqual(props.interactionModes, [.pan, .zoom, .rotate])
        XCTAssertEqual(props.annotations, [])
        XCTAssertNil(props.valueChangeActionID)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = Map.Props([
            "coordinate": apple, "showsUserLocation": true, "interactionModes": ["zoom", "pan"] as [Any],
            "annotations": [["coordinate": apple, "title": "Apple", "subtitle": "Cupertino"]] as [Any],
            "valueChangeActionID": "moved", "actionID": "camera",
        ])
        XCTAssertEqual(props.coordinate, .init(latitude: 37.33, longitude: -122.03))
        XCTAssertTrue(props.showsUserLocation)
        XCTAssertEqual(props.interactionModes, [.zoom, .pan])
        XCTAssertEqual(props.annotations, [.init(coordinate: .init(latitude: 37.33, longitude: -122.03), title: "Apple", subtitle: "Cupertino")])
        XCTAssertEqual(props.valueChangeActionID, "moved")
        XCTAssertEqual(props.actionID, "camera")
    }

    func testCoordinateNeedsNumericLatitudeAndLongitude() {
        XCTAssertEqual(Map.Props(["coordinate": ["latitude": 1, "longitude": 2] as [String: Any]]).coordinate, .init(latitude: 1, longitude: 2))
        for coordinate: Any in [["latitude": 1] as [String: Any], ["latitude": "1", "longitude": 2] as [String: Any], "37,-122", 5, [37.3, -122.0] as [Any]] {
            XCTAssertNil(Map.Props(["coordinate": coordinate]).coordinate, "\(coordinate)")
        }
    }

    func testUserLocationMustBeABool() {
        XCTAssertFalse(Map.Props(["showsUserLocation": "true"]).showsUserLocation)
        XCTAssertFalse(Map.Props(["showsUserLocation": 1]).showsUserLocation)
    }

    func testInteractionModesAreAllWhenAnyEntryIsNotAModeName() {
        XCTAssertEqual(Map.Props(["interactionModes": ["pan"] as [Any]]).interactionModes, [.pan])
        // An empty list is kept: no interaction at all.
        XCTAssertEqual(Map.Props(["interactionModes": [Any]()]).interactionModes, [])
        for modes: Any in [["pan", "tilt"] as [Any], ["Pan"] as [Any], ["pan", 5] as [Any], "pan", 5] {
            XCTAssertEqual(Map.Props(["interactionModes": modes]).interactionModes, [.pan, .zoom, .rotate], "\(modes)")
        }
    }

    func testAnnotationsWithoutAValidCoordinateAreSkipped() {
        let props = Map.Props(["annotations": [
            ["coordinate": apple, "title": "A"],
            ["title": "No coordinate"],
            ["coordinate": ["latitude": 1] as [String: Any], "title": "Half"],
            ["coordinate": apple, "title": 5, "subtitle": true],
        ] as [Any]])
        XCTAssertEqual(props.annotations.map(\.title), ["A", nil])
        XCTAssertNil(props.annotations[1].subtitle)
    }

    func testAnnotationsOfAnotherShapeAreNone() {
        for annotations: Any in ["x", 5, [1, 2] as [Any], [["coordinate": apple], 5] as [Any]] {
            XCTAssertEqual(Map.Props(["annotations": annotations]).annotations, [], "\(annotations)")
        }
    }
}
