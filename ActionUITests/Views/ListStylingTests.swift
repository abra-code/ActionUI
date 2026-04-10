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

    // MARK: - listStyle validation

    func testValidateProperties_listStylePlain_preserved() {
        let validated = List.validateProperties(["listStyle": "plain"], logger)
        XCTAssertEqual(validated["listStyle"] as? String, "plain")
    }

    func testValidateProperties_listStyleAutomatic_preserved() {
        let validated = List.validateProperties(["listStyle": "automatic"], logger)
        XCTAssertEqual(validated["listStyle"] as? String, "automatic")
    }

    func testValidateProperties_listStyleMissing_remainsNil() {
        let validated = List.validateProperties([:], logger)
        XCTAssertNil(validated["listStyle"])
    }

    func testValidateProperties_listStyleNonString_nilledOut() {
        let validated = List.validateProperties(["listStyle": 42], logger)
        XCTAssertNil(validated["listStyle"])
    }

    func testValidateProperties_listStyleUnknownValue_nilledOut() {
        let validated = List.validateProperties(["listStyle": "carousel"], logger)
        XCTAssertNil(validated["listStyle"])
    }

#if os(macOS)
    func testValidateProperties_listStylePlatformSpecific_macOS() {
        // inset and sidebar are valid on macOS
        XCTAssertEqual(List.validateProperties(["listStyle": "inset"],   logger)["listStyle"] as? String, "inset")
        XCTAssertEqual(List.validateProperties(["listStyle": "sidebar"], logger)["listStyle"] as? String, "sidebar")
        // insetGrouped and grouped are iOS-only — rejected on macOS
        XCTAssertNil(List.validateProperties(["listStyle": "insetGrouped"], logger)["listStyle"])
        XCTAssertNil(List.validateProperties(["listStyle": "grouped"],      logger)["listStyle"])
    }
#elseif os(iOS)
    func testValidateProperties_listStylePlatformSpecific_iOS() {
        // All six values are valid on iOS
        for style in ["automatic", "plain", "inset", "sidebar", "grouped", "insetGrouped"] {
            XCTAssertEqual(List.validateProperties(["listStyle": style], logger)["listStyle"] as? String, style,
                           "\(style) should be valid on iOS")
        }
    }
