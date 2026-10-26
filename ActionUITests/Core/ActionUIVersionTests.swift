// ActionUITests/Core/ActionUIVersionTests.swift
/*
 ActionUIVersion is "major.minor.patch", the form of the release tags (without their "v") and of
 the package manifests Scripts/set-version.sh keeps equal to it.
*/

import XCTest
@testable import ActionUI

final class ActionUIVersionTests: XCTestCase {
    func testTheVersionIsMajorMinorPatch() {
        let parts = ActionUIVersion.string.split(separator: ".", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 3, ActionUIVersion.string)
        for part in parts {
            XCTAssertFalse(part.isEmpty, ActionUIVersion.string)
            XCTAssertTrue(part.allSatisfy { ("0"..."9").contains($0) }, ActionUIVersion.string)
        }
    }
}
