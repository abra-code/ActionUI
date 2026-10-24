// Core/TypelessElementTests.swift
/*
 Tests for elements whose type is given only for other platforms: after PlatformFilter such an
 element has no type, and loading skips it (in a child list, a grid row and a single subview)
 instead of failing the document, from JSON, a property list and a dictionary, and in an inserted
 element (which itself still needs a type). A document whose root has no type still fails.
*/

import XCTest
@testable import ActionUI
import Foundation

@MainActor
final class TypelessElementTests: XCTestCase {
    private var logger: XCTestLogger!

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        logger = XCTestLogger(maxLevel: .verbose)
    }

    /// No platform these tests run on is watchOS, so "type:watchos" leaves no type.
    private static let document: [String: Any] = [
        "type": "VStack", "id": 1,
        "children": [
            ["type": "Text", "id": 2],
            ["type:watchos": "Table", "id": 3],
            ["type": "Text", "id": 4],
        ],
        "background": ["type:watchos": "Color", "id": 5],
        "overlay": ["type": "Text", "id": 6],
    ]

    private static let grid: [String: Any] = [
        "type": "Grid", "id": 10,
        "rows": [[["type": "Text", "id": 11], ["type:watchos": "Text", "id": 12]]],
    ]

    private func check(_ element: ActionUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let children = element.subviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(children?.map(\.id), [2, 4], "the child with no type here is skipped", file: file, line: line)
        XCTAssertNil(element.subviews?["background"], "a single subview with no type here is left unset", file: file, line: line)
        XCTAssertEqual((element.subviews?["overlay"] as? ActionUIElement)?.id, 6, file: file, line: line)
    }

    func testJSONSkipsAnElementWithNoTypeHere() throws {
        let model = WindowModel(windowUUID: "typeless-json", logger: logger)
        let data = try JSONSerialization.data(withJSONObject: Self.document)
        check(try model.loadDescription(from: data, format: "json"))
        XCTAssertNil(model.viewModels[3], "no view model for the skipped element")
        XCTAssertNotNil(model.viewModels[4])
    }

    func testAPropertyListSkipsAnElementWithNoTypeHere() throws {
        let model = WindowModel(windowUUID: "typeless-plist", logger: logger)
        let data = try PropertyListSerialization.data(fromPropertyList: Self.document, format: .binary, options: 0)
        check(try model.loadDescription(from: data, format: "plist"))
    }

    func testADictionarySkipsAnElementWithNoTypeHere() throws {
        let model = WindowModel(windowUUID: "typeless-dictionary", logger: logger)
        check(try model.loadDescription(from: Self.document))
    }

    func testAGridRowSkipsACellWithNoTypeHere() throws {
        let fromJSON = try WindowModel(windowUUID: "typeless-grid-json", logger: logger)
            .loadDescription(from: JSONSerialization.data(withJSONObject: Self.grid), format: "json")
        XCTAssertEqual((fromJSON.subviews?["rows"] as? [[ActionUIElement]])?.map { $0.map(\.id) }, [[11]])
        let fromDictionary = try WindowModel(windowUUID: "typeless-grid-dictionary", logger: logger).loadDescription(from: Self.grid)
        XCTAssertEqual((fromDictionary.subviews?["rows"] as? [[ActionUIElement]])?.map { $0.map(\.id) }, [[11]])
    }

    func testAnInsertedElementWithNoTypeHereIsRefusedAndItsChildIsSkipped() throws {
        let uuid = "typeless-insert"
        _ = try ActionUIModel.shared.loadDescription(from: ["type": "VStack", "id": 1], windowUUID: uuid)
        defer { ActionUIModel.shared.windowModels[uuid] = nil }
        XCTAssertThrowsError(try ActionUIModel.shared.insertElement(windowUUID: uuid, parentID: 1, dict: ["type:watchos": "Text", "id": 2]),
                             "the inserted element itself needs a type")
        XCTAssertEqual(try ActionUIModel.shared.insertElement(windowUUID: uuid, parentID: 1, dict: [
            "type": "VStack", "id": 3, "children": [["type:watchos": "Text", "id": 4], ["type": "Text", "id": 5]],
        ]), 3)
        let inserted = try XCTUnwrap(ActionUIModel.shared.windowModels[uuid]?.viewModels[3])
        XCTAssertNotNil(inserted)
        XCTAssertNil(ActionUIModel.shared.windowModels[uuid]?.viewModels[4], "its child with no type is skipped")
        XCTAssertNotNil(ActionUIModel.shared.windowModels[uuid]?.viewModels[5])
    }

    func testARootWithNoTypeHereStillFails() throws {
        let root: [String: Any] = ["type:watchos": "Text", "id": 1]
        let model = WindowModel(windowUUID: "typeless-root", logger: logger)
        XCTAssertThrowsError(try model.loadDescription(from: JSONSerialization.data(withJSONObject: root), format: "json"))
        XCTAssertThrowsError(try model.loadDescription(from: root))
    }
}
