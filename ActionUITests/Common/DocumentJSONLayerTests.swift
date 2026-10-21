// Tests/Common/DocumentJSONLayerTests.swift
/*
 The document paths that moved from JSONSerialization and PropertyListSerialization to JSONValue:
 a JSON or property-list document through the platform filter, and Map's coordinate text.
*/

import Foundation
import XCTest
@testable import ActionUI

@MainActor
final class DocumentJSONLayerTests: XCTestCase {
    private let model = ActionUIModel.shared

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        try await super.tearDown()
    }

    private func loadedText(_ data: Data, format: String) throws -> String? {
        let windowUUID = UUID().uuidString
        let root = try model.loadDescription(from: data, format: format, windowUUID: windowUUID)
        return model.windowModels[windowUUID]?.viewModels[root.id]?.properties["text"] as? String
    }

    // MARK: - Platform filter on a document

    func testJSONDocumentIsFiltered() throws {
        let json = #"{"id": 1, "type": "Text", "properties": {"text": "base", "text:apple": "apple", "text:android": "android", "count": 2.0, "ratio": 0.1}}"#
        XCTAssertEqual(try loadedText(Data(json.utf8), format: "json"), "apple")
    }

    func testPropertyListDocumentIsFiltered() throws {
        let document: [String: Any] = ["id": 1, "type": "Text", "properties": ["text": "base", "text:apple": "apple", "flag": true, "size": 1.5]]
        let data = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
        XCTAssertEqual(try loadedText(data, format: "plist"), "apple")
        let binary = try PropertyListSerialization.data(fromPropertyList: document, format: .binary, options: 0)
        XCTAssertEqual(try loadedText(binary, format: "plist"), "apple", "A binary property list loads too")
    }

    func testPropertyListWithADateIsRefusedWithAnError() throws {
        let document: [String: Any] = ["id": 1, "type": "Text", "properties": ["text": "a", "when": Date(timeIntervalSince1970: 0)]]
        let data = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
        XCTAssertThrowsError(try loadedText(data, format: "plist"), "ActionUI documents hold no dates; AnyCodable refuses them too")
    }

    func testMalformedJSONDocumentIsRefusedWithAnError() {
        XCTAssertThrowsError(try loadedText(Data(#"{"id": 1, "type": "Text""#.utf8), format: "json"))
    }

    // MARK: - Map coordinate text

    func testMapCoordinateText() throws {
        let serialize = try XCTUnwrap(Map.serializeValueToString)
        let logger = XCTestLogger(maxLevel: .warning)
        XCTAssertEqual(serialize(ActionUICoordinate(latitude: 37.7749, longitude: -122.4194), "json", logger),
                       #"{"latitude":37.7749,"longitude":-122.4194}"#)
        XCTAssertEqual(serialize(ActionUICoordinate(latitude: 0.1, longitude: 2), "json", logger),
                       #"{"latitude":0.1,"longitude":2}"#)

        let parse = try XCTUnwrap(Map.parseStringValue)
        XCTAssertEqual(parse(#"{"latitude":37,"longitude":-122.5}"#, "json", logger) as? ActionUICoordinate,
                       ActionUICoordinate(latitude: 37, longitude: -122.5), "An integral latitude is a number too")
        let quiet = SilentLogger()
        XCTAssertNil(parse(#"{"latitude":"north"}"#, "json", quiet))
        XCTAssertNil(parse("not json", "json", quiet))
        XCTAssertNil(parse(#"{"latitude":"inf","longitude":0}"#, "json", quiet), "A coordinate is a number, not the text inf")
    }

    // MARK: - Chart rows with null cells

    // insertElement(json:) and the adapters hand a chart description parsed by JSONValue, where a
    // null cell is ActionUIJSONNull, not NSNull.
    func testChartDataRowWithNullCellFromParsedJSON() throws {
        let parsed = try ActionUIJSON.value(from: #"{"columns":["a","b","c","d"],"data":[["x",null,1,true]]}"#)
        let description = try XCTUnwrap(parsed as? [String: Any])
        let cleaned = ChartDescription.parse(description, logger: nil).cleaned
        let rows = try XCTUnwrap(cleaned["data"] as? [Any], "A row with a null cell is a data row")
        XCTAssertEqual(ChartDescription.rowStrings(rows), [["x", "", "1", "true"]])
    }
}

private final class SilentLogger: ActionUILogger, @unchecked Sendable {
    func log(_ message: String, _ level: LoggerLevel) {}
}
