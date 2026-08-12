// ContainerActionTests.swift
//
// The end-to-end test for whole-container tap dispatch: a VStack / HStack / ZStack carrying
// an `actionID` is tappable as ONE target, and dispatches with the row identity a data-driven cell needs.
//
// This exists because the unit tests cannot reach the two claims that matter most. They pin
// the identity RULE (ContainerAction.resolve), which is pure; they cannot show that the
// gesture is actually attached to the rendered stack, nor that a Button inside a tappable
// cell stays the only dispatch. That second one was pure reasoning from SwiftUI semantics -
// "a tap resolves to the innermost control" - and reasoning from semantics instead of
// running it is how this project got Missing_Features #38a wrong.
//
// Fixture: Resources/VStack.containerAction.json
//
//   id 900   a template VStack; each row is an HStack carrying actionID "celltap.cell"
//            and containing a Text ($1) and a Button ("Button $1", actionID "celltap.button")
//   id 910   a status Text the handlers APPEND to, so a second dispatch cannot hide
//            behind the first - "what else fired" is the actual question here
//
// The host handlers live in ActionUISwiftTestApp.swift and write "C<viewID>-<row>;" for a
// cell tap and "B<viewID>-<row>;" for a button tap.
//
// What each assertion buys:
//
//  1. Tapping a row's CELL logs exactly "C900-1;". The gesture is attached (it fires at
//     all), it covers the cell rather than only the Button, and the identity is the owning
//     container's id with the row index - not the cloned instance's id, which
//     TemplateHelper forces to 0. That last part is the whole gap. The cell is addressed
//     as a button, not as the row's Text - see `cell(_:)`.
//
//  2. Tapping a row's BUTTON logs exactly "B900-2;" and nothing else. If the cell action
//     also fired we would see a "C900-2;" beside it. This is the claim that had no
//     evidence before.
//
//  3. Row 0 is exercised as well as a later row, so a fixture that accidentally reported
//     a constant index would not pass.
//
// Measured discrimination, because assertion 2 is the one that could quietly be vacuous.
// Two mutations were run against this file (iPhone SE, iOS 18.4):
//
//   ContainerAction.apply returns the view untouched  ->  kills 1 and 3, and 2 STILL PASSES.
//       On its own, assertion 2 cannot tell "the cell correctly stood down" from "there is
//       no cell action at all". It earns its keep only alongside 1 and 3, which establish
//       that the tap fires in the first place.
//   .onTapGesture replaced by .simultaneousGesture  ->  kills 2 alone.
//       That is the plausible wrong implementation - a gesture that deliberately does NOT
//       defer to the inner control - and it is what turns "SwiftUI resolves a tap to the
//       innermost control" from a claim about semantics into a measured one.
//
// Running this: UI automation is exclusive. Clicking in the app while it runs corrupts the
// run, and the corruption looks like a contradictory result rather than an error.

import XCTest

final class ContainerActionTests: XCTestCase {
    private let fixtureResource = "VStack.containerAction"
    private let rootTitle = "VStack.containerAction"

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

    /// The tappable cell for the row labeled `rowLabel` - the container itself, never the
    /// nested Button, which is what the cell-dispatch assertions rest on.
    ///
    /// It is a BUTTON, not the row's StaticText, on both platforms. `ContainerAction` marks a
    /// tappable container with `.accessibilityAddTraits(.isButton)`, and that absorbs the
    /// container's child Text into a single accessibility element labeled with the row's text:
    /// `staticTexts["Two"]` does not exist for a tappable row on iOS OR macOS. The nested
    /// Button survives the absorption on both, so `buttons["Button Two"]` still resolves
    /// separately - the two are told apart by label, and the fixture keeps those distinct.
    ///
    /// This is worth spelling out because querying the StaticText is the obvious thing to
    /// write - a Text is not a control, so a dispatch after tapping it could only have come
    /// from the container - and it fails as "rows never loaded", which looks exactly like the
    /// rows not rendering when they have rendered fine.
    private func cell(_ rowLabel: String) -> XCUIElement {
        screen.buttons[rowLabel]
    }

    /// Presses Load and waits for the three rows to exist.
    private func loadRows() {
        let load = screen.buttons["Load"]
        XCTAssertTrue(load.waitForExistence(timeout: 10), "Load button never appeared")
        press(load)
        XCTAssertTrue(cell("Three").waitForExistence(timeout: 10), "rows never loaded")
        XCTAssertEqual(waitForLog("Log: "), "Log: ", "the log did not start empty")
    }

    func testTappingACellDispatchesTheOwningContainerIDAndRowIndex() {
        loadRows()

        let rowBody = cell("Two")
        XCTAssertTrue(rowBody.exists, "row 1 body missing")
        press(rowBody)

        XCTAssertEqual(waitForLog("Log: C900-1;"), "Log: C900-1;",
                       "a cell tap must dispatch the owning container id (900) and the row index (1)")
    }

    func testRowZeroReportsItsOwnIndex() {
        loadRows()
        let rowBody = cell("One")
        XCTAssertTrue(rowBody.exists, "row 0 body missing")
        press(rowBody)

        XCTAssertEqual(waitForLog("Log: C900-0;"), "Log: C900-0;",
                       "row 0 must report index 0, not a constant or a missing context")
    }

    func testAButtonInsideATappableCellIsTheOnlyDispatch() {
        loadRows()

        let button = screen.buttons["Button Three"]
        XCTAssertTrue(button.exists, "row 2 button missing")
        press(button)

        // Wait for the button's own dispatch first, then give the cell action a chance to
        // arrive late before declaring it absent - asserting "not present" immediately would
        // pass simply by being quick.
        XCTAssertEqual(waitForLog("Log: B900-2;"), "Log: B900-2;",
                       "the button must dispatch with its row index")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(log(), "Log: B900-2;",
                       "the enclosing cell must NOT also dispatch - SwiftUI resolves the tap to "
                       + "the innermost control, and this is the assertion that proves it")
    }
}