#endif

    // MARK: - listRowBackground validation

    func testValidateProperties_listRowBackground_validString_preserved() {
        let validated = List.validateProperties(["listRowBackground": "blue"], logger)
        XCTAssertEqual(validated["listRowBackground"] as? String, "blue")
    }

    func testValidateProperties_listRowBackground_hexString_preserved() {
        let validated = List.validateProperties(["listRowBackground": "#E8F4FD"], logger)
        XCTAssertEqual(validated["listRowBackground"] as? String, "#E8F4FD")
    }

    func testValidateProperties_listRowBackground_missingKey_remainsNil() {
        let validated = List.validateProperties([:], logger)
        XCTAssertNil(validated["listRowBackground"])
    }

    func testValidateProperties_listRowBackground_nonString_nilledOut() {
        let validated = List.validateProperties(["listRowBackground": 123], logger)
        XCTAssertNil(validated["listRowBackground"])
    }

    // MARK: - listRowSeparator validation

    func testValidateProperties_listRowSeparator_validValues_preserved() {
        for value in ["visible", "hidden", "automatic"] {
            let validated = List.validateProperties(["listRowSeparator": value], logger)
            XCTAssertEqual(validated["listRowSeparator"] as? String, value,
                           "\(value) should be preserved")
        }
    }

    func testValidateProperties_listRowSeparator_missingKey_remainsNil() {
        let validated = List.validateProperties([:], logger)
        XCTAssertNil(validated["listRowSeparator"])
    }

    func testValidateProperties_listRowSeparator_invalidValue_nilledOut() {
        let validated = List.validateProperties(["listRowSeparator": "always"], logger)
        XCTAssertNil(validated["listRowSeparator"])
    }

    func testValidateProperties_listRowSeparator_nonString_nilledOut() {
        let validated = List.validateProperties(["listRowSeparator": true], logger)
        XCTAssertNil(validated["listRowSeparator"])
    }

    // MARK: - listRowSeparatorTint validation

    func testValidateProperties_listRowSeparatorTint_validString_preserved() {
        let validated = List.validateProperties(["listRowSeparatorTint": "red"], logger)
        XCTAssertEqual(validated["listRowSeparatorTint"] as? String, "red")
    }

    func testValidateProperties_listRowSeparatorTint_missingKey_remainsNil() {
        let validated = List.validateProperties([:], logger)
        XCTAssertNil(validated["listRowSeparatorTint"])
    }

    func testValidateProperties_listRowSeparatorTint_nonString_nilledOut() {
        let validated = List.validateProperties(["listRowSeparatorTint": 0xFF0000], logger)
        XCTAssertNil(validated["listRowSeparatorTint"])
    }

    // MARK: - listRowInsets validation

    func testValidateProperties_listRowInsets_numberDouble_preserved() {
        let validated = List.validateProperties(["listRowInsets": 16.0], logger)
        XCTAssertNotNil(validated["listRowInsets"])
        XCTAssertEqual(validated["listRowInsets"] as? Double, 16.0)
    }

    func testValidateProperties_listRowInsets_numberInt_preserved() {
        let validated = List.validateProperties(["listRowInsets": 8], logger)
        XCTAssertNotNil(validated["listRowInsets"])
        XCTAssertEqual(validated["listRowInsets"] as? Int, 8)
    }

    func testValidateProperties_listRowInsets_dictionary_preserved() {
        let insetsDict: [String: Any] = ["top": 4.0, "leading": 16.0, "bottom": 4.0, "trailing": 16.0]
        let validated = List.validateProperties(["listRowInsets": insetsDict], logger)
        XCTAssertNotNil(validated["listRowInsets"])
        let result = validated["listRowInsets"] as? [String: Any]
        XCTAssertEqual(result?["top"] as? Double, 4.0)
        XCTAssertEqual(result?["leading"] as? Double, 16.0)
        XCTAssertEqual(result?["bottom"] as? Double, 4.0)
        XCTAssertEqual(result?["trailing"] as? Double, 16.0)
    }

    func testValidateProperties_listRowInsets_missingKey_remainsNil() {
        let validated = List.validateProperties([:], logger)
        XCTAssertNil(validated["listRowInsets"])
    }

    func testValidateProperties_listRowInsets_invalidType_nilledOut() {
        let validated = List.validateProperties(["listRowInsets": "wide"], logger)
        XCTAssertNil(validated["listRowInsets"])
    }

    // MARK: - Combined validation — all styling properties in one pass

    func testValidateProperties_allStylingProperties_preserved() {
        let properties: [String: Any] = [
            "listStyle": "plain",
            "listRowBackground": "mint",
            "listRowSeparator": "hidden",
            "listRowSeparatorTint": "gray",
            "listRowInsets": 12.0
        ]
        let validated = List.validateProperties(properties, logger)
        XCTAssertEqual(validated["listStyle"] as? String, "plain")
        XCTAssertEqual(validated["listRowBackground"] as? String, "mint")
        XCTAssertEqual(validated["listRowSeparator"] as? String, "hidden")
        XCTAssertEqual(validated["listRowSeparatorTint"] as? String, "gray")
        XCTAssertEqual(validated["listRowInsets"] as? Double, 12.0)
    }

    func testValidateProperties_existingPropertiesUnaffectedByStyling() {
        // Existing itemType and actionID validation should be unaffected when styling is also set
        let properties: [String: Any] = [
            "itemType": ["viewType": "Text"],
            "actionID": "list.sel",
            "listStyle": "plain",
            "listRowSeparator": "hidden"
        ]
        let validated = List.validateProperties(properties, logger)
        let itemType = validated["itemType"] as? [String: Any]
        XCTAssertEqual(itemType?["viewType"] as? String, "Text")
        XCTAssertEqual(validated["actionID"] as? String, "list.sel")
        XCTAssertEqual(validated["listStyle"] as? String, "plain")
        XCTAssertEqual(validated["listRowSeparator"] as? String, "hidden")
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
        let validated = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validated)
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
        let validated = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validated)
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
        let validated = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validated)
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
        let validated = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validated)
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
        let validated = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validated)
        XCTAssertFalse(view is SwiftUI.EmptyView, "Heterogeneous list with row styling should build successfully")
    }
}
