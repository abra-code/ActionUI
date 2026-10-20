import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class NavigationSplitViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
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
    // navigationSplitViewColumnWidth parsing
    // ────────────────────────────────────────────────
    func testNavigationSplitViewColumnWidthValidShorthand() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": 380
        ]
        XCTAssertEqual(BaseModifiers(props).columnWidth, .fixed(380.0))
    }

    func testNavigationSplitViewColumnWidthValidRange() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": [
                "ideal": 400,
                "min": 280,
                "max": 520
            ]
        ]
        XCTAssertEqual(BaseModifiers(props).columnWidth, .range(min: 280.0, ideal: 400.0, max: 520.0))
    }

    func testNavigationSplitViewColumnWidthMissingIdeal() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": ["min": 300, "max": 500]
        ]
        XCTAssertNil(BaseModifiers(props).columnWidth)
    }

    func testNavigationSplitViewColumnWidthInvalidType() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": "invalid"
        ]
        XCTAssertNil(BaseModifiers(props).columnWidth)
    }

    func testNavigationSplitViewColumnWidthNegativeValue() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": -100
        ]
        XCTAssertNil(BaseModifiers(props).columnWidth)
    }

    func testNavigationSplitViewColumnWidthZeroValue() throws {
        let props: [String: Any] = [
            "navigationSplitViewColumnWidth": 0
        ]
        XCTAssertNil(BaseModifiers(props).columnWidth)
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
        let properties = element.properties
        let viewModel = ViewModel()

        let view = NavigationSplitView.buildView(element, viewModel, windowUUID, properties, logger)
        XCTAssertNotNil(view, "View should build successfully")
    }

    // MARK: - Destination switching tests

    func testNavigationSplitViewWithDestinationsJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": {
                "type": "List",
                "id": 2,
                "properties": { "actionID": "sidebar.selection.changed" },
                "children": [
                    { "type": "Label", "id": 100, "properties": { "title": "Item A", "systemImage": "1.circle", "destinationViewId": 10 } },
                    { "type": "Label", "id": 101, "properties": { "title": "Item B", "systemImage": "2.circle", "destinationViewId": 11 } }
                ]
            },
            "detail": {
                "type": "Text", "id": 3, "properties": { "text": "Select an item" }
            },
            "destinations": [
                { "type": "Text", "id": 10, "properties": { "text": "Detail A" } },
                { "type": "Text", "id": 11, "properties": { "text": "Detail B" } }
            ],
            "properties": {
                "columnVisibility": "all"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "NavigationSplitView")

        // Sidebar
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase
        XCTAssertEqual((sidebar as? ActionUIElement)?.type, "List")
        XCTAssertEqual((sidebar as? ActionUIElement)?.id, 2)

        // Sidebar children
        let sidebarChildren = sidebar?.subviews?["children"] as? [any ActionUIElementBase]
        XCTAssertEqual(sidebarChildren?.count, 2)

        // Destinations
        let destinations = element.subviews?["destinations"] as? [any ActionUIElementBase]
        XCTAssertEqual(destinations?.count, 2)
        XCTAssertEqual((destinations?[0] as? ActionUIElement)?.id, 10)
        XCTAssertEqual((destinations?[1] as? ActionUIElement)?.id, 11)

        // ViewModels created for all elements
        XCTAssertNotNil(windowModel?.viewModels[1], "ViewModel for NavigationSplitView")
        XCTAssertNotNil(windowModel?.viewModels[2], "ViewModel for sidebar List")
        XCTAssertNotNil(windowModel?.viewModels[100], "ViewModel for child 100")
        XCTAssertNotNil(windowModel?.viewModels[101], "ViewModel for child 101")
        XCTAssertNotNil(windowModel?.viewModels[10], "ViewModel for destination 10")
        XCTAssertNotNil(windowModel?.viewModels[11], "ViewModel for destination 11")
    }

    func testNavigationSplitViewDestinationMaps() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": {
                "type": "List",
                "id": 2,
                "properties": { "actionID": "sidebar.selection" },
                "children": [
                    { "type": "Label", "id": 100, "properties": { "title": "A", "systemImage": "a.circle", "destinationViewId": 10 } }
                ]
            },
            "detail": { "type": "Text", "id": 3, "properties": { "text": "Default" } },
            "destinations": [
                { "type": "Text", "id": 10, "properties": { "text": "Dest A" } }
            ],
            "properties": {}
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Initially no destination is selected
        XCTAssertNil(viewModel.states["selectedDestination"], "selectedDestination should be nil initially")
    }

    func testNavigationSplitViewBuildViewWithDestinations() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": [
                "type": "List",
                "id": 2,
                "properties": ["actionID": "sidebar.selection"],
                "children": [
                    ["type": "Label", "id": 100, "properties": ["title": "A", "systemImage": "a.circle", "destinationViewId": 10]]
                ]
            ],
            "detail": [
                "type": "Text", "id": 3, "properties": ["text": "Default"]
            ],
            "destinations": [
                ["type": "Text", "id": 10, "properties": ["text": "Dest A"]]
            ],
            "properties": ["columnVisibility": "all"]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let storedProperties = ActionUIRegistry.shared.currentProperties(element: element, model: viewModel)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: storedProperties)
        XCTAssertNotNil(view, "buildView should succeed with destinations")
    }

    func testNavigationSplitViewNonListSidebarWarning() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": [
                "type": "VStack",
                "id": 2,
                "properties": [:],
                "children": [
                    ["type": "Text", "id": 100, "properties": ["text": "Item A"]]
                ]
            ],
            "detail": [
                "type": "Text", "id": 3, "properties": ["text": "Default"]
            ],
            "destinations": [
                ["type": "Text", "id": 10, "properties": ["text": "Dest A"]]
            ],
            "properties": [:]
        ]

        // Use ConsoleLogger to avoid test failure from warnings
        let consoleLogger = ConsoleLogger()
        ActionUIModel.shared.logger = consoleLogger

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let storedProperties = ActionUIRegistry.shared.currentProperties(element: element, model: viewModel)

        // buildView should log warning about non-List sidebar but still succeed
        let view = NavigationSplitView.buildView(element, viewModel, windowUUID, storedProperties, consoleLogger)
        XCTAssertNotNil(view, "buildView should succeed even with non-List sidebar")

        // Verify sidebar type is VStack (not List)
        let sidebar = element.subviews?["sidebar"] as? any ActionUIElementBase
        XCTAssertEqual((sidebar as? ActionUIElement)?.type, "VStack", "Sidebar should be VStack")
    }

    func testNavigationSplitViewPropsColumnVisibilityInvalid() throws {
        let properties: [String: Any] = ["columnVisibility": "invalid"]
        let props = NavigationSplitView.Props(properties)
        XCTAssertEqual(props.columnVisibility, .all, "Invalid columnVisibility should default to 'all'")
    }

    func testNavigationSplitViewPropsStyleInvalid() throws {
        let properties: [String: Any] = ["style": "invalid"]
        let props = NavigationSplitView.Props(properties)
        XCTAssertEqual(props.style, .automatic, "Invalid style should default to 'automatic'")
    }

    // ────────────────────────────────────────────────
    // columnVisibility property seeds the columnVisibility state
    // ────────────────────────────────────────────────

    /// Loads a two-column split view whose properties are `propertiesJSON` and returns its
    /// columnVisibility state.
    private func loadedColumnVisibility(_ propertiesJSON: String) throws -> String? {
        let jsonString = """
        {
            "id": 1,
            "type": "NavigationSplitView",
            "sidebar": {"type": "Text", "id": 2, "properties": {"text": "Sidebar"}},
            "detail": {"type": "Text", "id": 3, "properties": {"text": "Detail"}},
            "properties": \(propertiesJSON)
        }
        """
        _ = try ActionUIModel.shared.loadDescription(from: Data(jsonString.utf8), format: "json", windowUUID: windowUUID)
        return ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 1, key: "columnVisibility") as? String
    }

    func testColumnVisibilityPropertySeedsTheState() throws {
        XCTAssertEqual(try loadedColumnVisibility(#"{"columnVisibility": "detail"}"#), "detail")
    }

    func testEveryColumnVisibilityNameSeedsTheState() throws {
        for name in ["automatic", "all", "doubleColumn", "detail"] {
            ActionUIModel.resetForTesting()
            windowUUID = UUID().uuidString
            XCTAssertEqual(try loadedColumnVisibility(#"{"columnVisibility": "\#(name)"}"#), name)
        }
    }

    func testColumnVisibilityStateDefaultsToAll() throws {
        XCTAssertEqual(try loadedColumnVisibility("{}"), "all")
    }

    func testInvalidColumnVisibilityPropertySeedsAll() throws {
        XCTAssertEqual(try loadedColumnVisibility(#"{"columnVisibility": "sideways"}"#), "all")
    }
}
