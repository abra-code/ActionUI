// Tests/ActionUIElementTests.swift
/*
 ActionUIElementTests.swift

 Tests for ActionUIElement in ActionUIElement.swift, focusing on encoding/decoding, Equatable conformance, and findElement functionality.
 Verifies JSON serialization with various subviews (children, rows, content, destination, sidebar, detail),
 equality comparisons for all subviews types, and edge cases for robust JSON parsing and error handling.
 Also tests findElement(by:) for locating elements by ID in all possible subview keys and nested structures.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIElementTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
    }
    
    override func tearDown() {
        logger = nil
        super.tearDown()
    }
    
    func testEncodingAndDecodingWithChildren() throws {
        // Arrange: JSON with children
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 },
            "children": [
                { "id": 2, "type": "Text", "properties": { "text": "Child1" } },
                { "id": 3, "type": "Button", "properties": { "title": "Click" } }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act: Decode
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Assert: Verify decoded element
        XCTAssertEqual(element.id, 1, "ID should be 1")
        XCTAssertEqual(element.type, "View", "Type should be View")
        XCTAssertEqual(element.properties.double(forKey: "padding"), 8.0, "Padding should be 8.0")
        XCTAssertNotNil(element.subviews, "Subviews should not be nil")
        if let children = element.subviews?["children"] as? [ActionUIElement] {
            XCTAssertEqual(children.count, 2, "Should have 2 children")
            XCTAssertEqual(children[0].id, 2, "First child ID should be 2")
            XCTAssertEqual(children[0].type, "Text", "First child type should be Text")
            XCTAssertEqual(children[0].properties["text"] as? String, "Child1", "First child text should be Child1")
            XCTAssertEqual(children[1].id, 3, "Second child ID should be 3")
            XCTAssertEqual(children[1].type, "Button", "Second child type should be Button")
            XCTAssertEqual(children[1].properties["title"] as? String, "Click", "Second child title should be Click")
        } else {
            XCTFail("Children should be an array of ActionUIElement")
        }
        
        // Act: Encode back to JSON
        let encodedData = try JSONEncoder(logger: logger).encode(element)
        let encodedElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: encodedData)
        
        // Assert: Verify round-trip
        XCTAssertEqual(encodedElement, element, "Encoded and decoded element should be equal")
    }
    
    func testEncodingAndDecodingWithRows() throws {
        // Arrange: JSON with rows (for Grid)
        let jsonString = """
        {
            "id": 1,
            "type": "Grid",
            "properties": { "spacing": 10.0 },
            "rows": [
                [
                    { "id": 2, "type": "Text", "properties": { "text": "Cell1" } },
                    { "id": 3, "type": "Button", "properties": { "title": "Click" } }
                ],
                [
                    { "id": 4, "type": "Text", "properties": { "text": "Cell2" } }
                ]
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act: Decode
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Assert: Verify decoded element
        XCTAssertEqual(element.id, 1, "ID should be 1")
        XCTAssertEqual(element.type, "Grid", "Type should be Grid")
        XCTAssertEqual(element.properties.double(forKey: "spacing"), 10.0, "Spacing should be 10.0")
        XCTAssertNotNil(element.subviews, "Subviews should not be nil")
        if let rows = element.subviews?["rows"] as? [[ActionUIElement]] {
            XCTAssertEqual(rows.count, 2, "Should have 2 rows")
            XCTAssertEqual(rows[0].count, 2, "First row should have 2 elements")
            XCTAssertEqual(rows[0][0].id, 2, "First cell ID should be 2")
            XCTAssertEqual(rows[0][0].type, "Text", "First cell type should be Text")
            XCTAssertEqual(rows[0][0].properties["text"] as? String, "Cell1", "First cell text should be Cell1")
            XCTAssertEqual(rows[0][1].id, 3, "Second cell ID should be 3")
            XCTAssertEqual(rows[0][1].type, "Button", "Second cell type should be Button")
            XCTAssertEqual(rows[0][1].properties["title"] as? String, "Click", "Second cell title should be Click")
            XCTAssertEqual(rows[1].count, 1, "Second row should have 1 element")
            XCTAssertEqual(rows[1][0].id, 4, "Second row cell ID should be 4")
            XCTAssertEqual(rows[1][0].type, "Text", "Second row cell type should be Text")
            XCTAssertEqual(rows[1][0].properties["text"] as? String, "Cell2", "Second row cell text should be Cell2")
        } else {
            XCTFail("Rows should be an array of arrays of ActionUIElement")
        }
        
        // Act: Encode back to JSON
        let encodedData = try JSONEncoder(logger: logger).encode(element)
        let encodedElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: encodedData)
        
        // Assert: Verify round-trip
        XCTAssertEqual(encodedElement, element, "Encoded and decoded element should be equal")
    }
    
    func testEncodingAndDecodingWithSingleChild() throws {
        // Arrange: JSON with content (for NavigationStack)
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationStack",
            "properties": { "title": "Home" },
            "content": { "id": 2, "type": "Text", "properties": { "text": "Home" } }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act: Decode
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Assert: Verify decoded element
        XCTAssertEqual(element.id, 1, "ID should be 1")
        XCTAssertEqual(element.type, "NavigationStack", "Type should be NavigationStack")
        XCTAssertEqual(element.properties["title"] as? String, "Home", "Title should be Home")
        XCTAssertNotNil(element.subviews, "Subviews should not be nil")
        if let content = element.subviews?["content"] as? ActionUIElement {
            XCTAssertEqual(content.id, 2, "Content ID should be 2")
            XCTAssertEqual(content.type, "Text", "Content type should be Text")
            XCTAssertEqual(content.properties["text"] as? String, "Home", "Content text should be Home")
        } else {
            XCTFail("Content should be a ActionUIElement")
        }
        
        // Act: Encode back to JSON
        let encodedData = try JSONEncoder(logger: logger).encode(element)
        let encodedElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: encodedData)
        
        // Assert: Verify round-trip
        XCTAssertEqual(encodedElement, element, "Encoded and decoded element should be equal")
    }
    
    func testEncodingAndDecodingWithMixedSubviews() throws {
        // Arrange: JSON with children and content
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationStack",
            "properties": { "title": "Home" },
            "children": [
                { "id": 2, "type": "Text", "properties": { "text": "Child1" } }
            ],
            "content": { "id": 3, "type": "Text", "properties": { "text": "Content" } }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act: Decode
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Assert: Verify decoded element
        XCTAssertEqual(element.id, 1, "ID should be 1")
        XCTAssertEqual(element.type, "NavigationStack", "Type should be NavigationStack")
        XCTAssertEqual(element.properties["title"] as? String, "Home", "Title should be Home")
        XCTAssertNotNil(element.subviews, "Subviews should not be nil")
        if let children = element.subviews?["children"] as? [ActionUIElement] {
            XCTAssertEqual(children.count, 1, "Should have 1 child")
            XCTAssertEqual(children[0].id, 2, "Child ID should be 2")
            XCTAssertEqual(children[0].type, "Text", "Child type should be Text")
            XCTAssertEqual(children[0].properties["text"] as? String, "Child1", "Child text should be Child1")
        } else {
            XCTFail("Children should be an array of ActionUIElement")
        }
        if let content = element.subviews?["content"] as? ActionUIElement {
            XCTAssertEqual(content.id, 3, "Content ID should be 3")
            XCTAssertEqual(content.type, "Text", "Content type should be Text")
            XCTAssertEqual(content.properties["text"] as? String, "Content", "Content text should be Content")
        } else {
            XCTFail("Content should be a ActionUIElement")
        }
        
        // Act: Encode back to JSON
        let encodedData = try JSONEncoder(logger: logger).encode(element)
        let encodedElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: encodedData)
        
        // Assert: Verify round-trip
        XCTAssertEqual(encodedElement, element, "Encoded and decoded element should be equal")
    }
    
    func testEncodingAndDecodingWithEmptySubviews() throws {
        // Arrange: JSON with no subviews
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act: Decode
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Assert: Verify decoded element
        XCTAssertEqual(element.id, 1, "ID should be 1")
        XCTAssertEqual(element.type, "View", "Type should be View")
        XCTAssertEqual(element.properties.double(forKey: "padding"), 8.0, "Padding should be 8.0")
        XCTAssertNil(element.subviews, "Subviews should be nil")
        
        // Act: Encode back to JSON
        let encodedData = try JSONEncoder(logger: logger).encode(element)
        let encodedElement = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: encodedData)
        
        // Assert: Verify round-trip
        XCTAssertEqual(encodedElement, element, "Encoded and decoded element should be equal")
    }
    
    func testEncodingAndDecodingWithInvalidSubviews() throws {
        // Arrange: JSON with invalid children (non-element array)
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 },
            "children": ["invalid"]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act & Assert: Expect decoding failure
        XCTAssertThrowsError(
            try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData),
            "Should throw error for invalid children"
        ) { error in
            XCTAssertTrue(error is DecodingError, "Error should be DecodingError")
        }
    }
    
    func testEquatableWithIdenticalChildren() {
        // Arrange: Two identical elements with children
        let element1 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil),
                    ActionUIElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                ]
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil),
                    ActionUIElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                ]
            ]
        )
        
        // Act & Assert
        XCTAssertEqual(element1, element2, "Elements with identical children should be equal")
    }
    
    func testEquatableWithDifferentChildren() {
        // Arrange: Two elements with different children
        let element1 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ]
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child2"], subviews: nil)
                ]
            ]
        )
        
        // Act & Assert
        XCTAssertNotEqual(element1, element2, "Elements with different children should not be equal")
    }
    
    func testEquatableWithIdenticalRows() {
        // Arrange: Two identical elements with rows
        let element1 = ActionUIElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ActionUIElement(id: 2, type: "Text", properties: ["text": "Cell1"], subviews: nil),
                        ActionUIElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                    ],
                    [
                        ActionUIElement(id: 4, type: "Text", properties: ["text": "Cell2"], subviews: nil)
                    ]
                ]
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ActionUIElement(id: 2, type: "Text", properties: ["text": "Cell1"], subviews: nil),
                        ActionUIElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                    ],
                    [
                        ActionUIElement(id: 4, type: "Text", properties: ["text": "Cell2"], subviews: nil)
                    ]
                ]
            ]
        )
        
        // Act & Assert
        XCTAssertEqual(element1, element2, "Elements with identical rows should be equal")
    }
    
    func testEquatableWithDifferentRows() {
        // Arrange: Two elements with different rows
        let element1 = ActionUIElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ActionUIElement(id: 2, type: "Text", properties: ["text": "Cell1"], subviews: nil)
                    ]
                ]
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ActionUIElement(id: 2, type: "Text", properties: ["text": "Cell2"], subviews: nil)
                    ]
                ]
            ]
        )
        
        // Act & Assert
        XCTAssertNotEqual(element1, element2, "Elements with different rows should not be equal")
    }
    
    func testEquatableWithIdenticalContent() {
        // Arrange: Two identical elements with content
        let element1 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ActionUIElement(id: 2, type: "Text", properties: ["text": "Home"], subviews: nil)
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ActionUIElement(id: 2, type: "Text", properties: ["text": "Home"], subviews: nil)
            ]
        )
        
        // Act & Assert
        XCTAssertEqual(element1, element2, "Elements with identical content should be equal")
    }
    
    func testEquatableWithDifferentContent() {
        // Arrange: Two elements with different content
        let element1 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ActionUIElement(id: 2, type: "Text", properties: ["text": "Home"], subviews: nil)
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ActionUIElement(id: 2, type: "Text", properties: ["text": "Different"], subviews: nil)
            ]
        )
        
        // Act & Assert
        XCTAssertNotEqual(element1, element2, "Elements with different content should not be equal")
    }
    
    func testEquatableWithMixedSubviews() {
        // Arrange: Two identical elements with children and content
        let element1 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ],
                "content": ActionUIElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ],
                "content": ActionUIElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        
        // Act & Assert
        XCTAssertEqual(element1, element2, "Elements with identical mixed subviews should be equal")
    }
    
    func testEquatableWithDifferentMixedSubviews() {
        // Arrange: Two elements with different children and same content
        let element1 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ],
                "content": ActionUIElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child2"], subviews: nil)
                ],
                "content": ActionUIElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        
        // Act & Assert
        XCTAssertNotEqual(element1, element2, "Elements with different mixed subviews should not be equal")
    }
    
    func testEquatableWithNilSubviews() {
        // Arrange: Two elements with nil subviews
        let element1 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: nil
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: nil
        )
        
        // Act & Assert
        XCTAssertEqual(element1, element2, "Elements with nil subviews should be equal")
    }
    
    func testEquatableWithEmptyAndNilSubviews() {
        // Arrange: One element with empty subviews, one with nil
        let element1 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [:]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: nil
        )
        
        // Act & Assert
        XCTAssertEqual(element1, element2, "Elements with empty and nil subviews should be equal")
    }
    
    func testEquatableWithDifferentSubviewKeys() {
        // Arrange: Two elements with different subview keys
        let element1 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ]
            ]
        )
        let element2 = ActionUIElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ActionUIElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
            ]
        )
        
        // Act & Assert
        XCTAssertNotEqual(element1, element2, "Elements with different subview keys should not be equal")
    }
    
    func testDecodingWithMissingType() {
        // Arrange: JSON with missing type
        let jsonString = """
        {
            "id": 1,
            "properties": { "padding": 8.0 }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        // Act & Assert: Expect decoding failure
        XCTAssertThrowsError(
            try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData),
            "Should throw error for missing type"
        ) { error in
            XCTAssertTrue(error is DecodingError, "Error should be DecodingError")
        }
    }
    
    func testDecodingFromDictionaryWithInvalidChild() throws {
        // Arrange: Dictionary with invalid content
        let dictionary: [String: Any] = [
            "id": 1,
            "type": "NavigationStack",
            "properties": ["title": "Home"],
            "content": ["invalid"]
        ]
        
        // Act
        let element = try ActionUIElement(from: dictionary, logger: logger)
        
        // Assert: Verify content is not set due to invalid data
        XCTAssertEqual(element.id, 1, "ID should be 1")
        XCTAssertEqual(element.type, "NavigationStack", "Type should be NavigationStack")
        XCTAssertEqual(element.properties["title"] as? String, "Home", "Title should be Home")
        XCTAssertNil(element.subviews, "Subviews should be nil")
        XCTAssertNil(element.subviews?["content"], "Content should be nil due to invalid data")
    }
    
    // MARK: - findElement(by:) Tests
    
    func testFindElementByIDInRoot() throws {
        // Arrange: JSON with root element
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 1)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 1")
        XCTAssertEqual(found?.id, 1, "Found element should have ID 1")
        XCTAssertEqual(found?.type, "View", "Found element should have type View")
    }
    
    func testFindElementByIDInChildren() throws {
        // Arrange: JSON with children
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 },
            "children": [
                { "id": 2, "type": "Text", "properties": { "text": "Child1" } },
                { "id": 3, "type": "Button", "properties": { "title": "Click" } }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 3)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 3 in children")
        XCTAssertEqual(found?.id, 3, "Found element should have ID 3")
        XCTAssertEqual(found?.type, "Button", "Found element should have type Button")
    }
    
    func testFindElementByIDInRows() throws {
        // Arrange: JSON with rows
        let jsonString = """
        {
            "id": 1,
            "type": "Grid",
            "properties": { "spacing": 10.0 },
            "rows": [
                [
                    { "id": 2, "type": "Text", "properties": { "text": "Cell1" } },
                    { "id": 3, "type": "Button", "properties": { "title": "Click" } }
                ],
                [
                    { "id": 4, "type": "Text", "properties": { "text": "Cell2" } }
                ]
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 3)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 3 in rows")
        XCTAssertEqual(found?.id, 3, "Found element should have ID 3")
        XCTAssertEqual(found?.type, "Button", "Found element should have type Button")
    }
    
    func testFindElementByIDInContent() throws {
        // Arrange: JSON with content
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationStack",
            "properties": { "title": "Home" },
            "content": { "id": 2, "type": "Text", "properties": { "text": "Home" } }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 2)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 2 in content")
        XCTAssertEqual(found?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(found?.type, "Text", "Found element should have type Text")
    }
    
    func testFindElementByIDInDestination() throws {
        // Arrange: JSON with destination
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationLink",
            "properties": { "title": "Link" },
            "destination": { "id": 2, "type": "Text", "properties": { "text": "Detail" } }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 2)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 2 in destination")
        XCTAssertEqual(found?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(found?.type, "Text", "Found element should have type Text")
    }
    
    func testFindElementByIDInSidebar() throws {
        // Arrange: JSON with sidebar
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationSplitView",
            "properties": { "title": "Sidebar" },
            "sidebar": { "id": 2, "type": "Text", "properties": { "text": "Sidebar" } }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 2)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 2 in sidebar")
        XCTAssertEqual(found?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(found?.type, "Text", "Found element should have type Text")
    }
    
    func testFindElementByIDInDetail() throws {
        // Arrange: JSON with detail
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationSplitView",
            "properties": { "title": "Detail" },
            "detail": { "id": 2, "type": "Text", "properties": { "text": "Detail" } }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 2)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 2 in detail")
        XCTAssertEqual(found?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(found?.type, "Text", "Found element should have type Text")
    }
    
    func testFindElementByIDNestedDeeply() throws {
        // Arrange: JSON with nested structure
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationStack",
            "properties": { "title": "Home" },
            "content": {
                "id": 2,
                "type": "View",
                "properties": {},
                "children": [
                    {
                        "id": 3,
                        "type": "View",
                        "properties": {},
                        "children": [
                            { "id": 4, "type": "Text", "properties": { "text": "Deep" } }
                        ]
                    }
                ]
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 4)
        
        // Assert
        XCTAssertNotNil(found, "Should find element with ID 4 in nested children")
        XCTAssertEqual(found?.id, 4, "Found element should have ID 4")
        XCTAssertEqual(found?.type, "Text", "Found element should have type Text")
    }
    
    func testFindElementByIDNotFound() throws {
        // Arrange: JSON with children
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 },
            "children": [
                { "id": 2, "type": "Text", "properties": { "text": "Child1" } }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 999)
        
        // Assert
        XCTAssertNil(found, "Should return nil for non-existent ID")
    }
    
    func testFindElementByIDWithEmptySubviews() throws {
        // Arrange: JSON with no subviews
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": { "padding": 8.0 }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: jsonData)
        
        // Act
        let found = element.findElement(by: 2)
        
        // Assert
        XCTAssertNil(found, "Should return nil when subviews is empty")
    }
}
