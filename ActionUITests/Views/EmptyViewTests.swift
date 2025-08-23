// Tests/Views/EmptyViewTests.swift
/*
 EmptyViewTests.swift

 Tests for the EmptyView component in the ActionUI component library.
 Minimal tests for view construction and state initialization, as most functionality is covered by ViewTests.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class EmptyViewTests: XCTestCase {
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
    
    func testEmptyViewConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "EmptyView",
            "properties": [:]
        ]
        let element = try! ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = EmptyView.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        _ = view // Ensure view is used
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        XCTAssertNotNil(state.wrappedValue[element.id], "Registry should initialize state for EmptyView")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                (state.wrappedValue[element.id] as? [String: Any])?["validatedProperties"] as? [String: Any] ?? [:],
                validatedProperties
            ),
            "State should include validated properties"
        )
    }
    
    func testEmptyViewJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "EmptyView",
            "properties": ["padding": 10.0]
        ]
        
        let element = try! ViewElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "EmptyView", "Element type should be EmptyView")
        XCTAssertEqual(element.properties["padding"] as? Double, 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
}
