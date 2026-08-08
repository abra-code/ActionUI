// SplitPersistentToolbarTests.swift
//
// The NavigationSplitView half of the Missing_Features #36 measurement. It began as a
// discovery run that reported through XCTFail; now that the behaviour is known it asserts
// it, so the suite stays green and a future change to these semantics goes red.
//
// Fixture: Resources/NavigationSplitView.persistentToolbar.json, which mirrors the shape
// SharedCare's derived wide shell actually uses (SharedCare-wide.json): a
// NavigationSplitView whose sidebar is a List carrying the toolbar, and whose detail is an
// INNER NavigationStack with its own root content and pushed destinations.
//
//   SPLITBAR       on the NavigationSplitView element
//   SIDEBARBAR     on the sidebar List          <- where SharedCare's real sync indicator lives
//   DETAILROOTBAR  on the detail stack's root
//   INNERDESTBAR   on a destination of the inner stack
//
// The question it answers: when the INNER stack pushes, which toolbar items survive? That is the
// wide-shell equivalent of what PersistentToolbarTests measured for the narrow shell.
//
// MEASURED 2026-08-08 on macOS 26:
//
//   detail-root   present=[SPLITBAR SIDEBARBAR DETAILROOTBAR]  absent=[INNERDESTBAR]
//   pushed-inner  present=[SPLITBAR SIDEBARBAR INNERDESTBAR]   absent=[DETAILROOTBAR]
//
// SPLITBAR and SIDEBARBAR both SURVIVE the inner push; only the detail stack's own root bar
// is replaced. Both live in the one window toolbar the split view's columns share, and the
// sidebar stays mounted. The consequence for SharedCare: its wide shell authors the sync
// indicator on the sidebar List, so on macOS that indicator is ALREADY persistent, and #36
// does not affect the wide shell at all.
//
// iPad is NOT covered. The multi-scene harness opens the fixture as a 320pt side-by-side
// scene, where SwiftUI collapses NavigationSplitView to a single stack with the sidebar as
// root - so there is no detail column to push into and the run measures compact width, not
// wide. Closing the selector scene first would fix it. Left undone deliberately: SharedCare
// runs the NARROW shell on iPad (App/apple/DateHelpers.swift gates the wide shell on
// `#if os(macOS)` alone), so this is a framework-completeness gap, not a product one.
//
// UI automation is exclusive. Clicking in the app during a run corrupts it, and the
// corruption reads as a contradictory result rather than an error.

import XCTest

final class SplitPersistentToolbarTests: XCTestCase {
    private let fixtureResource = "NavigationSplitView.persistentToolbar"
    private let rootTitle = "ToolbarDetailRoot"
    private let watched = ["SPLITBAR", "SIDEBARBAR", "DETAILROOTBAR", "INNERDESTBAR"]

    private var app: XCUIApplication!
    private var documentWindowID = ""

    private var screen: XCUIElement {
        #if os(macOS)
        return app.windows.matching(NSPredicate(format: "identifier == %@", documentWindowID)).firstMatch
        #else
        return app
        #endif
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if os(macOS)
        continueAfterFailure = true
        app = XCUIApplication()
        // NOT -resetAppState: WindowGroup(for: WindowIdentifier.self) renders an EmptyView
        // while that flag is set, so the fixture would open as a blank window.
        // ApplePersistenceIgnoreState stops macOS restoring documents from an earlier run,
        // which is what makes the uniqueness check below trustworthy.
        app.launchArguments = ["-openResource", fixtureResource, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        Thread.sleep(forTimeInterval: 5)

        // Bind by the fixture's OWN root title rather than "any window that is not the
        // selector", which would happily latch onto a restored window from another fixture.
        let matches = app.windows.allElementsBoundByIndex.filter { $0.title == rootTitle }
        guard matches.count == 1, let document = matches.first else {
            XCTFail("expected exactly one \(rootTitle) window, found \(matches.count). "
                    + "Windows: \(app.windows.allElementsBoundByIndex.map { $0.title })")
            return
        }
        documentWindowID = document.identifier
        #else
        // Only macOS is covered. A compact-width scene collapses NavigationSplitView to a
        // single stack with the sidebar as root, so there is no detail column to push into -
        // the run would measure compact width, not wide, and would then fail confusingly on
        // a missing PUSH_INNER rather than skipping. See the header for the iPad detail.
        throw XCTSkip("NavigationSplitView toolbar persistence is only measured on macOS - see header")
        #endif
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func press(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    /// Wait until `title` is the screen actually on show, rather than sleeping and hoping.
    /// A bare sleep let the sibling test report a pushed destination's buttons while the
    /// window was still titled with the previous screen.
    @discardableResult
    private func settle(on title: String) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if screen.title == title { Thread.sleep(forTimeInterval: 2); return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// Sample every watched element once, before judging any of them.
    ///
    /// `present` is checked against the window TOOLBAR, not the whole window: the claim being
    /// pinned is that these items live in the shared window toolbar, and a plain
    /// `buttons[title].exists` would pass just as well if they rendered as an inline banner
    /// in the body. `absent` stays window-wide, so "does not appear" keeps meaning nowhere.
    private func assertBars(_ state: String, present: [String], absent: [String]) {
        var inBar: [String: Bool] = [:]
        var anywhere: [String: Bool] = [:]
        for title in present { inBar[title] = screen.toolbars.buttons[title].exists }
        for title in absent { anywhere[title] = screen.buttons[title].exists }

        let context = "[\(state)] toolbar: " + screen.toolbars.buttons.allElementsBoundByIndex
            .map { $0.label.isEmpty ? $0.identifier : $0.label }
            .filter { !$0.hasPrefix("_XCUI:") }.description
        for title in present {
            XCTAssertTrue(inBar[title] == true, "expected \(title) in the window toolbar. \(context)")
        }
        for title in absent {
            XCTAssertFalse(anywhere[title] == true, "expected \(title) NOT on screen. \(context)")
        }
    }

    func testToolbarPersistenceAcrossAnInnerPush() {
        let pushInner = screen.buttons["PUSH_INNER"]
        XCTAssertTrue(pushInner.waitForExistence(timeout: 20),
                      "split fixture never loaded. Tree: \(app.debugDescription)")
        XCTAssertTrue(settle(on: "ToolbarDetailRoot"), "detail root never became the top screen")

        assertBars("detail-root",
                   present: ["SPLITBAR", "SIDEBARBAR", "DETAILROOTBAR"],
                   absent: ["INNERDESTBAR"])

        press(pushInner)
        XCTAssertTrue(screen.staticTexts["inner dest body"].waitForExistence(timeout: 10),
                      "inner push to destination 500 did not happen")
        XCTAssertTrue(settle(on: "ToolbarInnerDest"), "destination 500 never became the top screen")

        // The result this file exists for: the split-element toolbar AND the sidebar's both
        // survive the inner push, because the columns share one window toolbar and the
        // sidebar never unmounts. Only the detail stack's own root bar is replaced.
        assertBars("pushed-inner",
                   present: ["SPLITBAR", "SIDEBARBAR", "INNERDESTBAR"],
                   absent: ["DETAILROOTBAR"])
    }
}
