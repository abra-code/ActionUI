// Tests/Views/MapTests.swift
/*
 MapTests.swift

 Tests for the Map component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and annotation rendering.
*/

import XCTest
import SwiftUI
import MapKit
@testable import ActionUI

@MainActor
final class MapTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        super.tearDown()
    }
        
    func testMapJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Map",
            "properties": {
                "coordinate": { "latitude": 37.33233141, "longitude": -122.0312186 },
                "showsUserLocation": true,
                "interactionModes": ["pan", "zoom"],
                "annotations": [
                    {
                        "coordinate": { "latitude": 37.332, "longitude": -122.031 },
                        "title": "Point A",
                        "subtitle": "Location A"
                    }
                ]
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Map", "Element type should be Map")
        if let coord = element.properties.coordinate(forKey: "coordinate") {
            XCTAssertEqual(coord.latitude, 37.33233141, accuracy: 0.0001, "Coordinate latitude should be 37.33233141")
            XCTAssertEqual(coord.longitude, -122.0312186, accuracy: 0.0001, "Coordinate longitude should be -122.0312186")
        }
        else {
            XCTFail("Map properties missing expected coordinate")
        }
        XCTAssertEqual(element.properties["showsUserLocation"] as? Bool, true, "showsUserLocation should be true")
        XCTAssertEqual(element.properties["interactionModes"] as? [String], ["pan", "zoom"], "interactionModes should be ['pan', 'zoom']")
        let annotations = element.properties["annotations"] as? [[String: Any]]
        XCTAssertEqual(annotations?.count, 1, "Annotations should have 1 item")
        let annotation = annotations?.first
        if let annotationCoord = annotation?.coordinate(forKey: "coordinate") {
            XCTAssertEqual(annotationCoord.latitude, 37.332, accuracy: 0.0001, "Annotation coordinate latitude should be 37.332")
            XCTAssertEqual(annotationCoord.longitude, -122.031, accuracy: 0.0001, "Annotation coordinate longitude should be -122.031")
        } else {
            XCTFail("Map properties missing correct annotation[coordinate] value")
        }
        XCTAssertEqual(annotation?["title"] as? String, "Point A", "Annotation title should be Point A")
        XCTAssertEqual(annotation?["subtitle"] as? String, "Location A", "Annotation subtitle should be Location A")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testMapValidatePropertiesValid() {
        let properties: [String: Any] = [
            "coordinate": ["latitude": 37.33233141, "longitude": -122.0312186],
            "showsUserLocation": true,
            "interactionModes": ["pan", "zoom", "rotate"],
            "annotations": [
                ["coordinate": ["latitude": 37.332, "longitude": -122.031], "title": "Point A", "subtitle": "Location A"]
            ]
        ]
        
        let validated = Map.validateProperties(properties, logger)
        
        if let coord = validated.coordinate(forKey:"coordinate") {
            XCTAssertEqual(coord.latitude, 37.33233141, accuracy: 0.0001, "Coordinate latitude should be valid")
            XCTAssertEqual(coord.longitude, -122.0312186, accuracy: 0.0001, "Coordinate longitude should be valid")
        } else {
            XCTFail("expected valid coordinate")
        }
        XCTAssertEqual(validated["showsUserLocation"] as? Bool, true, "showsUserLocation should be valid")
        XCTAssertEqual(validated["interactionModes"] as? [String], ["pan", "zoom", "rotate"], "interactionModes should be valid")
        let annotations = validated["annotations"] as? [[String: Any]]
        XCTAssertEqual(annotations?.count, 1, "Annotations should have 1 item")
        let annotation = annotations?.first
        if let annotationCoord = annotation?.coordinate(forKey:"coordinate") {
            XCTAssertEqual(annotationCoord.latitude, 37.332, accuracy: 0.0001, "Annotation coordinate latitude should be valid")
            XCTAssertEqual(annotationCoord.longitude, -122.031, accuracy: 0.0001, "Annotation coordinate longitude should be valid")
        } else {
            XCTFail("annotation[\"coordinate\"] must not be nil")
        }
        XCTAssertEqual(annotation?["title"] as? String, "Point A", "Annotation title should be valid")
        XCTAssertEqual(annotation?["subtitle"] as? String, "Location A", "Annotation subtitle should be valid")
    }
    
    func testMapValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "coordinate": ["latitude": "invalid", "longitude": true],
            "showsUserLocation": "true",
            "interactionModes": ["invalid"],
            "annotations": [
                ["coordinate": ["latitude": "invalid", "longitude": true], "title": 123, "subtitle": false]
            ]
        ]
        
        let validated = Map.validateProperties(properties, logger)
        
        if validated.coordinate(forKey:"coordinate") != nil {
            XCTFail("invalid coordinate should be nil")
        }
        
        XCTAssertEqual(validated["showsUserLocation"] as? Bool, false, "Invalid showsUserLocation should default to false")
        XCTAssertEqual(validated["interactionModes"] as? [String], ["pan", "zoom", "rotate"], "Invalid interactionModes should default to all")
        let annotations = validated["annotations"] as? [[String: Any]]
        XCTAssertEqual(annotations?.count, 0, "Invalid annotations should default to empty array")
    }
    
    func testMapValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Map.validateProperties(properties, logger)
        
        XCTAssertNil(validated["coordinate"], "Missing coordinate should be nil")
        XCTAssertEqual(validated["showsUserLocation"] as? Bool, false, "Missing showsUserLocation should default to false")
        XCTAssertEqual(validated["interactionModes"] as? [String], ["pan", "zoom", "rotate"], "Missing interactionModes should default to all")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                validated["annotations"] as? [String: Any] ?? [:],
                [:]
            ),
            "Missing annotations should default to empty array"
        )
    }
    
    func testMapCameraBindingUpdatesState() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Map",
            "properties": [
                "coordinate": ["latitude": 37.33233141, "longitude": -122.0312186],
                "showsUserLocation": true
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        
        // Trigger complete construction of DatePicker
         guard let windowModel = actionUIModel.windowModels[windowUUID],
               let viewModel = windowModel.viewModels[element.id] else {
             XCTFail("Failed to retrieve viewModel")
             return
         }

         let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
         _ = actionUIView.body // Force body creation

        // Simulate camera change
        let newCoord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: element.id, value: newCoord)
                
        if let stateCoord = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: element.id) as? CLLocationCoordinate2D {
            XCTAssertEqual(stateCoord.latitude, 40.7128, accuracy: 0.0001, "Map state should update to new coordinate latitude")
            XCTAssertEqual(stateCoord.longitude, -74.0060, accuracy: 0.0001, "Map state should update to new coordinate longitude")
        }
        else {
            XCTFail("stateCoord must not be nil")
        }
    }
}
