// Tests/Interop/WrapperTests.swift
/*
 Tests for the Swift wrappers of the C API (Owned.swift, Widgets.swift, Properties.swift): each
 owned type takes the right reference for new (floating), handed-over and borrowed pointers and
 releases it once, also on an early return; a handed-over reference is not released; the widget
 views read and write Booleans, skip setting a value the widget already has, walk children in
 order, and measure with baselines; properties read and write by name and skip an equal value.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class WrapperTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    private func referenceCount(_ object: UnsafeMutableRawPointer) -> UInt32 {
        object.assumingMemoryBound(to: GObject.self).pointee.ref_count
    }

    // MARK: Owned references

    func testRetainingClaimsANewWidgetsFloatingReferenceAndReleasesIt() {
        let label = UnsafeMutableRawPointer(gtk_label_new("x")!)
        XCTAssertNotEqual(g_object_is_floating(label), 0)
        g_object_ref(label)  // the test's own, to watch the count after the owner is gone
        do {
            let owned = OwnedObject(retaining: label)
            XCTAssertEqual(g_object_is_floating(owned.pointer), 0, "the floating reference claimed")
            XCTAssertEqual(referenceCount(label), 2)
        }
        XCTAssertEqual(referenceCount(label), 1, "released when the owner went away")
        g_object_unref(label)
    }

    func testRetainingABorrowedObjectTakesAReferenceOfItsOwn() {
        let label = UnsafeMutableRawPointer(gtk_label_new("x")!)
        g_object_ref_sink(label)  // owned elsewhere: not floating, count 1
        do {
            let owned = OwnedObject(retaining: label)
            XCTAssertEqual(referenceCount(owned.pointer), 2)
        }
        XCTAssertEqual(referenceCount(label), 1)
        g_object_unref(label)
    }

    func testAdoptingTakesAFullReferenceAsIs() {
        let menu = UnsafeMutableRawPointer(g_menu_new()!)
        g_object_ref(menu)
        do {
            let owned = OwnedObject(adopting: menu)
            XCTAssertEqual(referenceCount(owned.pointer), 2, "no reference added")
        }
        XCTAssertEqual(referenceCount(menu), 1, "the adopted reference released")
        g_object_unref(menu)
    }

    func testAnEarlyReturnReleasesTheReference() {
        let menu = UnsafeMutableRawPointer(g_menu_new()!)
        g_object_ref(menu)
        func returnsEarly(_ flag: Bool) -> Int {
            let owned = OwnedObject(adopting: OpaquePointer(menu))
            guard flag else { return 0 }
            return Int(referenceCount(owned.pointer))
        }
        XCTAssertEqual(returnsEarly(false), 0)
        XCTAssertEqual(referenceCount(menu), 1)
        g_object_unref(menu)
    }

    func testAHandedOverReferenceIsNotReleased() {
        let menu = UnsafeMutableRawPointer(g_menu_new()!)
        g_object_ref(menu)
        let owned = OwnedObject(adopting: menu)
        let handed = owned.handOver()
        XCTAssertEqual(referenceCount(handed), 2, "the callee owns the reference now")
        g_object_unref(handed)  // as the callee would
        XCTAssertEqual(referenceCount(menu), 1)
        g_object_unref(menu)
    }

    func testOwnedVariantsReadTheirValueAndRefuseTheWrongType() {
        let text = OwnedVariant(retaining: g_variant_new_string("tag")!)
        XCTAssertEqual(g_variant_is_floating(text.pointer), 0, "the floating reference claimed")
        XCTAssertEqual(text.string, "tag")
        XCTAssertNil(text.bool, "a string is no Boolean")
        let flag = OwnedVariant(retaining: g_variant_new_boolean(1)!)
        XCTAssertEqual(flag.bool, true)
        XCTAssertNil(flag.string, "a Boolean is no string")
        let borrowed = OwnedVariant(retaining: flag.pointer)
        XCTAssertEqual(borrowed.bool, true)
        let adopted = OwnedVariant(adopting: g_variant_ref_sink(g_variant_new_string("full"))!)
        XCTAssertEqual(adopted.string, "full")
        let path = OwnedVariant(retaining: g_variant_new_object_path("/a")!)
        XCTAssertNil(path.string, "an object path is not a string")
    }

    func testTakenStringsAreCopiedAndFreed() {
        XCTAssertEqual(takeGString(g_strdup("abc")), "abc")
        XCTAssertNil(takeGString(nil))
    }

    // MARK: Widget views

    // GTK 4.18 itself skips equal text on a label and an equal visible flag (no notify either way),
    // so these counts pin the end state only; testTheSameTextKeepsAnEntrysCursor is the one that
    // fails without a guard (GtkEntry replaces equal text and moves the cursor).
    func testSettersSkipAValueTheWidgetHas() {
        let label = OwnedObject(retaining: gtk_label_new("one")!)
        var notified = 0
        connectSignal(label.pointer, "notify::label", .instanceAndArgument) { notified += 1 }
        let view = Gtk.Label(label.widget)
        view.text = "one"
        XCTAssertEqual(notified, 0, "the same text: not set")
        view.text = "two"
        XCTAssertEqual(notified, 1)
        XCTAssertEqual(view.text, "two")

        let widget = Gtk.Widget(label.widget)
        var visibility = 0
        connectSignal(label.pointer, "notify::visible", .instanceAndArgument) { visibility += 1 }
        widget.isVisible = true
        XCTAssertEqual(visibility, 0)
        widget.isVisible = false
        XCTAssertFalse(widget.isVisible)
        XCTAssertEqual(visibility, 1)
    }

    func testTheSameTextKeepsAnEntrysCursor() {
        let entry = OwnedObject(retaining: gtk_entry_new()!)
        let editable = Gtk.Editable(entry.widget)
        editable.text = "hello"
        gtk_editable_set_position(entry.opaquePointer, 2)
        editable.text = "hello"
        XCTAssertEqual(gtk_editable_get_position(entry.opaquePointer), 2)
    }

    func testACheckButtonsStateReadsAsABoolean() {
        let check = OwnedObject(retaining: gtk_check_button_new()!)
        let view = Gtk.CheckButton(check.widget)
        XCTAssertFalse(view.isActive)
        view.isActive = true
        XCTAssertTrue(view.isActive)
    }

    func testChildrenComeInOrder() {
        let box = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!)
        for text in ["a", "b", "c"] {
            gtk_box_append(box.typed(), gtk_label_new(text))
        }
        let texts = Gtk.Widget(box.widget).children.map { Gtk.Label($0.pointer).text }
        XCTAssertEqual(texts, ["a", "b", "c"])
        XCTAssertEqual(Gtk.Widget(box.widget).lastChild.map { Gtk.Label($0.pointer).text }, "c")
    }

    func testRemovingTheCurrentChildKeepsTheWalkGoing() {
        let box = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!)
        for text in ["a", "b", "c"] {
            gtk_box_append(box.typed(), gtk_label_new(text))
        }
        var removed = 0
        for child in Gtk.Widget(box.widget).children {
            gtk_box_remove(typed(box.widget), child.pointer)
            removed += 1
        }
        XCTAssertEqual(removed, 3, "the next child is read before the current one goes")
        XCTAssertNil(Gtk.Widget(box.widget).firstChild)
    }

    func testMeasuringReportsSizesAndABaselineOnlyForText() {
        let label = OwnedObject(retaining: gtk_label_new("Hello")!)
        let text = Gtk.Widget(label.widget).measure(GTK_ORIENTATION_VERTICAL)
        XCTAssertGreaterThan(text.natural, 0)
        XCTAssertNotNil(text.naturalBaseline)
        let box = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!)
        XCTAssertNil(Gtk.Widget(box.widget).measure(GTK_ORIENTATION_VERTICAL).naturalBaseline)
    }

    func testCSSClassesAreAddedAndRemoved() {
        let label = OwnedObject(retaining: gtk_label_new("x")!)
        let widget = Gtk.Widget(label.widget)
        widget.setCSSClass("heading", true)
        XCTAssertTrue(widget.hasCSSClass("heading"))
        widget.setCSSClass("heading", false)
        XCTAssertFalse(widget.hasCSSClass("heading"))
        XCTAssertTrue(widget.isA(gtk_label_get_type()))
        XCTAssertFalse(widget.isA(gtk_box_get_type()))
    }

    // MARK: Properties

    func testStringPropertiesReadAndWriteWithNilAsNone() {
        // A tooltip keeps NULL; a GtkEntry placeholder, once cleared, reads "" (GTK 4.18).
        let label = OwnedObject(retaining: gtk_label_new("x")!)
        let widget = Gtk.Widget(label.widget)
        let tooltip = PropertyKey<String?>("tooltip-text")
        XCTAssertNil(widget[tooltip])
        widget[tooltip] = "Help"
        XCTAssertEqual(widget[tooltip], "Help")
        XCTAssertEqual(swiftString(gtk_widget_get_tooltip_text(label.widget)), "Help", "the widget's own getter agrees")
        widget[tooltip] = nil
        XCTAssertNil(widget[tooltip])
    }

    func testBooleanAndDoublePropertiesReadAndWrite() {
        let entry = OwnedObject(retaining: gtk_entry_new()!)
        let activates = PropertyKey<Bool>("activates-default")
        Gtk.Widget(entry.widget)[activates] = true
        XCTAssertTrue(Gtk.Widget(entry.widget)[activates])
        XCTAssertNotEqual(gtk_entry_get_activates_default(typed(entry.widget)), 0)

        let bar = OwnedObject(retaining: gtk_progress_bar_new()!)
        let fraction = PropertyKey<Double>("fraction")
        Gtk.Widget(bar.widget)[fraction] = 0.25
        XCTAssertEqual(Gtk.Widget(bar.widget)[fraction], 0.25)
        XCTAssertEqual(gtk_progress_bar_get_fraction(bar.opaquePointer), 0.25)
    }

    func testSettingAPropertyToItsValueChangesNothing() {
        let entry = OwnedObject(retaining: gtk_entry_new()!)
        let widget = Gtk.Widget(entry.widget)
        let placeholder = PropertyKey<String?>("placeholder-text")
        var notified = 0
        connectSignal(entry.pointer, "notify::placeholder-text", .instanceAndArgument) { notified += 1 }
        widget[placeholder] = "Name"
        widget[placeholder] = "Name"
        XCTAssertEqual(notified, 1)
    }
}
