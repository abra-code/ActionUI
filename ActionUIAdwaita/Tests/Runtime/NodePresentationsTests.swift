// Tests/Runtime/NodePresentationsTests.swift
/*
 Tests for NodePresentations, the sheet, full-screen cover and popover an element declares, in a
 window on screen: a Button's click shows its sheet, closing it sets the state false and fires
 sheetOnDismissActionID once, and a state the host sets false closes it and fires the action too; a
 full-screen cover is a dialog as well; a Button's popover sits on the side its arrow edge names,
 its clicks show and hide it and popoverActionID fires as it shows; a click on a Text toggles its
 popover; the user's close sets the state false; a node that leaves the tree takes its
 presentations down without an action, and a removed element's open popover is released with
 its node; the host's close of a window showing a sheet closes the window.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodePresentationsTests: XCTestCase {
    private var windowUUID = ""
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var renderTree: AdwaitaWindow?
    private var fired: [String] = []
    private var actionIDs: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "node-presentations-\(name)"
        fired = []
    }

    override func tearDown() async throws {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        for actionID in actionIDs {
            ActionUIModel.shared.unregisterActionHandler(for: actionID)
        }
        actionIDs = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    /// `json` in a window on screen.
    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_set_default_size(window, 480, 360)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    private func record(_ actionID: String) {
        actionIDs.append(actionID)
        ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(id) }
        }
    }

    private func state(_ viewID: Int, _ key: String) -> Bool? {
        ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: viewID, key: key) as? Bool
    }

    private func wait(_ condition: () -> Bool) -> Bool {
        AdwaitaTestHost.runMainLoop(until: condition, timeoutMilliseconds: 3000)
    }

    /// Emits a GtkGestureClick's "released" (one press at 1, 1), as the user's click would.
    private func release(_ gesture: UnsafeMutableRawPointer) {
        let type = gesture.assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type
        let id = g_signal_lookup("released", type)
        precondition(id != 0)
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], type)
        g_value_set_object(&values[0], gesture)
        g_value_init(&values[1], GType(6 << 2))  // G_TYPE_INT
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], GType(15 << 2))  // G_TYPE_DOUBLE
        g_value_set_double(&values[2], 1)
        g_value_init(&values[3], GType(15 << 2))
        g_value_set_double(&values[3], 1)
        g_signal_emitv(&values, id, 0, nil)
        for index in values.indices {
            g_value_unset(&values[index])
        }
    }

    /// The first GtkGestureClick on `widget`.
    private func clickGesture(on widget: WidgetPointer) -> UnsafeMutableRawPointer? {
        let controllers = gtk_widget_observe_controllers(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_gesture_click_get_type()) != 0 {
                return item
            }
        }
        return nil
    }

    // MARK: Sheets

    private static let sheetDocument = #"""
        {"type": "VStack", "id": 1, "children": [
            {"type": "Button", "id": 2, "properties": {"title": "Show", "sheetOnDismissActionID": "test.dismissed"},
             "sheet": {"type": "Text", "id": 20, "properties": {"text": "In the sheet"}}},
            {"type": "Button", "id": 3, "properties": {"title": "Cover", "fullScreenCoverOnDismissActionID": "test.cover"},
             "fullScreenCover": {"type": "Text", "id": 30, "properties": {"text": "In the cover"}}}
        ]}
        """#

    func testAButtonsClickShowsItsSheetAndClosingItFiresTheDismissActionOnce() throws {
        let root = try present(Self.sheetDocument)
        record("test.dismissed")
        let button = try XCTUnwrap(root.childNodes[2])
        let presentations = try XCTUnwrap(button.presentations)
        AdwaitaTestHost.emit("clicked", on: button.widget)
        XCTAssertEqual(state(2, "sheetVisible"), true)
        XCTAssertTrue(wait { presentations.root(.sheet) != nil })
        let text = try XCTUnwrap(presentations.root(.sheet)?.widget)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(text))), "In the sheet")
        XCTAssertTrue(wait { gtk_widget_get_mapped(text) != 0 }, "shown over the window")

        let dialog: UnsafeMutablePointer<AdwDialog> = typed(try XCTUnwrap(presentations.widget(.sheet)))
        XCTAssertNotEqual(adw_dialog_close(dialog), 0, "as the dialog's close button does")
        XCTAssertTrue(wait { presentations.root(.sheet) == nil })
        XCTAssertEqual(state(2, "sheetVisible"), false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.dismissed"])
    }

    func testAStateTheHostSetsFalseClosesTheSheetAndFiresTheDismissAction() throws {
        let root = try present(Self.sheetDocument)
        record("test.dismissed")
        let presentations = try XCTUnwrap(root.childNodes[2]?.presentations)
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 2, key: "sheetVisible", value: true))
        XCTAssertTrue(wait { presentations.root(.sheet) != nil }, "the host can show it too")
        let dialog = try XCTUnwrap(presentations.widget(.sheet))
        // Held, so it can be asked about once the node lets it go.
        g_object_ref(dialog)
        defer { g_object_unref(dialog) }
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 2, key: "sheetVisible", value: false))
        XCTAssertTrue(wait { presentations.root(.sheet) == nil && gtk_widget_get_parent(dialog) == nil })
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.dismissed"], "any dismissal fires it, once")
    }

    func testAFullScreenCoverIsADialogToo() throws {
        let root = try present(Self.sheetDocument)
        record("test.cover")
        let button = try XCTUnwrap(root.childNodes[3])
        let presentations = try XCTUnwrap(button.presentations)
        AdwaitaTestHost.emit("clicked", on: button.widget)
        XCTAssertTrue(wait { presentations.root(.fullScreenCover) != nil })
        let widget = try XCTUnwrap(presentations.widget(.fullScreenCover))
        XCTAssertTrue(Gtk.Widget(widget).isA(adw_dialog_get_type()))
        XCTAssertNotEqual(adw_dialog_close(typed(widget)), 0)
        XCTAssertTrue(wait { presentations.root(.fullScreenCover) == nil })
        XCTAssertEqual(state(3, "fullScreenCoverVisible"), false)
        XCTAssertEqual(fired, ["test.cover"])
    }

    // MARK: Popovers

    private static let popoverDocument = #"""
        {"type": "VStack", "id": 1, "children": [
            {"type": "Button", "id": 2, "properties": {"title": "Pop", "popoverArrowEdge": "bottom", "popoverActionID": "test.shown"},
             "popover": {"type": "Text", "id": 20, "properties": {"text": "In the popover"}}},
            {"type": "Text", "id": 3, "properties": {"text": "Tap me", "popoverArrowEdge": "trailing"},
             "popover": {"type": "Text", "id": 30, "properties": {"text": "Text's popover"}}}
        ]}
        """#

    func testAButtonsPopoverSitsWhereItsArrowEdgeSaysAndItsClicksShowAndHideIt() throws {
        let root = try present(Self.popoverDocument)
        record("test.shown")
        let button = try XCTUnwrap(root.childNodes[2])
        let presentations = try XCTUnwrap(button.presentations)
        AdwaitaTestHost.emit("clicked", on: button.widget)
        XCTAssertTrue(wait { presentations.root(.popover) != nil })
        let popover = try XCTUnwrap(presentations.widget(.popover))
        XCTAssertEqual(gtk_popover_get_position(typed(popover)), GTK_POS_TOP, "an arrow at the bottom: the popover above")
        XCTAssertTrue(gtk_widget_get_parent(popover) == button.outerWidget, "on the element's box")
        let text = try XCTUnwrap(presentations.root(.popover)?.widget)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(text))), "In the popover")
        XCTAssertEqual(fired, ["test.shown"])

        AdwaitaTestHost.emit("clicked", on: button.widget)
        XCTAssertEqual(state(2, "popoverVisible"), false, "a second click hides it")
        XCTAssertTrue(wait { presentations.root(.popover) == nil })
        XCTAssertEqual(fired, ["test.shown"], "fired as it shows only")
    }

    func testAClickOnATextTogglesItsPopoverAndTheUsersCloseSetsTheStateFalse() throws {
        let root = try present(Self.popoverDocument)
        let text = try XCTUnwrap(root.childNodes[3])
        let presentations = try XCTUnwrap(text.presentations)
        let gesture = try XCTUnwrap(clickGesture(on: text.outerWidget))
        release(gesture)
        XCTAssertEqual(state(3, "popoverVisible"), true)
        XCTAssertTrue(wait { presentations.root(.popover) != nil })
        let popover = try XCTUnwrap(presentations.widget(.popover))
        XCTAssertEqual(gtk_popover_get_position(typed(popover)), GTK_POS_LEFT, "an arrow at the trailing edge: the popover before")

        // As a click outside it does.
        gtk_popover_popdown(typed(popover))
        XCTAssertTrue(wait { presentations.root(.popover) == nil })
        XCTAssertEqual(state(3, "popoverVisible"), false)
        XCTAssertNil(clickGesture(on: try XCTUnwrap(root.childNodes[2]).outerWidget), "a Button toggles through its click")
    }

    // MARK: Leaving the tree

    func testANodeThatLeavesTheTreeTakesItsPresentationsDownWithoutAnAction() throws {
        let root = try present(Self.sheetDocument)
        record("test.dismissed")
        let presentations = try XCTUnwrap(root.childNodes[2]?.presentations)
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 2, key: "sheetVisible", value: true))
        XCTAssertTrue(wait { presentations.root(.sheet) != nil })
        renderTree?.detach()
        XCTAssertNil(presentations.root(.sheet))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, [])
        XCTAssertEqual(state(2, "sheetVisible"), true, "the state stays")
    }

    func testARemovedElementsOpenPopoverIsReleasedWithItsNode() throws {
        let root = try present(Self.popoverDocument)
        let model = try XCTUnwrap(root.childNodes[3]?.model)
        model.states["popoverVisible"] = true
        XCTAssertTrue(wait { root.childNodes[3]?.presentations?.widget(.popover).map { gtk_widget_get_mapped($0) != 0 } ?? false })
        let popover = try XCTUnwrap(root.childNodes[3]?.presentations?.widget(.popover))
        // A heap slot: GLib writes NULL into it when the popover is finalized.
        let slot = UnsafeMutablePointer<gpointer?>.allocate(capacity: 1)
        defer { slot.deallocate() }
        slot.pointee = UnsafeMutableRawPointer(popover)
        g_object_add_weak_pointer(typed(OpaquePointer(popover)), slot)
        weak let removed = root.childNodes[3]
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 3)
        // The node and its box go in the flush, before the popover's queued unparent runs.
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(removed)
        XCTAssertNil(slot.pointee, "the popover was released")
        if let alive = slot.pointee {
            g_object_remove_weak_pointer(typed(OpaquePointer(alive)), slot)
        }
        XCTAssertEqual(model.states["popoverVisible"] as? Bool, true, "the state stays")
    }

    func testTheHostsCloseOfAWindowShowingASheetClosesTheWindow() throws {
        let app = AdwaitaApplication()
        let uuid = "node-presentations-app"
        var events: [String] = []
        var shown = false
        var stillOpen = true
        app.handlers.windowWillClose = { events.append("close \($0)") }
        actionIDs.append("test.dismissed")
        ActionUIModel.shared.registerActionHandler(for: "test.dismissed") { id, _, _, _, _ in
            MainActor.assumeIsolated { events.append(id) }
        }
        app.handlers.didFinishLaunching = {
            // A watchdog: a window that stays open fails the test instead of hanging it.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.presentWindow(json: Data(Self.sheetDocument.utf8), windowUUID: uuid, title: nil)
            _ = ActionUIModel.shared.setElementState(windowUUID: uuid, viewID: 2, key: "sheetVisible", value: true)
            _ = runAfter(milliseconds: 300) {
                shown = app.gtkWindow(uuid).flatMap { adw_application_window_get_visible_dialog(typed($0)) } != nil
                // AdwDialogHost would close the sheet instead of the window.
                app.closeWindow(uuid)
                stillOpen = app.gtkWindow(uuid) != nil
            }
        }
        XCTAssertEqual(app.run(), 0, "the last window closed: the application ended")
        ActionUIModel.shared.windowModels[uuid] = nil
        XCTAssertTrue(shown)
        XCTAssertFalse(stillOpen)
        XCTAssertEqual(events, ["close \(uuid)"], "no dismiss action fired")
    }

    func testPresentationsTakenDownAreRestoredFromTheirStates() throws {
        let root = try present(Self.sheetDocument)
        record("test.dismissed")
        let presentations = try XCTUnwrap(root.childNodes[2]?.presentations)
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 2, key: "sheetVisible", value: true))
        XCTAssertTrue(wait { presentations.root(.sheet) != nil })
        root.takeDownPresentations()
        XCTAssertNil(presentations.root(.sheet))
        root.restorePresentations()
        XCTAssertNotNil(presentations.root(.sheet), "a window that did not close shows its sheet again")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, [])
    }
}
