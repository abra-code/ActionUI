// SplitPersistentToolbarTests.swift
//
// The NavigationSplitView half of `persistentToolbar` (Missing_Features #36). It began as a
// discovery run that reported through XCTFail; it now asserts the behavior, so the suite
// stays green and a future change to these semantics goes red.
//
// Fixture: Resources/NavigationSplitView.persistentToolbar.json, which mirrors the shape
// SharedCare's derived wide shell actually uses (SharedCare-wide.json): a
// NavigationSplitView whose sidebar is a List carrying the toolbar, and whose detail is an
// INNER NavigationStack with its own root content and pushed destinations.
//
//   SPERS    in the NavigationSplitView's `persistentToolbar`  -> the feature
//   SALIAS   in the NavigationSplitView's `toolbar`            -> the DEPRECATED ALIAS
//   SIDE     on the sidebar List          <- where SharedCare's real sync indicator lives
//   DROOT    on the detail stack's root
//   DINNER   on a destination of the inner stack
//
// Labels are short so the same fixture fits an iPhone bar for the compact-width sibling,
// CompactSplitPersistentToolbarTests - see the note on bar space in PersistentToolbarTests.
//
// The question it answers: when the INNER stack pushes, which toolbar items survive? That is the
// wide-shell equivalent of what PersistentToolbarTests covers for the narrow shell.
//
//   detail-root   present=[SPERS SALIAS SIDE DROOT]   absent=[DINNER]
//   pushed-inner  present=[SPERS SALIAS SIDE DINNER]  absent=[DROOT]
//
// SALIAS and SIDE were both MEASURED surviving the inner push on macOS 26 on
// 2026-08-08, before `persistentToolbar` existed: they live in the one window toolbar the
// split view's columns share, and the sidebar never unmounts. Two consequences worth
// keeping straight. SharedCare's wide shell authors the sync indicator on the sidebar List,
// so on macOS that indicator was ALREADY persistent and #36 never affected the wide shell.
// And on this platform the new key changes nothing observable - SPERS is asserted
// here so that the key is proven wired on macOS too, not because macOS was broken.
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
    private let rootTitle = "TBDetail"
    /// The split view's container-level items: the real key and its deprecated alias.
    private let containerBars = ["SPERS", "SALIAS"]

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
        // This file measures the WIDE shell, which needs a real detail column to push into.
        // A compact-width scene collapses NavigationSplitView into a single stack rooted at the
        // sidebar, so there is nothing here to drive; that half is measured separately by
        // CompactSplitPersistentToolbarTests, which runs exactly where this one skips.
        throw XCTSkip("wide-shell measurement is macOS-only; compact width is covered by CompactSplitPersistentToolbarTests")
        #endif
    }

    override func tearDown() {
        // Terminate rather than just dropping the reference. Several UI classes in this target
        // drive the SAME app, and on macOS a still-running instance from the previous class makes
        // the next launch fail with "Failed to activate application (current state: Running
        // Background)" - a flake that looks nothing like its cause.
        app?.terminate()
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
    ///
    /// Each present item must also appear at most once: on macOS the container's persistent
    /// items are applied outside the split view, and a per-column application on top of that
    /// would put the same item in the shared window toolbar several times over.
    private func assertBars(_ state: String, present: [String], absent: [String]) {
        var inBar: [String: Bool] = [:]
        var anywhere: [String: Bool] = [:]
        for title in present { inBar[title] = screen.toolbars.buttons[title].exists }
        for title in absent { anywhere[title] = screen.buttons[title].exists }
        let barLabels = screen.toolbars.buttons.allElementsBoundByIndex
            .map { $0.label.isEmpty ? $0.identifier : $0.label }
            .filter { !$0.hasPrefix("_XCUI:") }

        let context = "[\(state)] toolbar: \(barLabels.description)"
        for title in present {
            XCTAssertTrue(inBar[title] == true, "expected \(title) in the window toolbar. \(context)")
            XCTAssertLessThanOrEqual(barLabels.filter { $0 == title }.count, 1,
                                     "\(title) appears more than once in the window toolbar. \(context)")
        }
        for title in absent {
            XCTAssertFalse(anywhere[title] == true, "expected \(title) NOT on screen. \(context)")
        }
    }

    func testToolbarPersistenceAcrossAnInnerPush() {
        let pushInner = screen.buttons["PUSH_INNER"]
        XCTAssertTrue(pushInner.waitForExistence(timeout: 20),
                      "split fixture never loaded. Tree: \(app.debugDescription)")
        XCTAssertTrue(settle(on: "TBDetail"), "detail root never became the top screen")

        assertBars("detail-root",
                   present: containerBars + ["SIDE", "DROOT"],
                   absent: ["DINNER"])

        press(pushInner)
        XCTAssertTrue(screen.staticTexts["inner dest body"].waitForExistence(timeout: 10),
                      "inner push to destination 500 did not happen")
        XCTAssertTrue(settle(on: "TBInner"), "destination 500 never became the top screen")

        // The result this file exists for: the split view's container-level items AND the
        // sidebar's both survive the inner push, because the columns share one window toolbar
        // and the sidebar never unmounts. Only the detail stack's own root bar is replaced.
        assertBars("pushed-inner",
                   present: containerBars + ["SIDE", "DINNER"],
                   absent: ["DROOT"])
    }
}
