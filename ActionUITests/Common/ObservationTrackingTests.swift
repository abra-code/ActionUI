// Common/ObservationTrackingTests.swift
/*
 Every host mutation must change a property that a rendering view reads, or the view never
 renders again. ActionUIView reads all of its model's tracked properties (ViewModel.trackAllChanges),
 a container reads its model's dynamicSubviews, and WindowModalView reads the window's modal,
 dialog and toast. These tests read the same properties inside withObservationTracking, make one
 mutation through ActionUIModel, and expect the change notification SwiftUI would receive.
*/

import XCTest
import SwiftUI
import Observation
@testable import ActionUI

/// A template element that keeps the row's throw-away model and reads its value while building, as
/// TextField and Slider do.
private struct RowModelCapture: ActionUIViewConstruction {
    @MainActor static var captured: ViewModel?
    static var valueType: Any.Type = String.self
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, model, _, _, _ in
        captured = model
        return SwiftUI.Text(model.value as? String ?? "")
    }
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
}

@MainActor
final class ObservationTrackingTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    private let model = ActionUIModel.shared

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        model.logger = logger
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

    private func load(_ dict: [String: Any]) throws -> WindowModel {
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)
        return try XCTUnwrap(model.windowModels[windowUUID])
    }

    /// Fails unless `mutate` changes something `read` read.
    private func expectChange(_ what: String, read: () -> Void, mutate: () throws -> Void) rethrows {
        let changed = expectation(description: what)
        changed.assertForOverFulfill = false
        withObservationTracking(read, onChange: { changed.fulfill() })
        try mutate()
        // onChange runs synchronously inside the mutation.
        wait(for: [changed], timeout: 1.0)
    }

    private let toggle: [String: Any] = ["id": 1, "type": "Toggle", "properties": ["actionID": "toggle.A", "value": false]]

    // MARK: - What ActionUIView reads

    func testSetElementPropertyChangesTheProperties() throws {
        let viewModel = try XCTUnwrap(load(toggle).viewModels[1])
        try expectChange("properties", read: { _ = viewModel.properties }) {
            model.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "actionID", value: "toggle.B")
        }
    }

    func testSetElementPropertyChangesWhatActionUIViewReads() throws {
        let viewModel = try XCTUnwrap(load(toggle).viewModels[1])
        try expectChange("trackAllChanges", read: { viewModel.trackAllChanges() }) {
            model.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "actionID", value: "toggle.B")
        }
    }

    func testSetElementValueChangesWhatActionUIViewReads() throws {
        let viewModel = try XCTUnwrap(load(toggle).viewModels[1])
        try expectChange("value", read: { viewModel.trackAllChanges() }) {
            model.setElementValue(windowUUID: windowUUID, viewID: 1, value: true)
        }
    }

    func testSetElementStateChangesWhatActionUIViewReads() throws {
        let viewModel = try XCTUnwrap(load(toggle).viewModels[1])
        try expectChange("states", read: { viewModel.trackAllChanges() }) {
            model.setElementState(windowUUID: windowUUID, viewID: 1, key: "custom", value: 3)
        }
    }

    // MARK: - What a container reads

    func testInsertElementChangesTheParentsDynamicSubviews() throws {
        let windowModel = try load(["id": 1, "type": "VStack", "properties": [:]])
        let parent = try XCTUnwrap(windowModel.viewModels[1])
        try expectChange("dynamicSubviews", read: { _ = parent.dynamicSubviews }) {
            _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: ["id": 10, "type": "Text", "properties": ["text": "new"]])
        }
    }

    func testRemoveElementChangesTheParentsDynamicSubviews() throws {
        let windowModel = try load(["id": 1, "type": "VStack", "properties": [:],
                                    "children": [["id": 10, "type": "Text", "properties": ["text": "old"]]]])
        let parent = try XCTUnwrap(windowModel.viewModels[1])
        try expectChange("dynamicSubviews", read: { _ = parent.dynamicSubviews }) {
            try model.removeElement(windowUUID: windowUUID, viewID: 10)
        }
    }

    // MARK: - What WindowModalView reads

    func testPresentModalChangesTheWindowModal() throws {
        let windowModel = try load(toggle)
        let modalJSON = Data(#"{ "id": 100, "type": "Text", "properties": { "text": "Modal" } }"#.utf8)
        try expectChange("windowModal", read: { _ = windowModel.windowModal }) {
            try model.presentModal(windowUUID: windowUUID, data: modalJSON, format: "json", style: .sheet)
        }
    }

    func testPresentAlertChangesTheWindowDialog() throws {
        let windowModel = try load(toggle)
        expectChange("windowDialog", read: { _ = windowModel.windowDialog }) {
            model.presentAlert(windowUUID: windowUUID, title: "Info")
        }
    }

    func testPresentToastChangesTheWindowToast() throws {
        let windowModel = try load(toggle)
        expectChange("windowToast", read: { _ = windowModel.windowToast }) {
            model.presentToast(windowUUID: windowUUID, message: "Hi")
        }
    }

    // MARK: - What is not observed

    func testReadsInsideUntrackedReadsAreNotTracked() throws {
        let viewModel = try XCTUnwrap(load(toggle).viewModels[1])
        let changed = expectation(description: "no change")
        changed.isInverted = true
        withObservationTracking({ UntrackedReads.perform { viewModel.trackAllChanges() } }, onChange: { changed.fulfill() })
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "custom", value: 3)
        model.setElementValue(windowUUID: windowUUID, viewID: 1, value: true)
        wait(for: [changed], timeout: 0.2)
        XCTAssertFalse(UntrackedReads.isActive)
    }

    func testLoadingADescriptionInsideATrackedScopeTracksNoReadOfTheNewModels() throws {
        let changed = expectation(description: "no change")
        changed.isInverted = true
        var windowModel: WindowModel?
        withObservationTracking({
            _ = try? model.loadDescription(from: [
                "type": "List", "id": 7, "template": ["type": "Text", "properties": ["text": "Row $1"]],
            ], windowUUID: windowUUID)
            windowModel = model.windowModels[windowUUID]
        }, onChange: { changed.fulfill() })
        model.setElementRows(windowUUID: windowUUID, viewID: 7, rows: [["a"]])
        wait(for: [changed], timeout: 0.2)
        XCTAssertNotNil(windowModel?.viewModels[7])
    }

    func testAWriteToATemplateRowsModelDoesNotRenderTheContainerAgain() throws {
        ActionUIRegistry.shared.register(RowModelCapture.self, as: "RowModelCapture")
        RowModelCapture.captured = nil
        let windowModel = try load(["type": "List", "id": 7, "template": ["type": "RowModelCapture", "properties": ["text": "$1"]]])
        model.setElementRows(windowUUID: windowUUID, viewID: 7, rows: [["a"]])
        let element = try XCTUnwrap(windowModel.element)
        let listModel = try XCTUnwrap(windowModel.viewModels[7])
        let changed = expectation(description: "no change")
        changed.isInverted = true
        withObservationTracking({
            _ = ActionUIView(element: element, model: listModel, windowUUID: windowUUID).body
        }, onChange: { changed.fulfill() })
        // What a TextField or Slider in the row does when the user edits it.
        try XCTUnwrap(RowModelCapture.captured).value = "typed"
        wait(for: [changed], timeout: 0.2)
    }

    func testAContainersReadOfItsChildrensPropertiesIsNotTracked() throws {
        // A List maps its children to destinations by reading their properties while it renders;
        // a later change to a child's properties must not render the List again.
        let windowModel = try load(["id": 1, "type": "List", "properties": [:], "children": [
            ["id": 10, "type": "Text", "properties": ["text": "a", "destinationViewId": 100]],
        ]])
        let children = try XCTUnwrap(windowModel.element?.subviews?["children"] as? [any ActionUIElementBase])
        let changed = expectation(description: "no change")
        changed.isInverted = true
        withObservationTracking({
            _ = RowSelection.buildIDMaps(children: children, windowModel: windowModel)
        }, onChange: { changed.fulfill() })
        model.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "destinationViewId", value: 200)
        wait(for: [changed], timeout: 0.2)
    }

    func testAChartCacheWriteChangesNothingTracked() throws {
        let viewModel = try XCTUnwrap(load(toggle).viewModels[1])
        let changed = expectation(description: "no change")
        changed.isInverted = true
        withObservationTracking({ viewModel.trackAllChanges() }, onChange: { changed.fulfill() })
        viewModel.elementCache = NSObject()
        viewModel.elementType = "Other"
        wait(for: [changed], timeout: 0.2)
    }
}
