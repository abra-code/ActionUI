// Tests/Views/ListStylingTests.swift
/*
 ListStylingTests.swift

 Tests for List styling properties: listStyle, listRowBackground,
 listRowSeparator, listRowSeparatorTint, listRowInsets.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ListStylingTests: XCTestCase {
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

    // MARK: - listStyle

    func testProps_listStylePlain_preserved() {
        let props = List.Props(["listStyle": "plain"])
        XCTAssertEqual(props.listStyle, .plain)
    }

    func testProps_listStyleAutomatic_preserved() {
        let props = List.Props(["listStyle": "automatic"])
        XCTAssertEqual(props.listStyle, .automatic)
    }

    func testProps_listStyleMissing_remainsNil() {
        let props = List.Props([:])
        XCTAssertNil(props.listStyle)
    }

    func testProps_listStyleNonString_ignored() {
        let props = List.Props(["listStyle": 42])
        XCTAssertNil(props.listStyle)
    }

    func testProps_listStyleUnknownValue_ignored() {
        let props = List.Props(["listStyle": "carousel"])
        XCTAssertNil(props.listStyle)
    }

#if os(macOS)
    func testProps_listStylePlatformSpecific_macOS() {
        // inset and sidebar are valid on macOS
        XCTAssertEqual(List.Props(["listStyle": "inset"]).listStyle, .inset)
        XCTAssertEqual(List.Props(["listStyle": "sidebar"]).listStyle, .sidebar)
        // insetGrouped and grouped are iOS-only: read on every platform, and the renderer
        // applies no style for them on macOS
        XCTAssertEqual(List.Props(["listStyle": "insetGrouped"]).listStyle, .insetGrouped)
        XCTAssertEqual(List.Props(["listStyle": "grouped"]).listStyle, .grouped)
    }
#elseif os(iOS)
    func testProps_listStylePlatformSpecific_iOS() {
        // All six values are valid on iOS
        for style in ["automatic", "plain", "inset", "sidebar", "grouped", "insetGrouped"] {
            XCTAssertEqual(List.Props(["listStyle": style]).listStyle?.rawValue, style,
                           "\(style) should be valid on iOS")
        }
    }
#endif

    // MARK: - listRowBackground

    func testProps_listRowBackground_validString_preserved() {
        let props = List.Props(["listRowBackground": "blue"])
        XCTAssertEqual(props.rowBackground, "blue")
    }

    func testProps_listRowBackground_hexString_preserved() {
        let props = List.Props(["listRowBackground": "#E8F4FD"])
        XCTAssertEqual(props.rowBackground, "#E8F4FD")
    }

    func testProps_listRowBackground_missingKey_remainsNil() {
        let props = List.Props([:])
        XCTAssertNil(props.rowBackground)
    }

    func testProps_listRowBackground_nonString_ignored() {
        let props = List.Props(["listRowBackground": 123])
        XCTAssertNil(props.rowBackground)
    }

    // MARK: - listRowSeparator

    func testProps_listRowSeparator_validValues_preserved() {
        for value in ["visible", "hidden", "automatic"] {
            let props = List.Props(["listRowSeparator": value])
            XCTAssertEqual(props.rowSeparator?.rawValue, value,
                           "\(value) should be preserved")
        }
    }

    func testProps_listRowSeparator_missingKey_remainsNil() {
        let props = List.Props([:])
        XCTAssertNil(props.rowSeparator)
    }

    func testProps_listRowSeparator_invalidValue_ignored() {
        let props = List.Props(["listRowSeparator": "always"])
        XCTAssertNil(props.rowSeparator)
    }

    func testProps_listRowSeparator_nonString_ignored() {
        let props = List.Props(["listRowSeparator": true])
        XCTAssertNil(props.rowSeparator)
    }

    // MARK: - listRowSeparatorTint

    func testProps_listRowSeparatorTint_validString_preserved() {
        let props = List.Props(["listRowSeparatorTint": "red"])
        XCTAssertEqual(props.rowSeparatorTint, "red")
    }

    func testProps_listRowSeparatorTint_missingKey_remainsNil() {
        let props = List.Props([:])
        XCTAssertNil(props.rowSeparatorTint)
    }

    func testProps_listRowSeparatorTint_nonString_ignored() {
        let props = List.Props(["listRowSeparatorTint": 0xFF0000])
        XCTAssertNil(props.rowSeparatorTint)
    }

    // MARK: - listRowInsets

    func testProps_listRowInsets_numberDouble_preserved() {
        let props = List.Props(["listRowInsets": 16.0])
        XCTAssertNotNil(props.rowInsets)
        XCTAssertEqual(props.rowInsets, .uniform(16.0))
    }

    func testProps_listRowInsets_numberInt_preserved() {
        let props = List.Props(["listRowInsets": 8])
        XCTAssertNotNil(props.rowInsets)
        XCTAssertEqual(props.rowInsets, .uniform(8.0))
    }

    func testProps_listRowInsets_dictionary_preserved() {
        let insetsDict: [String: Any] = ["top": 4.0, "leading": 16.0, "bottom": 4.0, "trailing": 16.0]
        let props = List.Props(["listRowInsets": insetsDict])
        XCTAssertNotNil(props.rowInsets)
        XCTAssertEqual(props.rowInsets, .edges(top: 4.0, leading: 16.0, bottom: 4.0, trailing: 16.0))
    }

    func testProps_listRowInsets_missingKey_remainsNil() {
        let props = List.Props([:])
        XCTAssertNil(props.rowInsets)
    }

    func testProps_listRowInsets_invalidType_ignored() {
        let props = List.Props(["listRowInsets": "wide"])
        XCTAssertNil(props.rowInsets)
    }

    // MARK: - Combined Props - all styling properties in one pass

    func testProps_allStylingProperties_preserved() {
        let properties: [String: Any] = [
            "listStyle": "plain",
            "listRowBackground": "mint",
            "listRowSeparator": "hidden",
            "listRowSeparatorTint": "gray",
            "listRowInsets": 12.0
        ]
        let props = List.Props(properties)
        XCTAssertEqual(props.listStyle, .plain)
        XCTAssertEqual(props.rowBackground, "mint")
        XCTAssertEqual(props.rowSeparator, .hidden)
        XCTAssertEqual(props.rowSeparatorTint, "gray")
        XCTAssertEqual(props.rowInsets, .uniform(12.0))
    }

    func testProps_existingPropertiesUnaffectedByStyling() {
        // Existing itemType and actionID parsing should be unaffected when styling is also set
        let properties: [String: Any] = [
            "itemType": ["viewType": "Text"],
            "actionID": "list.sel",
            "listStyle": "plain",
            "listRowSeparator": "hidden"
        ]
        let props = List.Props(properties)
        XCTAssertEqual(props.viewType, .text)
        XCTAssertEqual(props.actionID, "list.sel")
        XCTAssertEqual(props.listStyle, .plain)
        XCTAssertEqual(props.rowSeparator, .hidden)
    }

    // MARK: - buildView with styling properties

    func testBuildView_withListStyleAndRowBackground_succeeds() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "List",
            "properties": [
                "listStyle": "plain",
                "listRowBackground": "mint",
                "listRowSeparator": "hidden",
                "listRowInsets": 12.0
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("ViewModel not found"); return
        }
        viewModel.states["content"] = [["Alpha"], ["Beta"], ["Gamma"]]
        let properties = element.properties
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertFalse(view is SwiftUI.EmptyView, "buildView should succeed with row styling properties")
    }

    func testBuildView_withRowInsetsDictionary_succeeds() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "List",
            "properties": [
                "listRowInsets": ["top": 8.0, "leading": 20.0, "bottom": 8.0, "trailing": 20.0]
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("ViewModel not found"); return
        }
        viewModel.states["content"] = [["Row 1"], ["Row 2"]]
        let properties = element.properties
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    func testBuildView_withNoStylingProperties_succeeds() throws {
        // Baseline: no styling properties — should behave identically to pre-feature behavior
        let elementDict: [String: Any] = [
            "id": 3,
            "type": "List",
            "properties": [
                "itemType": ["viewType": "Text"],
                "actionID": "list.sel"
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("ViewModel not found"); return
        }
        viewModel.states["content"] = [["Item A"], ["Item B"]]
        let properties = element.properties
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    func testBuildView_templateMode_withRowStyling_succeeds() throws {
        let elementDict: [String: Any] = [
            "id": 4,
            "type": "List",
            "properties": [
                "listStyle": "plain",
                "listRowSeparator": "hidden",
                "listRowBackground": "orange"
            ],
            "template": [
                "type": "Label",
                "properties": ["title": "$2", "systemImage": "$1"]
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("ViewModel not found"); return
        }
        viewModel.states["content"] = [
            ["star.fill", "Favorites"],
            ["heart.fill", "Liked"]
        ]
        let properties = element.properties
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertFalse(view is SwiftUI.EmptyView, "Template list with row styling should build successfully")
    }

    func testBuildView_heterogeneousMode_withRowStyling_succeeds() throws {
        let elementDict: [String: Any] = [
            "id": 5,
            "type": "List",
            "properties": [
                "listStyle": "plain",
                "listRowSeparator": "hidden",
                "listRowInsets": 8.0
            ],
            "children": [
                ["type": "Text", "id": 50, "properties": ["text": "Row A"]],
                ["type": "Text", "id": 51, "properties": ["text": "Row B"]]
            ]
        ]
        let element = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id] else {
            XCTFail("ViewModel not found"); return
        }
        let properties = element.properties
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertFalse(view is SwiftUI.EmptyView, "Heterogeneous list with row styling should build successfully")
    }
}
