// PersistentToolbarTests.swift
//
// Characterization test for Missing_Features #36 (no persistent toolbar).
//
// It pins what SwiftUI, through ActionUI, ACTUALLY does with toolbars around a
// NavigationStack push - measured on 2026-08-08 rather than inferred, because the
// source-level reading of this turned out to be wrong on BOTH platforms, in opposite
// directions. When #36 is implemented these expectations should change; that is the
// point of pinning them now.
//
// Fixture: Resources/NavigationStack.persistentToolbar.json, which declares toolbars in the
// three positions that matter:
//
//   STACKBAR            on the NavigationStack element   -> ActionUI applies it OUTSIDE SwiftUI.NavigationStack
//   ROOTBAR             on the stack's `content`         -> applied INSIDE, on the root screen
//   DESTBARA, DESTBARB  on destination 500               -> two items, so accumulation is observable
//   destination 600     declares no toolbar at all
//
// Measured, iOS 18.5 and iOS 26.5 (identical):
//
//   root             present=[ROOTBAR]            absent=[STACKBAR DESTBARA DESTBARB]
//   pushed-with-bar  present=[DESTBARA DESTBARB]  absent=[STACKBAR ROOTBAR]
//   pushed-no-bar    present=[]                   absent=[STACKBAR ROOTBAR DESTBARA DESTBARB]
//
// Measured, macOS 26 (Tahoe):
//
//   root             present=[ROOTBAR STACKBAR]            absent=[DESTBARA DESTBARB]
//   pushed-with-bar  present=[DESTBARA DESTBARB STACKBAR]  absent=[ROOTBAR]
//   pushed-no-bar    present=[STACKBAR]                    absent=[ROOTBAR DESTBARA DESTBARB]
//
// Three results, in order of how much they matter to #36:
//
//  1. STACKBAR is the whole divergence. On iOS a toolbar authored on the NavigationStack
//     element renders NOWHERE - it does not escape to an enclosing bar and it does not
//     decorate the root, it is simply dropped, which is what Web and Android already do
//     by explicit guard. On macOS the SAME JSON renders it in the WINDOW toolbar, which
//     the whole stack shares, so it survives every push. macOS therefore already has the
//     capability #36 asks for, and iOS/Web/Android have nothing.
//
//  2. Toolbar items ACCUMULATE. DESTBARA and DESTBARB are two separately authored items,
//     so ToolbarHelper emitted two `.toolbar` calls against one view and both rendered,
//     on both platforms. That is the mechanism any merge-based fix would rely on.
//
//  3. A destination that declares no toolbar inherits nothing - no fallback to the root's.
//
// KNOWN LIMITATION, deliberately left open. On iOS every STACKBAR expectation is NEGATIVE,
// so deleting the stack-element `toolbar` block from the fixture would leave the iOS run
// fully green. The macOS run, where STACKBAR is asserted PRESENT, is the positive control
// that makes the iOS result mean anything - so run both, or the "iOS drops it" claim cannot
// be distinguished from "the fixture never declared it". A parse-level assertion in
// ActionUITests over the loaded element tree would make the iOS half self-contained.
//
// Running this: UI automation is exclusive. Clicking in the app while it runs corrupts
// the run, and the corruption looks like a contradictory result rather than an error.

import XCTest

final class PersistentToolbarTests: XCTestCase {
    private let fixtureResource = "NavigationStack.persistentToolbar"
    private let rootTitle = "ToolbarRoot"

    /// The one axis on which the hosts disagree - see note 1 in the header.
    #if os(macOS)
    private let stackBarRenders = true
    #else
    private let stackBarRenders = false
    #endif

    private var app: XCUIApplication!
    private var documentWindowID = ""

    /// Everything is queried through here, never through `app` directly.
    ///
    /// macOS restores previously-opened document windows, so a launch can come up with
    /// several identical copies of the fixture and "the PUSH button" stops identifying one
    /// element - XCUITest then refuses to click at all. The window's IDENTIFIER is stable
    /// across a push (its title is not, it tracks the top of the stack), so it is what
    /// pins every later query to the one window this test is actually driving.
    private var screen: XCUIElement {
        #if os(macOS)
        // NSPredicate rather than matching(identifier:) - the identifier is a SwiftUI
        // generic type name full of angle brackets and commas, which that overload rejects.
        return app.windows.matching(NSPredicate(format: "identifier == %@", documentWindowID)).firstMatch
        #else
        return app
        #endif
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        app = XCUIApplication()
        // No -resetAppState on ANY platform: wherever the host supports multiple windows
        // (macOS and iPad, not iPhone), WindowGroup(for: WindowIdentifier.self) renders an
        // EmptyView while that flag is set, so the fixture opens as a blank scene. On iPhone
        // the flag is simply unnecessary - that path presents a fullScreenCover instead.
        #if os(macOS)
        // ApplePersistenceIgnoreState stops macOS restoring document windows from an earlier
        // run. Without it the app comes up with several identical fixture windows and the
        // uniqueness check below fails - correctly, because a run with duplicates cannot say
        // which window it measured.
        app.launchArguments = ["-openResource", fixtureResource, "-ApplePersistenceIgnoreState", "YES"]
        #else
        app.launchArguments = ["-openResource", fixtureResource]
        #endif
        app.launch()
        Thread.sleep(forTimeInterval: 5)

        #if os(macOS)
        // Bind by the fixture's OWN root title, not by "any window that is not the selector":
        // the latter will happily latch onto a restored window belonging to a different
        // fixture, and every later query then measures the wrong document.
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
        app = nil
        super.tearDown()
    }

