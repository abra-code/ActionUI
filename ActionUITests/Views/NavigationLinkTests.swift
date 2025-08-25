// Tests/Views/NavigationLinkTests.swift
/*
 NavigationLinkTests.swift

 Tests for the NavigationLink component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "label": "Go to Detail",
     "link": "detail"
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class NavigationLinkTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        super.tearDown()
    }
    
    func testNavigationLinkJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationLink",
            "destination": ["type": "Text", "id": 2, "properties": ["text": "Detail"]],
            "properties": [
                "label": "Go to Detail",
                "link": "detail"
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = NavigationLink.validateProperties(element.properties, logger)
            let destination = element.subviews?["destination"] as? any ActionUIElement
            logger.log("destination: \((destination as? ViewElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "NavigationLink", "Element type should be NavigationLink")
            XCTAssertEqual((destination as? ViewElement)?.type, "Text", "Destination should be Text")
            XCTAssertEqual((destination as? ViewElement)?.id, 2, "Destination ID should be 2")
            XCTAssertEqual((element.properties["label"] as? String), "Go to Detail", "Label should be Go to Detail")
            XCTAssertEqual((element.properties["link"] as? String), "detail", "Link should be detail")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
    
    func testNavigationLinkMalformedDestination() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationLink",
            "destination": ["id": 2, "properties": ["text": "Detail"]], // Missing type
            "properties": [
                "label": "Go to Detail",
                "link": "detail"
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = NavigationLink.validateProperties(element.properties, logger)
            let destination = element.subviews?["destination"] as? any ActionUIElement
            XCTAssertNil(destination, "Malformed destination should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
