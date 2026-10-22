// Tests/Runtime/UpdateGuardTests.swift
/*
 Tests for UpdateGuard: updates nest, and the guard ends when an update throws. No display needed.
 (That signals are dropped during an update is in GtkInteropTests.)
*/

import XCTest
@testable import ActionUI

@MainActor
final class UpdateGuardTests: XCTestCase {

    func testUpdatesNest() {
        XCTAssertFalse(UpdateGuard.isApplying)
        UpdateGuard.applying {
            UpdateGuard.applying {
                XCTAssertTrue(UpdateGuard.isApplying)
            }
            XCTAssertTrue(UpdateGuard.isApplying, "the outer update is still running")
        }
        XCTAssertFalse(UpdateGuard.isApplying)
    }

    func testTheGuardEndsWhenTheUpdateThrows() {
        struct Failure: Error {}
        XCTAssertThrowsError(try UpdateGuard.applying { throw Failure() })
        XCTAssertFalse(UpdateGuard.isApplying)
    }
}
