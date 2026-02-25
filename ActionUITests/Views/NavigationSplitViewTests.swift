import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class NavigationSplitViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
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
    
    func testNavigationSplitViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": {"type": "Text", "id": 2, "properties": {"text": "Sidebar"}},
            "content": {"type": "Text", "id": 3, "properties": {"text": "Content"}},
            "detail": {"type": "Text", "id": 4, "properties": {"text": "Detail"}},
            "properties": {
                "columnVisibility": "all",
                "style": "balanced"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase
        let content = element.subviews?["content"] as? any ActionUIElementBase
        let detail  = element.subviews?["detail"]  as? any ActionUIElementBase
        
        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "NavigationSplitView")
        XCTAssertEqual((sidebar as? ActionUIElement)?.type, "Text")
        XCTAssertEqual((sidebar as? ActionUIElement)?.id, 2)
        XCTAssertEqual((content as? ActionUIElement)?.type, "Text")
        XCTAssertEqual((content as? ActionUIElement)?.id, 3)
        XCTAssertEqual((detail as? ActionUIElement)?.type, "Text")
        XCTAssertEqual((detail as? ActionUIElement)?.id, 4)
        XCTAssertEqual(element.properties["columnVisibility"] as? String, "all")
        XCTAssertEqual(element.properties["style"] as? String, "balanced")
    }
    
    // ────────────────────────────────────────────────
    // navigationSplitViewColumnWidth validation
    // ────────────────────────────────────────────────
    func testValidateNavigationSplitViewColumnWidthValidShorthand() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": 380
        ]
        let validated = NavigationSplitView.validateProperties(props, logger)
        let value = validated.cgFloat(forKey: "navigationSplitViewColumnWidth") ?? 0.0
        XCTAssertEqual(value, 380.0, accuracy: 0.0000001)
    }

    func testValidateNavigationSplitViewColumnWidthValidRange() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": [
                "ideal": 400,
                "min": 280,
                "max": 520
            ]
        ]
        let validated = NavigationSplitView.validateProperties(props, logger)
        let dict = validated["navigationSplitViewColumnWidth"] as? [String: Any]
        XCTAssertNotNil(dict)
        
        let idealNum = dict?.cgFloat(forKey:"ideal") ?? 0.0
        XCTAssertEqual(idealNum, 400.0, accuracy: 0.0000001)
 
        let minNum = dict?.cgFloat(forKey:"min") ?? 0.0
        XCTAssertEqual(minNum, 280.0, accuracy: 0.0000001)

        let maxNum = dict?.cgFloat(forKey:"max") ?? 0.0
        XCTAssertEqual(maxNum, 520.0, accuracy: 0.0000001)
    }

    func testValidateNavigationSplitViewColumnWidthMissingIdeal() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": ["min": 300, "max": 500]
        ]
        let validated = ActionUIRegistry.shared.validateProperties(
                forElementType: "NavigationSplitView",
                properties: props)
        XCTAssertNil(validated["navigationSplitViewColumnWidth"])
    }

    func testValidateNavigationSplitViewColumnWidthInvalidType() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": "invalid"
        ]
        let validated = ActionUIRegistry.shared.validateProperties(
                forElementType: "NavigationSplitView",
                properties: props)
        XCTAssertNil(validated["navigationSplitViewColumnWidth"])
    }

    func testValidateNavigationSplitViewColumnWidthNegativeValue() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": -100
        ]
        let validated = ActionUIRegistry.shared.validateProperties(
                forElementType: "NavigationSplitView",
                properties: props)
        XCTAssertNil(validated["navigationSplitViewColumnWidth"])
    }

    func testValidateNavigationSplitViewColumnWidthZeroValue() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": 0
        ]
        let validated = ActionUIRegistry.shared.validateProperties(
                forElementType: "NavigationSplitView",
                properties: props)
        XCTAssertNil(validated["navigationSplitViewColumnWidth"])
    }
    
    // Optional: test construction still succeeds with width constraints
    func testBuildViewWithColumnWidth() throws {
        let elementDict: [String: Any] = [
            "type": "NavigationSplitView",
            "sidebar": [
                "type": "Text",
                "properties": [
                    "text": "Sidebar",
                    "navigationSplitViewColumnWidth": ["ideal": 340, "min": 280]
                ]
            ],
            "detail": [
                "type": "Text",
                "properties": ["text": "Detail"]
            ],
            "properties": ["columnVisibility": "all"]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validated = ActionUIRegistry.shared.validateProperties(
                                                    forElementType: element.type,
                                                    properties: element.properties)
        let viewModel = ViewModel()
        
        let view = NavigationSplitView.buildView(element, viewModel, windowUUID, validated, logger)
        XCTAssertNotNil(view, "View should build successfully")
    }
}
