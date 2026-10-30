// Tests/Runtime/ViewShortcutTests.swift
/*
 Tests for keyboardShortcut on a view (ViewShortcut): a managed-scope shortcut controller on the
 element's widget with the accelerator the menu commands use (command as Ctrl, an empty list the
 bare key); its action activates the widget, so a Button fires its action; a changed shortcut
 replaces the controller and a removed one takes it away; a bare-Return button is the window's
 default widget, so Return in a text field presses it.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ViewShortcutTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "view-shortcut-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.save") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.save")
    }

    /// `json` in a window on screen (a button activates only once realized).
    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    private let button = #"""
        {"type": "Button", "id": 1, "properties": {"title": "Save", "actionID": "test.save", "keyboardShortcut": {"key": "s"}}}
        """#

    func testAButtonsShortcutIsAManagedControllerThatFiresItsAction() throws {
        let node = try present(button)
        let installed = try XCTUnwrap(attached(on: UnsafeMutableRawPointer(node.widget), key: ViewShortcut.installedKey))
        XCTAssertEqual(installed.accelerator, "<Control>s", "no modifiers given: command, Ctrl on Linux")
        XCTAssertEqual(gtk_shortcut_controller_get_scope(installed.controller), GTK_SHORTCUT_SCOPE_MANAGED)
        let shortcuts = installed.controller
        XCTAssertEqual(g_list_model_get_n_items(shortcuts), 1)
        let shortcut = try XCTUnwrap(g_list_model_get_item(shortcuts, 0))
        defer { g_object_unref(shortcut) }
        let action = try XCTUnwrap(gtk_shortcut_get_action(OpaquePointer(shortcut)))
        // What the key does: the widget activated, the button pressed and clicked.
        XCTAssertNotEqual(gtk_shortcut_action_activate(action, GtkShortcutActionFlags(0), node.widget, nil), 0)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { fired == ["test.save"] }), "fired: \(fired)")
    }

    func testAChangedShortcutReplacesTheControllerAndARemovedOneGoes() throws {
        let node = try present(button)
        let first = try XCTUnwrap(attached(on: UnsafeMutableRawPointer(node.widget), key: ViewShortcut.installedKey))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "keyboardShortcut",
                                                value: ["key": "return", "modifiers": [String]()] as [String: Any])
        AdwaitaTestHost.drainMainLoop()
        let second = try XCTUnwrap(attached(on: UnsafeMutableRawPointer(node.widget), key: ViewShortcut.installedKey))
        XCTAssertEqual(second.accelerator, "Return", "an empty list: the bare key")
        XCTAssertFalse(first === second)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "keyboardShortcut", value: "none")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(attached(on: UnsafeMutableRawPointer(node.widget), key: ViewShortcut.installedKey))
    }

    func testASwitchTogglesShortcutIsOnTheSwitchWhichItToggles() throws {
        let node = try present(#"""
            {"type": "Toggle", "id": 1, "properties": {"title": "Wi-Fi", "style": "switch", "keyboardShortcut": {"key": "t"}}}
            """#)
        // The element's widget is the box holding the title and the switch; the box has nothing to
        // activate.
        let control = Toggle.accessibleWidget(node.widget)
        XCTAssertNil(attached(on: UnsafeMutableRawPointer(node.widget), key: ViewShortcut.installedKey))
        let installed = try XCTUnwrap(attached(on: UnsafeMutableRawPointer(control), key: ViewShortcut.installedKey))
        let shortcut = try XCTUnwrap(g_list_model_get_item(installed.controller, 0))
        defer { g_object_unref(shortcut) }
        let action = try XCTUnwrap(gtk_shortcut_get_action(OpaquePointer(shortcut)))
        XCTAssertNotEqual(gtk_shortcut_action_activate(action, GtkShortcutActionFlags(0), control, nil), 0)
        // With animations on, an activated GtkSwitch changes state only when its 100 ms toggle
        // animation ends, on the frame clock: wait for the value rather than drain the loop once.
        let value = { ActionUIModel.shared.windowModels[self.windowUUID]?.viewModels[1]?.value as? Bool }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { value() == true }), "value: \(String(describing: value()))")
    }

    func testAReturnButtonIsTheWindowsDefaultSoReturnInATextFieldPressesIt() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"placeholder": "Name"}},
              {"type": "Button", "id": 3, "properties": {"title": "OK", "actionID": "test.save", "keyboardShortcut": {"key": "return", "modifiers": []}}}]}
            """#)
        let button = try XCTUnwrap(root.childNodes[3])
        let window = try XCTUnwrap(gtkWindow)
        XCTAssertTrue(gtk_window_get_default_widget(window) == button.widget, "the default button")
        // Return in the field: it leaves Return to the window, whose default widget is pressed.
        let field = try XCTUnwrap(root.childNodes[2])
        let entry = try XCTUnwrap(Self.descendant(of: field.widget, type: gtk_text_get_type()))
        // What Return in the field emits.
        AdwaitaTestHost.emit("activate", on: UnsafeMutableRawPointer(entry))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { fired == ["test.save"] }), "fired: \(fired)")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "keyboardShortcut", value: "none")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(gtk_window_get_default_widget(window), "no longer the default without the shortcut")
    }

    /// `widget` or its first descendant of `type`, depth first.
    private static func descendant(of widget: WidgetPointer, type: GType) -> WidgetPointer? {
        if Gtk.Widget(widget).isA(type) { return widget }
        for child in Array(Gtk.Widget(widget).children) {
            if let found = descendant(of: child.pointer, type: type) { return found }
        }
        return nil
    }

    func testCoreShortcutsMapLikeMenuShortcuts() {
        XCTAssertEqual(AppCommands.accelerator(key: "s", modifiers: [.command, .shift]), "<Control><Shift>s")
        XCTAssertEqual(AppCommands.accelerator(key: "escape", modifiers: []), "Escape")
        XCTAssertEqual(AppCommands.accelerator(key: "clear", modifiers: [.option]), "<Alt>Clear")
        XCTAssertEqual(AppCommands.accelerator(key: "k", modifiers: [.capslock]), "<Control>k", "Caps Lock alone: not the bare key")
    }
}
