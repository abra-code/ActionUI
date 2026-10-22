// Tests/Interop/MainLoopBridgeTests.swift
/*
 Tests for MainLoopBridge: main-actor work queued by DispatchQueue.main, by a main-actor Task and
 from another thread runs when the GLib main loop runs, and not before.
*/

import XCTest
import CAdwaita
import Dispatch
@testable import ActionUI

@MainActor
final class MainLoopBridgeTests: XCTestCase {

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    func testMainQueueWorkRunsInTheMainLoop() {
        let runs = CallCounter()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { runs.count += 1 }
        }
        XCTAssertEqual(runs.count, 0, "nothing runs the main queue until the main loop does")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { runs.count == 1 }))
    }

    func testAMainActorTaskRunsInTheMainLoop() {
        let runs = CallCounter()
        Task { @MainActor in runs.count += 1 }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { runs.count == 1 }))
    }

    func testWorkFromAnotherThreadRunsInTheMainLoop() {
        let runs = CallCounter()
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { runs.count += 1 }
            }
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { runs.count == 1 }))
    }

    func testDelayedMainQueueWorkRunsInTheMainLoop() {
        let runs = CallCounter()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
            MainActor.assumeIsolated { runs.count += 1 }
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { runs.count == 1 }))
    }
}
