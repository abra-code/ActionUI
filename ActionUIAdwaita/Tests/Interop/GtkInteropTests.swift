// Tests/Interop/GtkInteropTests.swift
/*
 Tests for the GTK interop helpers: signal handlers run and are released with their widget or on
 disconnect, user-signal handlers stay silent during a renderer update, attached objects live as
 long as their GObject, and timers run once or not at all when removed.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class GtkInteropTests: XCTestCase {

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    /// A new button the test owns (GTK hands out a floating reference, which the sink takes).
    private func ownedButton() -> WidgetPointer {
        let button = gtk_button_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(button))
        return button
    }

    func testConnectSignalRunsTheHandler() {
        let button = ownedButton()
        defer { g_object_unref(UnsafeMutableRawPointer(button)) }
        let clicks = CallCounter()
        let id = connectSignal(button, "clicked", .instanceOnly) { clicks.count += 1 }
        XCTAssertNotEqual(id, 0)
        AdwaitaTestHost.emit("clicked", on: button)
        AdwaitaTestHost.emit("clicked", on: button)
        XCTAssertEqual(clicks.count, 2)
    }

    func testANotifySignalRunsTheHandler() {
        let toggle = gtk_toggle_button_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(toggle))
        defer { g_object_unref(UnsafeMutableRawPointer(toggle)) }
        let changes = CallCounter()
        connectSignal(toggle, "notify::active", .instanceAndArgument) { changes.count += 1 }
        gtk_toggle_button_set_active(typed(toggle), 1)
        XCTAssertEqual(changes.count, 1)
    }

    func testTheHandlerIsReleasedWithItsWidget() {
        let button = ownedButton()
        weak var released: CallCounter?
        do {
            let clicks = CallCounter()
            released = clicks
            connectSignal(button, "clicked", .instanceOnly) { clicks.count += 1 }
        }
        XCTAssertNotNil(released, "GLib keeps the handler while it is connected")
        g_object_unref(UnsafeMutableRawPointer(button))
        XCTAssertNil(released, "finalizing the widget released the handler")
    }

    func testTheHandlerIsReleasedOnDisconnect() {
        let button = ownedButton()
        defer { g_object_unref(UnsafeMutableRawPointer(button)) }
        weak var released: CallCounter?
        var id: gulong = 0
        do {
            let clicks = CallCounter()
            released = clicks
            id = connectSignal(button, "clicked", .instanceOnly) { clicks.count += 1 }
        }
        g_signal_handler_disconnect(UnsafeMutableRawPointer(button), id)
        XCTAssertNil(released)
    }

    func testAnUnknownSignalReleasesTheHandler() {
        let button = ownedButton()
        defer { g_object_unref(UnsafeMutableRawPointer(button)) }
        weak var released: CallCounter?
        do {
            let clicks = CallCounter()
            released = clicks
            // GLib logs a critical for the unknown signal; the test only checks the release.
            XCTAssertEqual(connectSignal(button, "no-such-signal", .instanceOnly) { clicks.count += 1 }, 0)
        }
        XCTAssertNil(released)
    }

    func testAUserSignalIsIgnoredDuringAnUpdate() {
        let entry = gtk_entry_new()!
        g_object_ref_sink(UnsafeMutableRawPointer(entry))
        defer { g_object_unref(UnsafeMutableRawPointer(entry)) }
        let edits = CallCounter()
        connectUserSignal(entry, "changed", .instanceOnly) { edits.count += 1 }

        // A renderer setting the text: GTK emits "changed" inside the call, and the guard drops it.
        UpdateGuard.applying {
            gtk_editable_set_text(opaque(entry), "from the model")
        }
        XCTAssertEqual(edits.count, 0)

        // The same change outside an update, as typing would make it. (Replacing text emits
        // "changed" for the deletion and for the insertion.)
        gtk_editable_set_text(opaque(entry), "typed")
        XCTAssertGreaterThan(edits.count, 0)
    }

    func testAnAttachedObjectLivesAsLongAsItsGObject() {
        let button = ownedButton()
        weak var first: CallCounter?
        weak var second: CallCounter?
        do {
            let value = CallCounter()
            first = value
            attach(value, to: button, key: "test-key")
        }
        XCTAssertTrue(attached(CallCounter.self, on: button, key: "test-key") === first)
        XCTAssertNil(attached(TimerAction.self, on: button, key: "test-key"), "another type is not returned")
        XCTAssertNil(attached(CallCounter.self, on: button, key: "other-key"))

        do {
            let value = CallCounter()
            second = value
            attach(value, to: button, key: "test-key")
        }
        XCTAssertNil(first, "replacing the value released the old one")
        XCTAssertNotNil(second)

        g_object_unref(UnsafeMutableRawPointer(button))
        XCTAssertNil(second, "finalizing the object released the value")
    }

    func testATimerRunsOnceAndIsReleased() {
        weak var released: CallCounter?
        let fired = CallCounter()
        do {
            let held = CallCounter()
            released = held
            runAfter(milliseconds: 10) {
                held.count += 1
                fired.count += 1
            }
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { fired.count > 0 }))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.count, 1)
        XCTAssertNil(released)
    }

    func testARemovedTimerNeverRuns() {
        weak var released: CallCounter?
        let fired = CallCounter()
        do {
            let held = CallCounter()
            released = held
            let source = runAfter(milliseconds: 10) {
                held.count += 1
                fired.count += 1
            }
            XCTAssertNotEqual(g_source_remove(source), 0)
        }
        XCTAssertNil(released)
        // Longer than the timer's interval.
        XCTAssertFalse(AdwaitaTestHost.runMainLoop(until: { fired.count > 0 }, timeoutMilliseconds: 50))
    }
}
