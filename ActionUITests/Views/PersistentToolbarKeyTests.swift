// Tests/Views/PersistentToolbarKeyTests.swift
/*
 PersistentToolbarKeyTests.swift

 Tests for the "persistentToolbar" subview key (Missing_Features #36): a navigation
 container's toolbar, whose items stay in the bar on every screen inside that container.

 These cover the parse and model layers. The UI tests in ActionUITestAppUITests cover what
 the user sees, but they are slow, Apple-only, and cannot tell the two failure modes apart:
 a persistent item that renders nothing because the renderer skipped it looks exactly like
 one that renders nothing because no ViewModel was ever registered for it. That second mode
 is the one this file is really here for - see testPersistentToolbarItemsAreRegistered.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class PersistentToolbarKeyTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    /// Captures log messages by level, so the deprecation warning can be asserted rather
    /// than merely believed. XCTestLogger turns error-level logs into failures instead.
    private final class CapturingLogger: ActionUILogger, @unchecked Sendable {
        private(set) var warnings: [String] = []
        func log(_ message: String, _ level: LoggerLevel) {
            switch level {
            case .warning: warnings.append(message)
            // Do not swallow errors just because this logger is here to read warnings - a decode
            // or registration failure during one of these loads would otherwise be invisible and
            // the test would go on to assert about a document that never loaded.
            case .error: XCTFail("unexpected error-level log: \(message)")
            default: break
            }
        }
    }

    /// A NavigationStack carrying a persistent item (60/61), the deprecated container-level
    /// alias (10/11), a root-screen toolbar (20/21) and one destination (500).
    private let fixtureJSON = """
    {
      "id": 1,
      "type": "NavigationStack",
      "properties": {},
      "persistentToolbar": [
        {
          "id": 60,
          "type": "ToolbarItem",
          "properties": { "placement": "topBarTrailing" },
          "content": { "id": 61, "type": "Button", "properties": { "title": "PERSISTBAR", "actionID": "t.persist" } }
        }
      ],
      "toolbar": [
        {
          "id": 10,
          "type": "ToolbarItem",
          "properties": { "placement": "automatic" },
          "content": { "id": 11, "type": "Button", "properties": { "title": "STACKBAR", "actionID": "t.stack" } }
        }
      ],
      "content": {
        "id": 2,
        "type": "VStack",
        "properties": { "navigationTitle": "Root" },
        "children": [ { "id": 3, "type": "Text", "properties": { "text": "root body" } } ],
        "toolbar": [
          {
            "id": 20,
            "type": "ToolbarItem",
            "properties": { "placement": "automatic" },
            "content": { "id": 21, "type": "Button", "properties": { "title": "ROOTBAR", "actionID": "t.root" } }
          }
        ]
      },
      "destinations": [
        { "id": 500, "type": "VStack", "properties": { "navigationTitle": "Dest" },
          "children": [ { "id": 501, "type": "Text", "properties": { "text": "dest body" } } ] }
      ]
    }
    """

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        // Put the shared logger back. Three tests here swap in a CapturingLogger, which now fails
        // on error-level logs - leaving it installed would let a later test's error be reported
        // against this class, or worse, against whichever test happened to be running.
        ActionUIModel.shared.logger = logger
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // MARK: - Decoding

    func testPersistentToolbarDecodesFromJSON() throws {
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(fixtureJSON.utf8))

        guard let items = element.subviews?["persistentToolbar"] as? [any ActionUIElementBase] else {
            XCTFail("persistentToolbar should decode into subviews as an element array")
            return
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, 60)
        XCTAssertEqual(items[0].type, "ToolbarItem")
        XCTAssertEqual(items[0].properties["placement"] as? String, "topBarTrailing")

        let content = items[0].subviews?["content"] as? (any ActionUIElementBase)
        XCTAssertEqual(content?.id, 61, "the item's content element should decode with it")

        // It is a SEPARATE key, not a rename: a container may carry both while documents migrate.
        let aliased = element.subviews?["toolbar"] as? [any ActionUIElementBase]
        XCTAssertEqual(aliased?.count, 1, "the container's own toolbar should still decode alongside it")
        XCTAssertEqual(aliased?[0].id, 10)
    }

    /// The dictionary initializer is a second, hand-written decode path (used by the adapters),
    /// and it enumerates its array keys separately from Codable. A key added to one and not the
    /// other decodes from a file but vanishes when the same document arrives as a dictionary.
    func testPersistentToolbarDecodesFromDictionary() throws {
        let dict: [String: Any] = [
            "id": 1,
            "type": "NavigationStack",
            "properties": [:],
            "persistentToolbar": [
                [
                    "id": 60,
                    "type": "ToolbarItem",
                    "properties": ["placement": "primaryAction"],
                    "content": ["id": 61, "type": "Button", "properties": ["title": "PERSISTBAR"]]
                ]
            ],
            "content": ["id": 2, "type": "VStack", "properties": [:]]
        ]

        let element = try ActionUIElement(from: dict, logger: logger)
        let items = element.subviews?["persistentToolbar"] as? [any ActionUIElementBase]
        XCTAssertEqual(items?.count, 1, "persistentToolbar should decode from a dictionary too")
        XCTAssertEqual(items?[0].id, 60)
    }

    func testPersistentToolbarRoundTripsThroughEncoding() throws {
        let original = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(fixtureJSON.utf8))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: try encoder.encode(original))

        guard let items = decoded.subviews?["persistentToolbar"] as? [any ActionUIElementBase] else {
            XCTFail("persistentToolbar should survive an encode/decode round trip")
            return
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, 60)
        XCTAssertEqual(items[0].properties["placement"] as? String, "topBarTrailing")
        XCTAssertEqual((items[0].subviews?["content"] as? (any ActionUIElementBase))?.id, 61)
    }

    // MARK: - Model registration

    /// The failure this file exists for.
    ///
    /// Every renderer resolves a toolbar item through the window's ViewModel pool, which is
    /// populated by walking ActionUISubviewContainers.arrayKeys. Leave a new array key out of
    /// that list and the items still decode, still appear in the element tree, and still look
    /// right in every parse-level test - but they have no ViewModel, so they render nothing
    /// and setElementProperty on their ids is a silent no-op. The whole feature fails without
    /// a single error being logged. That is exactly what this asserts against.
    func testPersistentToolbarItemsAreRegistered() throws {
        _ = try ActionUIModel.shared.loadDescription(from: Data(fixtureJSON.utf8), format: "json", windowUUID: windowUUID)

        guard let viewModels = ActionUIModel.shared.windowModels[windowUUID]?.viewModels else {
            XCTFail("window model should exist after loadDescription")
            return
        }
        XCTAssertNotNil(viewModels[60], "the persistent ToolbarItem needs a ViewModel or it renders nothing")
        XCTAssertNotNil(viewModels[61], "the item's content needs one too - that is what actually draws")
        XCTAssertEqual(viewModels[60]?.elementType, "ToolbarItem")
        XCTAssertEqual(viewModels[61]?.elementType, "Button")

        // Placement is read from the ViewModel's validated properties at render time,
        // falling back to the raw property; validation has to have run for the first path.
        XCTAssertEqual(viewModels[60]?.validatedProperties["placement"] as? String, "topBarTrailing")
    }

    func testPersistentToolbarItemsAreFoundInTheElementTree() throws {
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(fixtureJSON.utf8))

        XCTAssertEqual(element.findElement(by: 60)?.type, "ToolbarItem",
                       "the shared descendant walk should reach persistent items")
        XCTAssertEqual(element.findElement(by: 61)?.type, "Button")
    }

    // MARK: - The deprecated alias

    func testPersistentItemsIncludeTheContainerToolbarAlias() throws {
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(fixtureJSON.utf8))

        let items = ToolbarHelper.persistentToolbarItems(of: element)
        XCTAssertEqual(items.map { $0.id }.sorted(), [10, 60],
                       "a container's own toolbar is the deprecated spelling of persistentToolbar, so both are persistent")

        // The root screen's toolbar is NOT part of this - it belongs to one screen.
        XCTAssertFalse(items.contains { $0.id == 20 })
    }

    func testPersistentItemsAreEmptyWhenNeitherKeyIsDeclared() throws {
        let json = """
        { "id": 1, "type": "NavigationStack", "content": { "id": 2, "type": "VStack", "properties": {} } }
        """
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(json.utf8))
        XCTAssertTrue(ToolbarHelper.persistentToolbarItems(of: element).isEmpty)
    }

    /// The gate that keeps the same array from being applied twice.
    ///
    /// `View.applyModifiers` applies an element's `toolbar` as that screen's toolbar, and a
    /// navigation container has to be excluded: its builder already applies the same items where
    /// the platform needs them, so applying them here too puts them in the macOS window toolbar
    /// twice. Only a macOS UI run can see that duplication on screen, which is why the rule is a
    /// function with a test rather than an inline condition - this fails on every platform.
    func testAContainerToolbarIsNotAlsoAScreenToolbar() throws {
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(fixtureJSON.utf8))

        XCTAssertTrue(ToolbarHelper.screenToolbarItems(of: element).isEmpty,
                      "a NavigationStack's own toolbar is the container's, applied by its builder - not this screen's")

        // The same array is still persistent, so it is applied exactly once, elsewhere.
        XCTAssertEqual(ToolbarHelper.persistentToolbarItems(of: element).map { $0.id }.sorted(), [10, 60])
    }

    func testAnOrdinaryViewsToolbarIsStillItsOwn() throws {
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(fixtureJSON.utf8))
        guard let content = element.subviews?["content"] as? (any ActionUIElementBase) else {
            XCTFail("fixture should have a content element"); return
        }

        XCTAssertEqual(ToolbarHelper.screenToolbarItems(of: content).map { $0.id }, [20],
                       "the root VStack's toolbar is a screen toolbar and must keep being applied normally")
    }

    func testNavigationContainersAreRecognized() {
        XCTAssertTrue(ToolbarHelper.isNavigationContainer("NavigationStack"))
        XCTAssertTrue(ToolbarHelper.isNavigationContainer("NavigationSplitView"))
        // The gate that keeps View.swift applying a screen's own toolbar the way it always has.
        XCTAssertFalse(ToolbarHelper.isNavigationContainer("VStack"))
        XCTAssertFalse(ToolbarHelper.isNavigationContainer("List"))
        XCTAssertFalse(ToolbarHelper.isNavigationContainer("NavigationLink"))
    }

    func testContainerToolbarLogsADeprecationWarning() throws {
        let capturing = CapturingLogger()
        ActionUIModel.shared.logger = capturing

        _ = try ActionUIModel.shared.loadDescription(from: Data(fixtureJSON.utf8), format: "json", windowUUID: windowUUID)

        let deprecations = capturing.warnings.filter { $0.contains("persistentToolbar") }
        XCTAssertEqual(deprecations.count, 1, "exactly one warning, naming the element: \(capturing.warnings)")
        XCTAssertTrue(deprecations.first?.contains("NavigationStack") == true,
                      "the warning should name the element type so the author can find it")
        XCTAssertTrue(deprecations.first?.contains("id 1") == true,
                      "and its id: \(deprecations.first ?? "")")
    }

    /// The opposite mistake to the alias, and the one that would otherwise be silent: only a
    /// navigation container reads the key, so anywhere else the items decode, get ViewModels, and
    /// render nothing at all. The verifier catches it at author time; this catches it at runtime.
    func testPersistentToolbarOnANonContainerWarns() throws {
        let json = """
        {
          "id": 1,
          "type": "NavigationStack",
          "content": {
            "id": 2,
            "type": "VStack",
            "properties": {},
            "persistentToolbar": [
              { "id": 70, "type": "ToolbarItem", "properties": {},
                "content": { "id": 71, "type": "Button", "properties": { "title": "NOPE" } } }
            ]
          }
        }
        """
        let capturing = CapturingLogger()
        ActionUIModel.shared.logger = capturing

        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)

        let ignored = capturing.warnings.filter { $0.contains("is ignored") }
        XCTAssertEqual(ignored.count, 1, "expected one warning naming the misplaced key: \(capturing.warnings)")
        XCTAssertTrue(ignored.first?.contains("VStack") == true,
                      "the warning should name the element that carries it: \(ignored.first ?? "")")
    }

    func testAScreenToolbarDoesNotWarn() throws {
        let json = """
        {
          "id": 1,
          "type": "NavigationStack",
          "content": {
            "id": 2,
            "type": "VStack",
            "properties": {},
            "toolbar": [
              { "id": 20, "type": "ToolbarItem", "properties": {},
                "content": { "id": 21, "type": "Button", "properties": { "title": "ROOTBAR" } } }
            ]
          }
        }
        """
        let capturing = CapturingLogger()
        ActionUIModel.shared.logger = capturing

        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)

        XCTAssertTrue(capturing.warnings.filter { $0.contains("persistentToolbar") }.isEmpty,
                      "a toolbar on an ordinary view is still an ordinary screen toolbar: \(capturing.warnings)")
    }
}