    /// Wait until the screen named by `navigationTitle` is the one actually on show.
    ///
    /// A fixed sleep was not enough: macOS reported a pushed destination's buttons while
    /// the window was still titled "ToolbarRoot", i.e. mid-transition. On macOS the window
    /// title tracks the top of the stack, so it is a real settle condition, not a guess.
    /// On iOS it waits for the navigation bar carrying that title, which is a real condition.
    /// An earlier version just slept and returned true, which made every
    /// `XCTAssertTrue(settle(...))` unfailable on iOS - a guard that could not guard.
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

    /// Click on macOS, tap elsewhere.
    private func press(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    /// Sample every watched element EXACTLY ONCE before judging any of them.
    ///
    /// An earlier version filtered the same list twice, once for present and once for
    /// absent, and produced a report with one button in both columns and another in
    /// neither - two live queries straddling a screen that was still moving. A
    /// measurement that contradicts itself is the clearest sign the measurement is what
    /// is wrong.
    /// `present` is checked against the BAR - the window toolbar on macOS, the navigation bar
    /// on iOS - not the whole window. A plain `buttons[title].exists` asks only "somewhere on
    /// screen", so it would pass just as well if an item rendered as an inline banner in the
    /// body, and the macOS claim being pinned here is specifically "in the window toolbar".
    /// `absent` stays window-wide, so "renders nowhere" keeps meaning nowhere.
    private func assertBars(_ state: String, present: [String], absent: [String]) {
        #if os(macOS)
        let bar = screen.toolbars
        #else
        let bar = app.navigationBars
        #endif

        var inBar: [String: Bool] = [:]
        var anywhere: [String: Bool] = [:]
        for title in present { inBar[title] = bar.buttons[title].exists }
        for title in absent { anywhere[title] = screen.buttons[title].exists }

        let context = "[\(state)] in bar: " + bar.buttons.allElementsBoundByIndex
            .map { $0.label.isEmpty ? $0.identifier : $0.label }
            .filter { !$0.hasPrefix("_XCUI:") }
            .description
        for title in present {
            XCTAssertTrue(inBar[title] == true, "expected \(title) in the bar. \(context)")
        }
        for title in absent {
            XCTAssertFalse(anywhere[title] == true, "expected \(title) NOT on screen. \(context)")
        }
    }

    func testToolbarPersistenceAcrossAPush() {
        // The stack-level item is expected everywhere on macOS and nowhere on iOS.
        let stackBar = stackBarRenders ? ["STACKBAR"] : []
        let noStackBar = stackBarRenders ? [] : ["STACKBAR"]

        let pushWithBar = screen.buttons["PUSH_WITH_BAR"]
        XCTAssertTrue(pushWithBar.waitForExistence(timeout: 20),
                      "fixture never loaded. Tree: \(app.debugDescription)")
        settle(on: "ToolbarRoot")

        assertBars("root",
                   present: ["ROOTBAR"] + stackBar,
                   absent: ["DESTBARA", "DESTBARB"] + noStackBar)

        // ---- push onto a destination that declares its own toolbar --------------
        press(pushWithBar)
        XCTAssertTrue(screen.staticTexts["dest with bar"].waitForExistence(timeout: 10),
                      "push to destination 500 did not happen")
        XCTAssertTrue(settle(on: "ToolbarDestWithBar"), "destination 500 never became the top screen")

        // Two things at once: the destination REPLACES the root's bar (so a global
        // indicator authored on the root is invisible here - that IS #36), and the
        // destination's own two items BOTH render, which is what makes a merge viable.
        assertBars("pushed-with-bar",
                   present: ["DESTBARA", "DESTBARB"] + stackBar,
                   absent: ["ROOTBAR"] + noStackBar)

        goBack()
        settle(on: "ToolbarRoot")

        // ---- push onto a destination that declares NO toolbar -------------------
        let pushNoBar = screen.buttons["PUSH_NO_BAR"]
        XCTAssertTrue(pushNoBar.waitForExistence(timeout: 10),
                      "did not return to root. Tree: \(app.debugDescription)")
        press(pushNoBar)
        XCTAssertTrue(screen.staticTexts["dest without bar"].waitForExistence(timeout: 10),
                      "push to destination 600 did not happen")
        XCTAssertTrue(settle(on: "ToolbarDestNoBar"), "destination 600 never became the top screen")

        // Declaring no toolbar does not inherit one. There is no fallback to the root.
        assertBars("pushed-no-bar",
                   present: stackBar,
                   absent: ["ROOTBAR", "DESTBARA", "DESTBARB"] + noStackBar)
    }

    private func goBack() {
        // iOS labels the back button with the previous screen's navigationTitle; macOS
        // uses a plain chevron in the window toolbar.
        for candidate in ["ToolbarRoot", "Back"] {
            let button = screen.buttons[candidate]
            if button.waitForExistence(timeout: 3) {
                press(button)
                Thread.sleep(forTimeInterval: 2)
                return
            }
        }
        #if os(macOS)
        let toolbarButtons = screen.toolbars.buttons
        if toolbarButtons.count > 0 {
            press(toolbarButtons.element(boundBy: 0))
            Thread.sleep(forTimeInterval: 2)
            return
        }
        #else
        if screen.navigationBars.buttons.count > 0 {
            press(screen.navigationBars.buttons.element(boundBy: 0))
            Thread.sleep(forTimeInterval: 2)
            return
        }
        #endif
        XCTFail("no back affordance found. Tree: \(app.debugDescription)")
    }
}
