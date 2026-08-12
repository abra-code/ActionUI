// ListPersistentToolbarTests.swift
//
// `persistentToolbar` on the OTHER NavigationStack branch.
//
// NavigationStack.buildView has two of them. The standard branch handles a content view with
// NavigationLinks in it; the SELECTABLE-LIST branch takes over when content is a List with an
// actionID whose children carry destinationViewId, and drives the push from List selection
// instead. They build their screens at different sites, so a fix applied to one and not the
// other compiles, passes, and does nothing where it matters - the design for this feature calls
// that out by name, and SharedCare's narrow shell takes the selectable-List branch.
//
// PersistentToolbarTests covers the standard branch. This file exists so that branch is not the
// only one measured. Fixture: Resources/NavigationStack.persistentToolbarList.json.
//
//   Sync   in the stack's `persistentToolbar`
//   Sort   on the content List           -> the root screen only
//   Edit   on destination 500            -> that destination only
//
//   root     present=[Sync Sort]  absent=[Edit]
//   pushed   present=[Sync Edit]  absent=[Sort]
//
// Deliberately smaller than its sibling: this is a second measurement of the same claim through
// a different code path, not a second exploration. The interesting extra is that on this branch
// the push comes from a List SELECTION rather than a NavigationLink tap.
//
// UI automation is exclusive - clicking in the app during a run corrupts it.

import XCTest

final class ListPersistentToolbarTests: XCTestCase {
    private let fixtureResource = "NavigationStack.persistentToolbarList"
    private let rootTitle = "Playlists"

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
        continueAfterFailure = true
        app = XCUIApplication()
        #if os(macOS)
        app.launchArguments = ["-openResource", fixtureResource, "-ApplePersistenceIgnoreState", "YES"]
        #else
        app.launchArguments = ["-openResource", fixtureResource]
        #endif
        app.launch()
        Thread.sleep(forTimeInterval: 5)

        #if os(macOS)
        let matches = app.windows.allElementsBoundByIndex.filter { $0.title == rootTitle }
        guard matches.count == 1, let document = matches.first else {
            XCTFail("expected exactly one \(rootTitle) window, found \(matches.count). "
                    + "Windows: \(app.windows.allElementsBoundByIndex.map { $0.title })")
            return
        }
        documentWindowID = document.identifier
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

    @discardableResult
    private func settle(on title: String) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            #if os(macOS)
            let arrived = screen.title == title
            #else
            let arrived = app.navigationBars[title].exists
            #endif
            if arrived {
                Thread.sleep(forTimeInterval: 1)
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// Positives are scoped to the bar, negatives stay window-wide, and every present item must
    /// appear at most once - same discipline as PersistentToolbarTests, and for the same reasons.
    private func assertBars(_ state: String, screenTitle: String, present: [String], absent: [String]) {
        #if os(macOS)
        let bar = screen.toolbars
        #else
        // This screen's bar, not "any navigation bar" - see the note in PersistentToolbarTests.
        let bar = app.navigationBars[screenTitle]
        #endif

        var inBar: [String: Bool] = [:]
        var anywhere: [String: Bool] = [:]
        for title in present { inBar[title] = bar.buttons[title].exists }
        for title in absent { anywhere[title] = screen.buttons[title].exists }
        let barLabels = bar.buttons.allElementsBoundByIndex
            .map { $0.label.isEmpty ? $0.identifier : $0.label }
            .filter { !$0.hasPrefix("_XCUI:") }

        let context = "[\(state)] in bar: \(barLabels.description)"
        for title in present {
            XCTAssertTrue(inBar[title] == true, "expected \(title) in the bar. \(context)")
            XCTAssertLessThanOrEqual(barLabels.filter { $0 == title }.count, 1,
                                     "\(title) appears more than once in the bar. \(context)")
        }
        for title in absent {
            XCTAssertFalse(anywhere[title] == true, "expected \(title) NOT on screen. \(context)")
        }
    }

    func testPersistentToolbarSurvivesASelectionDrivenPush() {
        // Wait FIRST, then choose. Picking the query before waiting means a still-loading app
        // silently commits to the staticTexts branch and the wait then fails against it.
        XCTAssertTrue(screen.staticTexts["Road Trip"].waitForExistence(timeout: 20)
                      || screen.buttons["Road Trip"].exists,
                      "list fixture never loaded. Tree: \(app.debugDescription)")
        let row = screen.buttons["Road Trip"].exists ? screen.buttons["Road Trip"] : screen.staticTexts["Road Trip"]
        settle(on: rootTitle)

        assertBars("root", screenTitle: rootTitle, present: ["Sync", "Sort"], absent: ["Edit"])

        press(row)
        XCTAssertTrue(screen.staticTexts["The pushed screen."].waitForExistence(timeout: 10),
                      "selecting the row did not push destination 500")
        XCTAssertTrue(settle(on: "Songs"), "destination 500 never became the top screen")

        // The claim: the selectable-List branch merges the container's items too. Delete either
        // of that branch's two onScreen calls in NavigationStack.swift and this is what goes red.
        assertBars("pushed", screenTitle: "Songs", present: ["Sync", "Edit"], absent: ["Sort"])
    }
}
