// Core/LockTests.swift
/*
 Tests for Lock, the pthread mutex Core uses for state more than one thread touches: it returns
 the body's value, passes a thrown error on and unlocks, and keeps the updates of two threads whole.
*/

import XCTest
@testable import ActionUI

final class LockTests: XCTestCase {

    func testReturnsTheBodysValue() {
        let lock = Lock()
        XCTAssertEqual(lock.withLock { 6 * 7 }, 42)
    }

    func testAThrownErrorIsPassedOnAndTheLockIsReleased() {
        struct Failure: Error {}
        let lock = Lock()
        XCTAssertThrowsError(try lock.withLock { throw Failure() }) { error in
            XCTAssertTrue(error is Failure)
        }
        // Taken again: the throw unlocked it (a lock still held would never return here).
        XCTAssertEqual(lock.withLock { "again" }, "again")
    }

    func testTwoThreadsIncrementingUnderTheLockLoseNoIncrements() async {
        final class Counter: @unchecked Sendable {
            let lock = Lock()
            var value = 0
        }
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    for _ in 0..<100_000 {
                        counter.lock.withLock { counter.value += 1 }
                    }
                }
            }
        }
        XCTAssertEqual(counter.value, 200_000)
    }
}
