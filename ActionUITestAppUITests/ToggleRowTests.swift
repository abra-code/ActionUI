// ToggleRowTests.swift
//
// The end-to-end test for a Toggle in data-driven rows: in a List template and as a Table
// column. The unit tests (ActionUITests/Views/ToggleTemplateTests.swift) pin the write into
// the rows and the action's identity; they cannot show the two claims that depend on the
// rendered hierarchy:
//
//   - a click on the Toggle changes the Toggle only: the row is not selected and the
//     container's own actionID does not fire;
//   - a click elsewhere in the row selects it and does not toggle.
//
// Fixture: Resources/List.toggleRows.json
//
//   id 920   a selectable List whose template is an HStack holding a checkbox Toggle
//            ("Check $2", isOn "$1", disabled "$3") and a Text ("Row $2")
//   id 930   a selectable Table (macOS) with a Toggle column and a Text column
//   id 940   a status Text the handlers APPEND to, so a second dispatch cannot hide
//            behind the first
//
// The host handlers live in ActionUISwiftTestApp.swift and write
//   "T<list id>-<row>=<new Bool>:<state stored in the row>;"   a Toggle in the List
//   "C<table id>-<column>=<row>:<state stored in the cell>;"   a Toggle cell in the Table
//   "S<id>;"                                                   a selection change
//
// Each "not also" assertion waits for the expected entry first and then gives a late
// second dispatch two seconds to arrive, as ContainerActionTests does.
//
// Running this: UI automation is exclusive. Clicking in the app while it runs corrupts the
// run, and the corruption looks like a contradictory result rather than an error.

import XCTest

final class ToggleRowTests: XCTestCase {
    private let fixtureResource = "List.toggleRows"
    private let rootTitle = "List.toggleRows"

    private var app: XCUIApplication!
    private var documentWindowID = ""

    /// Everything is queried through here, never through `app` directly - see
    /// PersistentToolbarTests for why the window identifier is what pins the query.
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
        // Terminate rather than dropping the reference: a still-running instance makes the
        // next class's launch fail with "Failed to activate application", a flake that looks
        // nothing like its cause.
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

    /// The status Text's current contents, or "" when it has not appeared yet.
    ///
    /// Reads `label` AND `value`, because the two platforms disagree about where a SwiftUI
    /// Text puts its string: on iOS it is the accessibility LABEL, on macOS the label is
    /// empty and the string is the VALUE. Reading only the label passed the whole suite on
    /// iOS and reported "" for every assertion on macOS - a harness bug that looked exactly
    /// like the feature being broken on one platform.
    private func log() -> String {
        for element in screen.staticTexts.allElementsBoundByIndex {
            if element.label.hasPrefix("Log: ") { return element.label }
            if let value = element.value as? String, value.hasPrefix("Log: ") { return value }
        }
        return ""
    }

    /// Waits for the log to reach `expected`, then returns it. Returning the LAST observed
    /// value rather than a Bool means a failure message shows what actually arrived - which
    /// for a double-dispatch bug is the whole diagnosis ("B900-2;C900-2;" vs "B900-2;").
    @discardableResult
    private func waitForLog(_ expected: String) -> String {
        let deadline = Date().addingTimeInterval(10)
        var seen = ""
        while Date() < deadline {
            seen = log()
            if seen == expected { return seen }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return seen
    }

    /// The Toggle of the List row titled `title`. A checkbox on macOS; the "checkbox" style
    /// falls back to a switch where the platform has none.
    private func listToggle(_ title: String) -> XCUIElement {
        #if os(macOS)
        return screen.checkBoxes["Check \(title)"]
        #else
        return screen.switches["Check \(title)"]
        #endif
    }

    /// Presses Load and waits for the rows to exist.
    private func loadRows() {
        let load = screen.buttons["Load"]
        XCTAssertTrue(load.waitForExistence(timeout: 10), "Load button never appeared")
        press(load)
        XCTAssertTrue(listToggle("Three").waitForExistence(timeout: 10), "rows never loaded")
        XCTAssertEqual(waitForLog("Log: "), "Log: ", "the log did not start empty")
    }

    /// Asserts the log reaches `expected` and still reads `expected` two seconds later.
    private func assertLogIsOnly(_ expected: String, _ message: String) {
        XCTAssertEqual(waitForLog(expected), expected, message)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(log(), expected, "something else fired as well: \(message)")
    }

    func testTogglingAListRowWritesTheRowAndDoesNotSelectIt() {
        loadRows()
        press(listToggle("Two"))
        assertLogIsOnly("Log: T920-1=true:true;",
                        "the Toggle must fire with the List id, the row index and the new state, after the row is written")
    }

    func testTogglingTwiceTurnsTheRowOffAgain() {
        // The second click only reads "false" if the first one was kept across the re-render.
        loadRows()
        press(listToggle("One"))
        XCTAssertEqual(waitForLog("Log: T920-0=true:true;"), "Log: T920-0=true:true;")
        press(listToggle("One"))
        assertLogIsOnly("Log: T920-0=true:true;T920-0=false:false;", "the second click must turn the row off")
    }

    func testClickingTheRowTextSelectsWithoutToggling() {
        loadRows()
        let text = screen.staticTexts["Row Two"]
        XCTAssertTrue(text.exists, "row 1 text missing")
        press(text)
        assertLogIsOnly("Log: S920;", "a click outside the Toggle selects the row and toggles nothing")
    }

    func testADisabledRowDoesNotToggle() {
        loadRows()
        let locked = listToggle("Three")
        XCTAssertFalse(locked.isEnabled, "the row's third column disables its Toggle")
    }

    #if os(macOS)
    /// The Toggle cells of the Table: they carry no title, which tells them apart from the
    /// List's "Check ..." toggles.
    private func tableToggles() -> [XCUIElement] {
        screen.checkBoxes.allElementsBoundByIndex.filter { !$0.label.hasPrefix("Check ") }
    }

    func testTogglingATableCellWritesTheCellAndDoesNotSelectTheRow() {
        loadRows()
        let cells = tableToggles()
        XCTAssertEqual(cells.count, 3, "expected one Toggle cell per row")
        guard cells.count == 3 else { return }
        press(cells[1])
        assertLogIsOnly("Log: C930-0=1:true;",
                        "the cell must fire with the Table id, the column, the row index, after the cell is written")
    }

    func testADisabledTableCellDoesNotToggle() {
        loadRows()
        let cells = tableToggles()
        guard cells.count == 3 else { XCTFail("expected one Toggle cell per row"); return }
        XCTAssertFalse(cells[2].isEnabled, "the row's third column disables its Toggle cell")
        XCTAssertTrue(cells[0].isEnabled)
    }
    #endif
}
