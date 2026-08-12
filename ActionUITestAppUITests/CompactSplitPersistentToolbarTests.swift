// CompactSplitPersistentToolbarTests.swift
//
// `persistentToolbar` on a NavigationSplitView in COMPACT width - the half that
// SplitPersistentToolbarTests skips, and the half that exercises a rule nothing else does.
//
// In compact width SwiftUI collapses a NavigationSplitView into a single stack rooted at the
// SIDEBAR. So on this platform the sidebar is not a column beside others, it is a screen, and it
// has to carry the split view's persistent items. In regular width it must NOT - each visible
// column keeps its own bar there, and applying to all of them would show one indicator two or
// three times at once. That conditional is the only place the renderer asks about width, and this
// file is the only test that reaches it.
//
// Fixture: Resources/NavigationSplitView.persistentToolbar.json, the same one the macOS wide-shell
// test drives. Collapsed, the launch screen is the sidebar:
//
//   Sync    in the split view's `persistentToolbar`  -> must be here
//   Info    in the split view's `toolbar`            -> the deprecated alias, must be here too
//   New     on the sidebar List itself               -> its own toolbar, must be here
//   Edit    on the detail stack's root               -> must NOT be, the detail is not on screen
//   Share   on a destination of the detail stack     -> must NOT be
//
// TWO GAPS, stated so they are not mistaken for coverage.
//
// This file proves the items ARE applied in compact width. Nothing proves they are NOT applied to
// a leading column in REGULAR width, which is the entire reason `sceneIsCompact` exists as a
// separate environment value. Hard-wiring it true would leave every test in this feature green.
// Measuring it needs a full-screen iPad scene, and the multi-window harness opens the fixture as a
// 320pt side-by-side scene - compact again, i.e. this test. `Missing_Features` #36 says the same.
//
// The two absent-checks below have no positive control HERE: misspell Edit in the fixture and
// they pass for the wrong reason. Their control is SplitPersistentToolbarTests, which drives the
// same fixture on macOS and asserts both labels PRESENT. Run both, or these two mean nothing.
//
// UI automation is exclusive - clicking in the app during a run corrupts it.

import XCTest

final class CompactSplitPersistentToolbarTests: XCTestCase {
    private let fixtureResource = "NavigationSplitView.persistentToolbar"
    private let sidebarTitle = "Folders"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if os(macOS)
        // macOS has no compact width and no collapse: its columns share one window toolbar, which
        // SplitPersistentToolbarTests measures instead.
        throw XCTSkip("compact-width collapse does not exist on macOS - see SplitPersistentToolbarTests")
        #else
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-openResource", fixtureResource]
        app.launch()
        Thread.sleep(forTimeInterval: 5)
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

    func testCollapsedSplitViewCarriesThePersistentItemsOnTheSidebarScreen() throws {
        // A regular-width scene would show the detail column's content alongside, and this file
        // would then be measuring the wrong thing while looking green. Establish the collapse
        // first: the sidebar's own bar is the top bar, and the detail's root bar is nowhere.
        let sidebarBar = app.navigationBars[sidebarTitle]
        XCTAssertTrue(sidebarBar.waitForExistence(timeout: 20),
                      "the collapsed split view should root at the sidebar. Tree: \(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)

        let barLabels = sidebarBar.buttons.allElementsBoundByIndex
            .map { $0.label.isEmpty ? $0.identifier : $0.label }
            .filter { !$0.hasPrefix("_XCUI:") }
        let context = "sidebar bar: \(barLabels.description)"

        for title in ["Sync", "Info", "New"] {
            XCTAssertTrue(sidebarBar.buttons[title].exists,
                          "expected \(title) in the collapsed stack's bar. \(context)")
            XCTAssertLessThanOrEqual(barLabels.filter { $0 == title }.count, 1,
                                     "\(title) appears more than once. \(context)")
        }
        for title in ["Edit", "Share"] {
            XCTAssertFalse(app.buttons[title].exists,
                           "expected \(title) NOT on screen - the detail column is not shown when collapsed. \(context)")
        }
    }
}
