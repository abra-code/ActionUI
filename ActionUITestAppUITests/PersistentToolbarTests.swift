// PersistentToolbarTests.swift
//
// The narrow-shell test for `persistentToolbar` (Missing_Features #36): toolbar items that
// stay in the bar on every screen inside a NavigationStack, not only on the screen that
// declares them. It also pins the two SwiftUI behaviors the implementation rests on, both
// measured here on 2026-08-08 before any of it was written.
//
// Fixture: Resources/NavigationStack.persistentToolbar.json, declaring toolbars in the
// positions that matter:
//
//   Sync           in the stack's `persistentToolbar`  -> the feature
//   Info           in the stack's `toolbar`            -> the DEPRECATED ALIAS for it
//   Sort           on the stack's `content`            -> one screen only (the root)
//   Edit, Share    on destination 500                  -> two items, so accumulation is observable
//   destination 600 declares no toolbar at all
//   an INLINE NavigationLink destination (Form 1), which the renderer builds by a different
//   route than the destinations array - the one push shape the others cannot speak for
//
// The labels are deliberately SHORT. They started out as PERSISTBAR / STACKBAR / DESTBARA,
// and on iOS 26 the pushed destination then carried five items - back button, two of its
// own, and two persistent - which no longer fit an iPhone bar: iOS moved DESTBARA and
// DESTBARB into a "More" overflow menu and the test failed for width, not for logic. That
// is why the readable names chosen later were kept to one short word each. What matters is
// RENDERED width, not character count: Sync/Info/Edit/Share is the same 17 characters as the
// PERS/ALIAS/DSTA/DSTB set it replaced but draws narrower, because it is mixed case rather
// than all caps - and the iOS back button, which grew from "TBRoot" to "Library", spends
// from the same budget. Rename these to longer or all-caps words and the width failure
// above comes back. Worth knowing beyond
// this file, in two directions. Persistent items are not free - they spend bar space on
// every screen inside the container, so a container should carry one or two, not a row. And
// in that overflow iOS kept the PERSISTENT items visible and overflowed the screen's own,
// which is the good outcome for a status indicator but is an observation, not a guarantee -
// nothing documents which end of an accumulated bar overflows first.
//
// Expected on EVERY Apple platform - which is the point, because the hosts used to disagree:
//
//   root             present=[Sync Info Sort]        absent=[Edit Share]
//   pushed-with-bar  present=[Sync Info Edit Share]  absent=[Sort]
//   pushed-no-bar    present=[Sync Info]             absent=[Sort Edit Share]
//   pushed-inline    present=[Sync Info]             absent=[Sort Edit Share]
//
// What each column is doing:
//
//  1. Sync present in all three states IS the feature. It survives a push onto a
//     destination with its own toolbar and onto one with no toolbar at all, and it does so
//     by two different routes: on macOS the items are applied once OUTSIDE the stack and
//     land in the shared window toolbar, while on iOS - which has no window toolbar - they
//     are merged into every screen's own bar. Same JSON, same result.
//
//  2. Info tracks the alias. A `toolbar` on the container was never a screen toolbar on
//     any host: macOS put it in the window toolbar (so it already behaved persistently),
//     iOS rendered it NOWHERE, and Web and Android dropped it by explicit guard. It now
//     means `persistentToolbar` everywhere, plus a load-time deprecation warning.
//
//  3. Toolbar items ACCUMULATE - Edit and Share are separately authored and both render,
//     alongside the persistent ones. That is the mechanism the iOS merge relies on, and why
//     persistent items compose with a screen's own bar instead of replacing it. Each present
//     item is also asserted to appear at most ONCE, which is what would catch the outer
//     application and the per-screen merge both firing on macOS.
//
//  4. Sort absent from both destinations: a screen's own toolbar is still its own, and a
//     destination declaring no toolbar still inherits nothing. `persistentToolbar` is the
//     only thing that crosses a push.
//
// Every negative assertion has a positive control in another state of the same run, so
// nothing here passes merely because the fixture forgot to declare something.
//
// Running this: UI automation is exclusive. Clicking in the app while it runs corrupts
// the run, and the corruption looks like a contradictory result rather than an error.

import XCTest

final class PersistentToolbarTests: XCTestCase {
    private let fixtureResource = "NavigationStack.persistentToolbar"
    private let rootTitle = "Library"

