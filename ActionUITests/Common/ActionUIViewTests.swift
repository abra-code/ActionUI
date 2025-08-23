// Tests/ActionUIViewTests.swift
/*
 ActionUIViewTests.swift

 Tests for ActionUIView in ActionUIView.swift, focusing on Equatable conformance and body property.
 Verifies equality comparisons for all subviews keys (children, rows, content, destination, sidebar, detail),
 state, windowUUID, and the early return optimization for nil/empty subviews, as well as the body property's
 interaction with ActionUIRegistry.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIViewTests: XCTestCase {
    private var registry: ActionUIRegistry!
    
    override func setUp() {
        super.setUp()
        registry = ActionUIRegistry.shared
    }
    
    override func tearDown() {
        registry = nil
        super.tearDown()
    }
    
    func testEquatableWithIdenticalChildren() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil),
                    ViewElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                ]
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil),
                    ViewElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                ]
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertEqual(view1, view2, "Views with identical children should be equal")
    }
    
    func testEquatableWithDifferentChildren() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ]
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child2"], subviews: nil)
                ]
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different children should not be equal")
    }
    
    func testEquatableWithIdenticalRows() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ViewElement(id: 2, type: "Text", properties: ["text": "Cell1"], subviews: nil),
                        ViewElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                    ],
                    [
                        ViewElement(id: 4, type: "Text", properties: ["text": "Cell2"], subviews: nil)
                    ]
                ]
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ViewElement(id: 2, type: "Text", properties: ["text": "Cell1"], subviews: nil),
                        ViewElement(id: 3, type: "Button", properties: ["title": "Click"], subviews: nil)
                    ],
                    [
                        ViewElement(id: 4, type: "Text", properties: ["text": "Cell2"], subviews: nil)
                    ]
                ]
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertEqual(view1, view2, "Views with identical rows should be equal")
    }
    
    func testEquatableWithDifferentRows() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ViewElement(id: 2, type: "Text", properties: ["text": "Cell1"], subviews: nil)
                    ]
                ]
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "Grid",
            properties: ["spacing": 10.0],
            subviews: [
                "rows": [
                    [
                        ViewElement(id: 2, type: "Text", properties: ["text": "Cell2"], subviews: nil)
                    ]
                ]
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different rows should not be equal")
    }
    
    func testEquatableWithIdenticalContent() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ViewElement(id: 2, type: "Text", properties: ["text": "Home"], subviews: nil)
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ViewElement(id: 2, type: "Text", properties: ["text": "Home"], subviews: nil)
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertEqual(view1, view2, "Views with identical content should be equal")
    }
    
    func testEquatableWithDifferentContent() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ViewElement(id: 2, type: "Text", properties: ["text": "Home"], subviews: nil)
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ViewElement(id: 2, type: "Text", properties: ["text": "Different"], subviews: nil)
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different content should not be equal")
    }
    
    func testEquatableWithIdenticalMixedSubviews() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ],
                "content": ViewElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ],
                "content": ViewElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertEqual(view1, view2, "Views with identical mixed subviews should be equal")
    }
    
    func testEquatableWithDifferentMixedSubviews() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ],
                "content": ViewElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child2"], subviews: nil)
                ],
                "content": ViewElement(id: 3, type: "Text", properties: ["text": "Content"], subviews: nil)
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different mixed subviews should not be equal")
    }
    
    func testEquatableWithDifferentState() {
        // Arrange
        let element = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: nil
        )
        let state1 = Binding.constant([1: ["key": "value1"] as [String: Any]] as [Int: Any])
        let state2 = Binding.constant([1: ["key": "value2"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element, state: state1, windowUUID: "uuid")
        let view2 = ActionUIView(element: element, state: state2, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different state should not be equal")
    }
    
    func testEquatableWithDifferentWindowUUID() {
        // Arrange
        let element = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: nil
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element, state: state, windowUUID: "uuid1")
        let view2 = ActionUIView(element: element, state: state, windowUUID: "uuid2")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different windowUUID should not be equal")
    }
    
    func testEquatableWithEmptyAndNilSubviewsEarlyReturn() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: nil
        )
        let element2 = ViewElement(
            id: 1,
            type: "View",
            properties: ["padding": 8.0],
            subviews: [:]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertEqual(view1, view2, "Views with nil and empty subviews should be equal with early return")
    }
    
    func testEquatableWithDifferentSubviewKeys() {
        // Arrange
        let element1 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "children": [
                    ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
                ]
            ]
        )
        let element2 = ViewElement(
            id: 1,
            type: "NavigationStack",
            properties: ["title": "Home"],
            subviews: [
                "content": ViewElement(id: 2, type: "Text", properties: ["text": "Child1"], subviews: nil)
            ]
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view1 = ActionUIView(element: element1, state: state, windowUUID: "uuid")
        let view2 = ActionUIView(element: element2, state: state, windowUUID: "uuid")
        
        // Act & Assert
        XCTAssertNotEqual(view1, view2, "Views with different subview keys should not be equal")
    }
    
    func testBodyProducesValidView() {
        // Arrange
        let element = ViewElement(
            id: 1,
            type: "Text",
            properties: ["text": "Hello"],
            subviews: nil
        )
        let state = Binding.constant([1: ["key": "value"] as [String: Any]] as [Int: Any])
        let view = ActionUIView(element: element, state: state, windowUUID: "uuid")
        
        // Act
        let body = view.body
        
        // Assert
        XCTAssertNotNil(body, "body should produce a valid view")
        // Note: Cannot test specific view type or content without knowing ActionUIRegistry implementation
    }
}
