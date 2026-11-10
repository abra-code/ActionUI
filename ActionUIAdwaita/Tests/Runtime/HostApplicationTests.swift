// Tests/Runtime/HostApplicationTests.swift
/*
 The renderer with an application ActionUI did not make: a host's own GApplication and its own
 windows, as OMC runs on Linux (and an AppKit host on macOS). The window registry finds the host's
 window's content and active window, and forgets a window destroyed; the primary menu's actions go
 on the host's application, the process's default GApplication, once it is registered, with no
 call from the host; Ctrl+Q stays the host's (ActionUI adds no quit action to an application it
 did not start).
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class HostApplicationTests: XCTestCase {
    private var fired: [(actionID: String, windowUUID: String)] = []
    private let windowUUID = "host-window-1"

    override func setUp() async throws {
        // No super.setUp(): see AppCommandsTests.
        try AdwaitaTestHost.initialize()
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "host.run") { [weak self] actionID, windowUUID, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append((actionID, windowUUID)) }
        }
    }

    override func tearDown() async throws {
        ActionUIModel.shared.unregisterActionHandler(for: "host.run")
        ActionUIModel.shared.removeWindow(windowUUID)
    }

    private static let document = #"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Host"}}]}"#

    private static let commands = #"""
        [{"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [
            {"type": "Button", "id": 4, "properties": {"title": "Run", "actionID": "host.run"}}]}]
        """#

    /// A window of the host's, not ActionUI's: an AdwWindow with the document's content in it,
    /// registered as the host registers the windows it fills.
    private func makeHostWindow(application: UnsafeMutablePointer<AdwApplication>?) throws -> (UnsafeMutablePointer<GtkWindow>, AdwaitaWindow) {
        _ = try ActionUIModel.shared.loadDescription(from: Data(Self.document.utf8), format: "json", windowUUID: windowUUID)
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
        let renderTree = AdwaitaWindow(windowModel: windowModel)
        let content = try XCTUnwrap(renderTree.contentWidget)
        let window: UnsafeMutablePointer<GtkWindow>
        if let application {
            window = typed(adw_application_window_new(typed(application))!)
            adw_application_window_set_content(typed(window), content)
        } else {
            window = typed(adw_window_new()!)
            adw_window_set_content(typed(window), content)
        }
        WindowRegistry.shared.register(windowUUID, window: window, renderTree: renderTree)
        return (window, renderTree)
    }

    /// A host's application, registered and the process's default, as a host's own is from its
    /// "startup" on; nil (the test skips) where it cannot register.
    private func makeRegisteredHostApplication(_ id: String) throws -> UnsafeMutablePointer<AdwApplication> {
        let application = adw_application_new(id, applicationNonUnique)!
        g_application_set_default(typed(application))
        var error: UnsafeMutablePointer<GError>?
        guard g_application_register(typed(application), nil, &error) != 0 else {
            let message = error.flatMap { swiftString($0.pointee.message) } ?? "unknown"
            if let error { g_error_free(error) }
            g_application_set_default(nil)
            g_object_unref(UnsafeMutableRawPointer(application))
            throw XCTSkip("the host application could not register: \(message)")
        }
        return application
    }

    /// The first widget of `type` at or below `widget`, depth first.
    private func descendant(of widget: WidgetPointer, type: GType) -> WidgetPointer? {
        if g_type_check_instance_is_a(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self), type) != 0 {
            return widget
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = descendant(of: current, type: type) {
                return found
            }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func release(_ application: UnsafeMutablePointer<AdwApplication>) {
        if g_application_get_default() == UnsafeMutablePointer<GApplication>(OpaquePointer(application)) {
            g_application_set_default(nil)
        }
        g_object_unref(UnsafeMutableRawPointer(application))
    }

    func testTheRegistryFindsAHostWindowsContentAndForgetsItAfterwards() throws {
        let (window, renderTree) = try makeHostWindow(application: nil)
        defer { gtk_window_destroy(window) }
        XCTAssertEqual(WindowRegistry.shared.gtkWindow(windowUUID), window)
        XCTAssertEqual(WindowRegistry.shared.contentWidget(windowUUID), renderTree.contentWidget)
        XCTAssertEqual(WindowRegistry.shared.windowUUID(of: window), windowUUID)
        XCTAssertNotNil(ActionUIModel.shared.contentSizeLimits(windowUUID: windowUUID),
                        "the content size limits of a window the host made")

        // A newer window under the same UUID stays when the older one is unregistered
        let newer: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        defer { gtk_window_destroy(newer) }
        WindowRegistry.shared.register(windowUUID, window: newer, renderTree: nil)
        WindowRegistry.shared.unregister(windowUUID, window: window)
        XCTAssertEqual(WindowRegistry.shared.gtkWindow(windowUUID), newer)
        WindowRegistry.shared.unregister(windowUUID, window: newer)
        XCTAssertNil(WindowRegistry.shared.gtkWindow(windowUUID))
        XCTAssertNil(ActionUIModel.shared.contentSizeLimits(windowUUID: windowUUID), "none once it is gone")
        XCTAssertEqual(WindowRegistry.shared.windowUUID(of: window), "")
    }

    func testTheMenuGoesOnTheHostsRegisteredApplicationWithNoCall() throws {
        let application = try makeRegisteredHostApplication("com.abracode.actionui.tests.host.menu")
        defer { release(application) }
        let commands = AppCommands()
        XCTAssertTrue(commands.load(json: Self.commands))
        let map = OpaquePointer(application)
        XCTAssertNotNil(g_action_map_lookup_action(map, "actionui-command-0"), "the item's action is on the host's application")
        XCTAssertNil(g_action_map_lookup_action(map, "actionui-quit"), "no quit action: quitting is the host's")
        if let accels = gtk_application_get_accels_for_action(typed(map), "app.actionui-quit") {
            XCTAssertNil(accels[0], "and no Ctrl+Q of ActionUI's")
            g_strfreev(accels)
        }

        // The item fires for the document of the host's active window
        let (window, _) = try makeHostWindow(application: application)
        defer {
            WindowRegistry.shared.unregister(windowUUID, window: window)
            gtk_window_destroy(window)
        }
        gtk_window_present(window)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_application_get_active_window(typed(map)) == window }),
                      "the host's window becomes its application's active window")
        g_action_activate(try XCTUnwrap(g_action_map_lookup_action(map, "actionui-command-0")), nil)
        XCTAssertEqual(fired.map(\.actionID), ["host.run"])
        XCTAssertEqual(fired.first?.windowUUID, windowUUID)
        withExtendedLifetime(commands) {}
    }

    func testAWindowDestroyedWithoutUnregisteringIsForgotten() throws {
        let (window, _) = try makeHostWindow(application: nil)
        XCTAssertEqual(WindowRegistry.shared.gtkWindow(windowUUID), window)
        gtk_window_destroy(window)
        XCTAssertNil(WindowRegistry.shared.gtkWindow(windowUUID), "no pointer to a freed window is left")
        XCTAssertNil(ActionUIModel.shared.contentSizeLimits(windowUUID: windowUUID))
    }

    func testAnApplicationNotRegisteredYetGetsTheMenuWithTheFirstMenuButton() throws {
        let application = adw_application_new("com.abracode.actionui.tests.host.late", applicationNonUnique)!
        g_application_set_default(typed(application))
        defer { release(application) }
        let commands = AppCommands()
        XCTAssertTrue(commands.load(json: Self.commands))
        let map = OpaquePointer(application)
        XCTAssertNil(g_action_map_lookup_action(map, "actionui-command-0"), "not before it is registered")

        var error: UnsafeMutablePointer<GError>?
        guard g_application_register(typed(application), nil, &error) != 0 else {
            if let error { g_error_free(error) }
            throw XCTSkip("the host application could not register")
        }
        let button = commands.makeMenuButton()
        g_object_ref_sink(UnsafeMutableRawPointer(button))
        g_object_unref(UnsafeMutableRawPointer(button))
        XCTAssertNotNil(g_action_map_lookup_action(map, "actionui-command-0"), "a menu button installs the actions")
    }

    // MARK: A document in a window the host made (HostWindow, actionUILoadIntoHostWindow*)

    func testAHostWindowIsFilledRegisteredAndSizedAndKeepsItsModelAfterItGoes() throws {
        let application = try makeRegisteredHostApplication("com.abracode.actionui.tests.host.fill")
        defer { release(application) }
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_application_window_new(typed(application))!)
        var destroyed = false
        defer { if !destroyed { gtk_window_destroy(window) } }
        XCTAssertTrue(HostWindow.load(json: Self.document, into: UnsafeMutableRawPointer(window), windowUUID: windowUUID, subtitle: "From the host"))

        // Filled as ActionUI's own windows are: the toolbar view, the document in the toast overlay
        let toolbar = try XCTUnwrap(adw_application_window_get_content(typed(window)))
        XCTAssertNotEqual(g_type_check_instance_is_a(UnsafeMutableRawPointer(toolbar).assumingMemoryBound(to: GTypeInstance.self), adw_toolbar_view_get_type()), 0)
        let overlay = try XCTUnwrap(adw_toolbar_view_get_content(OpaquePointer(toolbar)))
        XCTAssertEqual(adw_toast_overlay_get_child(OpaquePointer(overlay)), WindowRegistry.shared.contentWidget(windowUUID))
        XCTAssertEqual(WindowSubtitle.subtitle(of: window), "From the host")
        let header = try XCTUnwrap(descendant(of: WidgetPointer(OpaquePointer(toolbar)), type: adw_header_bar_get_type()), "a header bar")
        XCTAssertNotNil(descendant(of: header, type: gtk_menu_button_get_type()), "with the primary menu's button")
        XCTAssertNotNil(WindowRegistry.shared.presenter(windowUUID), "the document's modals, alerts and toasts show on it")
        var width: Int32 = 0, height: Int32 = 0
        gtk_window_get_default_size(window, &width, &height)
        XCTAssertGreaterThan(width, 0, "a default size from the document")
        XCTAssertGreaterThan(height, 0)
        XCTAssertEqual(WindowRegistry.shared.gtkWindow(windowUUID), window, "registered")

        // The host closes it: the window leaves the registry, its model stays for the host's code
        gtk_window_destroy(window)
        destroyed = true
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(WindowRegistry.shared.gtkWindow(windowUUID))
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID], "the model is the host's to remove")
        ActionUIModel.shared.removeWindow(windowUUID)
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID])
    }

    func testAPlainGtkWindowIsRefusedAndABadDocumentShowsWhy() throws {
        // Not an AdwApplicationWindow or AdwWindow: nothing done
        let plain: UnsafeMutablePointer<GtkWindow> = typed(gtk_window_new()!)
        defer { gtk_window_destroy(plain) }
        XCTAssertFalse(HostWindow.load(json: Self.document, into: UnsafeMutableRawPointer(plain), windowUUID: windowUUID, subtitle: nil))
        XCTAssertNil(WindowRegistry.shared.gtkWindow(windowUUID))
        XCTAssertNil(gtk_window_get_child(plain))

        // A document that does not load: false, and the window shows why
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        defer { gtk_window_destroy(window) }
        XCTAssertFalse(HostWindow.load(json: "{ not json", into: UnsafeMutableRawPointer(window), windowUUID: windowUUID, subtitle: nil))
        let toolbar = try XCTUnwrap(adw_window_get_content(typed(window)))
        let overlay = try XCTUnwrap(adw_toolbar_view_get_content(OpaquePointer(toolbar)))
        let shown = try XCTUnwrap(adw_toast_overlay_get_child(OpaquePointer(overlay)))
        XCTAssertNotEqual(g_type_check_instance_is_a(UnsafeMutableRawPointer(shown).assumingMemoryBound(to: GTypeInstance.self), gtk_label_get_type()), 0, "the error, as a label")
        XCTAssertNil(WindowRegistry.shared.contentWidget(windowUUID), "no document content")
    }
}