    /// The container-level items: the real key and its deprecated alias. Both are expected
    /// on every screen, on every platform - they are the same array by the time it reaches
    /// the renderer (ToolbarHelper.persistentToolbarItems).
    private let containerBars = ["Sync", "Info"]

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
        // Terminate rather than just dropping the reference. Several UI classes in this target
        // drive the SAME app, and on macOS a still-running instance from the previous class makes
        // the next launch fail with "Failed to activate application (current state: Running
        // Background)" - a flake that looks nothing like its cause.
        app?.terminate()
        app = nil
        super.tearDown()
    }

    /// Wait until the screen named by `navigationTitle` is the one actually on show.
    ///
    /// A fixed sleep was not enough: macOS reported a pushed destination's buttons while
    /// the window was still titled "Library", i.e. mid-transition. On macOS the window
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
    /// body, and the claim being pinned here is specifically "in the bar".
    /// `absent` stays window-wide, so "does not appear" keeps meaning nowhere.
    ///
    /// Each present item is also required to appear at most once. A persistent item applied
    /// at both sites on the same platform would still be "present" - it would just be there
    /// twice, and only a count can see that.
    private func assertBars(_ state: String, screenTitle: String, present: [String], absent: [String]) {
        #if os(macOS)
        let bar = screen.toolbars
        #else
        // Scoped to THIS screen's bar, not app.navigationBars. The unscoped query means "some
        // navigation bar anywhere", which during a push transition can still see the outgoing
        // screen's bar - enough to make a positive pass for the wrong reason and to make the
        // at-most-once count below report a duplicate that is really two screens.
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
            // Not XCTAssertEqual(_, 1): if a platform reports a bar button under some other
            // label this stays quiet rather than failing for a naming reason, while still
            // catching the duplication it exists to catch.
            XCTAssertLessThanOrEqual(barLabels.filter { $0 == title }.count, 1,
                                     "\(title) appears more than once in the bar. \(context)")
        }
        for title in absent {
            XCTAssertFalse(anywhere[title] == true, "expected \(title) NOT on screen. \(context)")
        }
    }

    func testToolbarPersistenceAcrossAPush() {
        let pushWithBar = screen.buttons["Push a screen with its own bar"]
        XCTAssertTrue(pushWithBar.waitForExistence(timeout: 20),
                      "fixture never loaded. Tree: \(app.debugDescription)")
        settle(on: "Library")

        assertBars("root", screenTitle: rootTitle,
                   present: containerBars + ["Sort"],
                   absent: ["Edit", "Share"])

        // ---- push onto a destination that declares its own toolbar --------------
        press(pushWithBar)
        XCTAssertTrue(screen.staticTexts["This screen brings its own toolbar."].waitForExistence(timeout: 10),
                      "push to destination 500 did not happen")
        XCTAssertTrue(settle(on: "Album"), "destination 500 never became the top screen")

        // Three things at once: the container's items cross the push, the destination's own
        // two items BOTH render beside them (accumulation), and the root's bar is gone -
        // persistence is a property of `persistentToolbar`, not of the whole bar.
        assertBars("pushed-with-bar", screenTitle: "Album",
                   present: containerBars + ["Edit", "Share"],
                   absent: ["Sort"])

        goBack()
        settle(on: "Library")

        // ---- push onto a destination that declares NO toolbar -------------------
        let pushNoBar = screen.buttons["Push a screen with no bar of its own"]
        XCTAssertTrue(pushNoBar.waitForExistence(timeout: 10),
                      "did not return to root. Tree: \(app.debugDescription)")
        press(pushNoBar)
        XCTAssertTrue(screen.staticTexts["This screen declares no toolbar."].waitForExistence(timeout: 10),
                      "push to destination 600 did not happen")
        XCTAssertTrue(settle(on: "Artists"), "destination 600 never became the top screen")

        // The hardest case for the iOS merge: a destination with no toolbar of its own still
        // shows the container's items, and still inherits nothing else.
        assertBars("pushed-no-bar", screenTitle: "Artists",
                   present: containerBars,
                   absent: ["Sort", "Edit", "Share"])

        goBack()
        settle(on: rootTitle)

        // ---- push via an INLINE NavigationLink destination -----------------------
        // A different code path. NavigationLink Form 1 renders its own `destination` subview
        // instead of going through the stack's navigationDestination, so neither case above can
        // speak for it - and it was missed the first time, staying green while that one push
        // shape silently lost the items on iOS.
        let pushInline = screen.buttons["Push an inline destination"]
        XCTAssertTrue(pushInline.waitForExistence(timeout: 10),
                      "did not return to root. Tree: \(app.debugDescription)")
        press(pushInline)
        XCTAssertTrue(screen.staticTexts["An inline destination."].waitForExistence(timeout: 10),
                      "the inline push did not happen")
        XCTAssertTrue(settle(on: "Note"), "the inline destination never became the top screen")

        assertBars("pushed-inline", screenTitle: "Note",
                   present: containerBars,
                   absent: ["Sort", "Edit", "Share"])
    }

    private func goBack() {
        // iOS labels the back button with the previous screen's navigationTitle; macOS
        // uses a plain chevron in the window toolbar.
        for candidate in [rootTitle, "Back"] {
            let button = screen.buttons[candidate]
            if button.waitForExistence(timeout: 3) {
                press(button)
                Thread.sleep(forTimeInterval: 2)
                return
            }
        }
        // Fall back to the first button in the bar that is NOT one of the fixture's own probes.
        // Taking index 0 unconditionally used to be safe only because the bar held one other
        // item; now that the container contributes items to every screen, index 0 can easily be
        // Sync - and pressing that would navigate nowhere and fail the next step instead of here.
        #if os(macOS)
        let barButtons = screen.toolbars.buttons
        #else
        let barButtons = screen.navigationBars.buttons
        #endif
        let probes = Set(containerBars + ["Sort", "Edit", "Share"])
        if let back = barButtons.allElementsBoundByIndex.first(where: { !probes.contains($0.label) }) {
            press(back)
            Thread.sleep(forTimeInterval: 2)
            return
        }
        XCTFail("no back affordance found. Tree: \(app.debugDescription)")
    }
}
