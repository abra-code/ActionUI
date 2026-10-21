// Common/ActionUIJSONBridgedTests.swift
/*
 ActionUIJSON with Foundation objects, as the Apple adapters and the remote server pass them: an
 NSNumber, a CFBoolean or an NSNull reaches Core only after FoundationBridge. The portable
 ActionUIJSON tests are in Core/ActionUIJSONTests.swift.
*/

import XCTest
@testable import ActionUI

final class ActionUIJSONBridgedTests: XCTestCase {

    func testNumbersAfterFoundationBridge() throws {
        XCTAssertEqual(try ActionUIJSON.string(from: FoundationBridge.native(NSNumber(value: 12))), "12")
        XCTAssertThrowsError(try ActionUIJSON.string(from: NSNumber(value: 12)), "Core reads no NSNumber")
    }

    func testBoolsAfterFoundationBridge() throws {
        // A Bool from Objective-C is an NSNumber backed by CFBoolean; FoundationBridge makes it a Bool.
        let bridged: Any = NSNumber(value: true)
        XCTAssertEqual(try ActionUIJSON.string(from: FoundationBridge.native(bridged)), "true")
        XCTAssertEqual(try ActionUIJSON.string(from: FoundationBridge.native(kCFBooleanFalse as Any)), "false")
    }

    func testFoundationNullIsRefused() {
        XCTAssertThrowsError(try ActionUIJSON.string(from: NSNull())) { error in
            XCTAssertEqual((error as? ActionUIJSONError)?.message, "Cannot convert value of type NSNull to JSON")
        }
    }

    func testInsertPositionAfterFoundationBridge() throws {
        // An Objective-C or remote host's NSNumber, after FoundationBridge.
        let position = try ActionUIJSON.insertPosition(from: FoundationBridge.native(["kind": "at", "index": NSNumber(value: 3)]))
        guard case .at(3) = position else {
            return XCTFail("expected at(3), got \(position)")
        }
        // A bool NSNumber must not be taken for 1.
        XCTAssertThrowsError(try ActionUIJSON.insertPosition(from: FoundationBridge.native(["kind": "at", "index": NSNumber(value: true)])))
    }
}
