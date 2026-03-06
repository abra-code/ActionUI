// Tests/Views/LoadableViewTests.swift
/*
 LoadableViewTests.swift

 Tests for the LoadableView component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LoadableViewTests: XCTestCase {
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
    
    func testLoadableViewValidatePropertiesValid() {
        let properties: [String: Any] = [
            "url": "https://example.com/view.json"
        ]
        
        let validated = LoadableView.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["url"] as? String, "https://example.com/view.json", "url should be valid")
    }
    
    func testLoadableViewValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "url": 123
        ]
        
        let consoleLogger = ConsoleLogger()
        let validated = LoadableView.validateProperties(properties, consoleLogger)
        
        XCTAssertNil(validated["url"], "Invalid url should be nil")
    }
    
    func testLoadableViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "LoadableView",
            "properties": {
                "url": "https://example.com/view.json",
                "padding": 10.0
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
        
        // Verify element properties
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "LoadableView", "Element type should be LoadableView")
        XCTAssertEqual(element.properties["url"] as? String, "https://example.com/view.json", "url should be https://example.com/view.json")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        
        // Verify ViewModel setup
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? String, "https://example.com/view.json", "Initial viewModel value should be the URL string")
        
//        // Verify view construction
//        let validatedProperties = LoadableView.validateProperties(element.properties, logger)
//        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
//        XCTAssertTrue(view is SwiftUI.AnyView, "Built view should be wrapped in AnyView")
    }

    // MARK: - Sub-view replacement (dynamic content swapping) tests

    /// Helper: loads a root window with a LoadableView placeholder, then loads a sub-view JSON as its content.
    private func loadRootWithLoadableView() throws -> WindowModel {
        let rootJSON = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {},
            "children": [
                { "id": 100, "type": "LoadableView", "properties": { "filePath": "/tmp/panel.json" } }
            ]
        }
        """
        let data = rootJSON.data(using: .utf8)!
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        return ActionUIModel.shared.windowModels[windowUUID]!
    }

    /// Helper: creates sub-view JSON data with a given root id and child ids.
    private func subViewJSON(rootID: Int, childIDs: [Int]) -> Data {
        let children = childIDs.map { """
            { "id": \($0), "type": "Text", "properties": { "text": "child \($0)" } }
        """ }.joined(separator: ",\n")
        let json = """
        {
            "id": \(rootID),
            "type": "VStack",
            "properties": {},
            "children": [ \(children) ]
        }
        """
        return json.data(using: .utf8)!
    }

    func testFirstLoadWithParentIDRecordsOwnership() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201, 202])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        // Ownership should be recorded
        XCTAssertNotNil(windowModel.loadedSubViewIDs[parentID], "Should record child IDs under parentID")
        XCTAssertTrue(windowModel.loadedSubViewIDs[parentID]!.contains(200))
        XCTAssertTrue(windowModel.loadedSubViewIDs[parentID]!.contains(201))
        XCTAssertTrue(windowModel.loadedSubViewIDs[parentID]!.contains(202))

        // ViewModels should be populated
        XCTAssertNotNil(windowModel.viewModels[200])
        XCTAssertNotNil(windowModel.viewModels[201])
        XCTAssertNotNil(windowModel.viewModels[202])
    }

    func testReplaceRemovesOldChildModels() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // First load
        let subData1 = subViewJSON(rootID: 200, childIDs: [201, 202])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        XCTAssertNotNil(windowModel.viewModels[200])
        XCTAssertNotNil(windowModel.viewModels[201])

        // Replace with new content
        let subData2 = subViewJSON(rootID: 300, childIDs: [301])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)

        // Old models should be gone
        XCTAssertNil(windowModel.viewModels[200], "Old root sub-view model should be removed")
        XCTAssertNil(windowModel.viewModels[201], "Old child model should be removed")
        XCTAssertNil(windowModel.viewModels[202], "Old child model should be removed")

        // New models should be present
        XCTAssertNotNil(windowModel.viewModels[300], "New root sub-view model should be present")
        XCTAssertNotNil(windowModel.viewModels[301], "New child model should be present")

        // Ownership tracking updated
        XCTAssertEqual(windowModel.loadedSubViewIDs[parentID], Set([300, 301]))
    }

    func testIDReuseAcrossSwaps() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // First load with IDs 1001, 1002
        let subData1 = subViewJSON(rootID: 1001, childIDs: [1002])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        let oldViewModel = windowModel.viewModels[1001]
        XCTAssertNotNil(oldViewModel)

        // Replace reusing the same IDs — should not conflict
        let subData2 = subViewJSON(rootID: 1001, childIDs: [1002])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)

        // New ViewModels should be different instances
        let newViewModel = windowModel.viewModels[1001]
        XCTAssertNotNil(newViewModel)
        XCTAssertFalse(oldViewModel === newViewModel, "Reused IDs should get fresh ViewModel instances after swap")
    }

    func testNestedLoadableViewRecursiveCleanup() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentA = 100

        // Parent A loads child B (which is itself a LoadableView parent)
        let subDataA = subViewJSON(rootID: 500, childIDs: [501])
        _ = try windowModel.loadSubViewDescription(from: subDataA, format: "json", parentID: parentA)

        // Simulate child B (id=500) acting as a nested LoadableView that loaded its own children
        let parentB = 500
        let subDataB = subViewJSON(rootID: 600, childIDs: [601, 602])
        _ = try windowModel.loadSubViewDescription(from: subDataB, format: "json", parentID: parentB)

        // Verify nested state
        XCTAssertNotNil(windowModel.viewModels[600])
        XCTAssertNotNil(windowModel.viewModels[601])
        XCTAssertNotNil(windowModel.loadedSubViewIDs[parentB])

        // Now replace parent A — should recursively remove B's children too
        let subDataA2 = subViewJSON(rootID: 700, childIDs: [701])
        _ = try windowModel.loadSubViewDescription(from: subDataA2, format: "json", parentID: parentA)

        // All of A's old direct children and B's nested children should be gone
        XCTAssertNil(windowModel.viewModels[500], "Direct child of A should be removed")
        XCTAssertNil(windowModel.viewModels[501], "Direct child of A should be removed")
        XCTAssertNil(windowModel.viewModels[600], "Nested child of B should be removed")
        XCTAssertNil(windowModel.viewModels[601], "Nested child of B should be removed")
        XCTAssertNil(windowModel.viewModels[602], "Nested child of B should be removed")

        // B's ownership entry should also be cleaned up
        XCTAssertNil(windowModel.loadedSubViewIDs[parentB], "Nested parent's tracking should be removed")

        // New content should be present
        XCTAssertNotNil(windowModel.viewModels[700])
        XCTAssertNotNil(windowModel.viewModels[701])
    }

    func testFullWindowReloadClearsTracking() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // Load a sub-view with parentID tracking
        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)
        XCTAssertFalse(windowModel.loadedSubViewIDs.isEmpty, "Should have tracking entries")

        // Full window reload
        let rootJSON = """
        { "id": 1, "type": "Text", "properties": { "text": "fresh" } }
        """
        _ = try windowModel.loadDescription(from: rootJSON.data(using: .utf8)!, format: "json")

        XCTAssertTrue(windowModel.loadedSubViewIDs.isEmpty, "Full reload should clear all sub-view tracking")
    }

    func testParentIDZeroDoesNotTrack() throws {
        let windowModel = try loadRootWithLoadableView()

        // Load sub-view with default parentID=0 (backward-compatible path)
        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json")

        // No ownership tracking for parentID 0
        XCTAssertNil(windowModel.loadedSubViewIDs[0], "parentID 0 should not create tracking entries")

        // ViewModels should still be populated
        XCTAssertNotNil(windowModel.viewModels[200])
        XCTAssertNotNil(windowModel.viewModels[201])
    }

    func testRootViewModelsPreservedDuringSubViewReplace() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // Root viewModels (id 1 and 100) should exist
        XCTAssertNotNil(windowModel.viewModels[1], "Root VStack model should exist")
        XCTAssertNotNil(windowModel.viewModels[100], "LoadableView model should exist")

        // Load and replace sub-views
        let subData1 = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        let subData2 = subViewJSON(rootID: 300, childIDs: [301])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)

        // Root viewModels should be untouched
        XCTAssertNotNil(windowModel.viewModels[1], "Root VStack model should be preserved after sub-view swap")
        XCTAssertNotNil(windowModel.viewModels[100], "LoadableView model should be preserved after sub-view swap")
    }

    // MARK: - viewDidLoadActionID tests

    /// Helper: loads a root window with a LoadableView that has viewDidLoadActionID set.
    private func loadRootWithViewDidLoadAction() throws -> WindowModel {
        let rootJSON = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {},
            "children": [
                { "id": 100, "type": "LoadableView", "properties": { "filePath": "/tmp/panel.json", "viewDidLoadActionID": "params.loaded" } }
            ]
        }
        """
        let data = rootJSON.data(using: .utf8)!
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        return ActionUIModel.shared.windowModels[windowUUID]!
    }

    /// Tracks dedup state for simulateFireViewDidLoad, mirroring the static dict in FileLoadableView/RemoteLoadableView.
    private var simulatedLoadedSources: [String: String] = [:]

    /// Simulates the fireViewDidLoad logic used by FileLoadableView/RemoteLoadableView.
    /// This avoids needing SwiftUI view instantiation in unit tests.
    private func simulateFireViewDidLoad(parentID: Int, source: String, actionID: String) {
        guard !actionID.isEmpty else { return }
        guard ActionUIModel.shared.windowModels[windowUUID]?.viewModels[parentID] != nil else { return }

        let key = "\(windowUUID!)_\(parentID)"
        guard simulatedLoadedSources[key] != source else { return }
        simulatedLoadedSources[key] = source
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: parentID, viewPartID: 0)
    }

    func testViewDidLoadActionIDPropertyValidation() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let viewModel = windowModel.viewModels[100]!
        XCTAssertEqual(viewModel.validatedProperties["viewDidLoadActionID"] as? String, "params.loaded",
                       "viewDidLoadActionID should be preserved in validated properties")
    }

    func testViewDidLoadFiresOnFirstLoad() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        // Load sub-view content
        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        // Track action handler calls
        var firedActions: [(String, Int)] = []
        ActionUIModel.shared.setDefaultActionHandler { actionID, _, viewID, _, _ in
            firedActions.append((actionID, viewID))
        }

        // Simulate fireViewDidLoad
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")

        XCTAssertEqual(firedActions.count, 1, "Action should fire once")
        XCTAssertEqual(firedActions[0].0, "params.loaded", "Action ID should match")
        XCTAssertEqual(firedActions[0].1, parentID, "View ID should be the LoadableView's ID")
    }

    func testViewDidLoadDoesNotReFireForSameSource() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        var fireCount = 0
        ActionUIModel.shared.setDefaultActionHandler { _, _, _, _, _ in
            fireCount += 1
        }

        // First call should fire
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")
        XCTAssertEqual(fireCount, 1, "Should fire on first call")

        // Second call with same source should not fire (simulates SwiftUI body rebuild)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")
        XCTAssertEqual(fireCount, 1, "Should not re-fire for the same source")
    }

    func testViewDidLoadFiresAgainForNewSource() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        var firedSources: [String] = []
        ActionUIModel.shared.setDefaultActionHandler { actionID, _, _, _, _ in
            firedSources.append(actionID)
        }

        // First source
        let subData1 = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/brightness.json", actionID: "params.loaded")

        // Replace with new source
        let subData2 = subViewJSON(rootID: 300, childIDs: [301])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/contrast.json", actionID: "params.loaded")

        XCTAssertEqual(firedSources.count, 2, "Should fire for each new source")
    }

    func testViewDidLoadNotFiredWithoutActionID() throws {
        // Use the helper without viewDidLoadActionID
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        var fireCount = 0
        ActionUIModel.shared.setDefaultActionHandler { _, _, _, _, _ in
            fireCount += 1
        }

        // Empty actionID should not fire (mirrors nil viewDidLoadActionID in real code)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "")
        XCTAssertEqual(fireCount, 0, "Should not fire when actionID is empty")
    }

    func testFullReloadClearsViewModels() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        var fireCount = 0
        ActionUIModel.shared.setDefaultActionHandler { _, _, _, _, _ in
            fireCount += 1
        }

        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")
        XCTAssertEqual(fireCount, 1)

        // Full window reload should clear all ViewModels
        let rootJSON = """
        { "id": 1, "type": "Text", "properties": { "text": "fresh" } }
        """
        _ = try windowModel.loadDescription(from: rootJSON.data(using: .utf8)!, format: "json")

        XCTAssertNil(windowModel.viewModels[parentID], "Old LoadableView ViewModel should be gone after full reload")
    }
}
