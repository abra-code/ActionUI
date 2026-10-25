// Tests/Runtime/AreaPresenceTests.swift
/*
 Tests for AreaPresence, which NodeHover and NodeDrop report through: entering an area reports
 present on the next turn; moving from one area to another within a turn reports nothing; leaving
 the last reports not present; an unpaired leave or a repeated enter reports nothing more.
*/

import XCTest
@testable import ActionUI

@MainActor
final class AreaPresenceTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    func testThePresenceIsReportedOncePerChange() {
        var reports: [Bool] = []
        let presence = AreaPresence { reports.append($0) }
        presence.left(0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(reports, [], "a leave without an enter changes nothing")
        presence.entered(0)
        XCTAssertEqual(reports, [], "on the next turn")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(reports, [true])
        // From the frame onto the overlay: a leave and an enter in one turn.
        presence.left(0)
        presence.entered(1)
        presence.entered(1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(reports, [true])
        presence.left(1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(reports, [true, false])
        // In and out within one turn: nothing.
        presence.entered(0)
        presence.left(0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(reports, [true, false])
    }
}
