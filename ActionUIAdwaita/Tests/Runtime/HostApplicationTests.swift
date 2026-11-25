// Tests/Runtime/HostApplicationTests.swift
/*
 The renderer with an application ActionUI did not make: a host's own GApplication and its own
 windows, as OMC runs on Linux (and an AppKit host on macOS). The window registry finds the host's
 window's content and active window, and forgets a window destroyed; the primary menu's actions go
 on the host's application, the process's default GApplication, once it is registered, with no
 call from the host; Ctrl+Q stays the host's (ActionUI adds no quit action to an application it
 did not start). ActionUI JSON a host window loads from a file has that file's origin.
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

    private static let json = #"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Host"}}]}"#

    private static let commands = #"""
        [{"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [
            {"type": "Button", "id": 4, "properties": {"title": "Run", "actionID": "host.run"}}]}]
        """#

    /// A window of the host's, not ActionUI's: an AdwWindow with the ActionUI JSON's content in it,
    /// registered as the host registers the windows it fills.
    private func makeHostWindow(application: UnsafeMutablePointer<AdwApplication>?) throws -> (UnsafeMutablePointer<GtkWindow>, AdwaitaWindow) {
        _ = try ActionUIModel.shared.loadDescription(from: Data(Self.json.utf8), format: "json", windowUUID: windowUUID)
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

        // The item fires for the ActionUI JSON of the host's active window
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
        // Not by name: the build before registration used up the first numbers.
        XCTAssertFalse(itemActions(map).isEmpty, "a menu button installs the actions")
    }

    /// The names of the menu items' actions on a registered application.
    private func itemActions(_ map: OpaquePointer) -> [String] {
        guard let list = g_action_group_list_actions(map) else { return [] }
        defer { g_strfreev(list) }
        var names: [String] = []
        var index = 0
        while let name = list[index] {
            names.append(String(cString: name))
            index += 1
        }
        return names.filter { $0.hasPrefix("actionui-command-") }
    }

    /// The texts of the labels at or below `widget`, depth first, without empty ones.
    private func labels(_ widget: WidgetPointer) -> [String] {
        var result: [String] = []
        if g_type_check_instance_is_a(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self), gtk_label_get_type()) != 0,
           let text = swiftString(gtk_label_get_text(OpaquePointer(widget))), !text.isEmpty {
            result.append(text)
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            result += labels(current)
            child = gtk_widget_get_next_sibling(current)
        }
        return result
    }

    func testAnItemMovedByARebuildDoesNotShowAnotherItemsShortcut() throws {
        // As OMC's menu: Quit (Ctrl+Q) after appTermination, then a keyed group put in before
        // About once the applet knows it (Add to Desktop). Every item after the new one moves
        // down one place; About, where Quit was, showed Ctrl+Q.
        let application = try makeRegisteredHostApplication("com.abracode.actionui.tests.host.moved")
        defer { release(application) }
        let commands = AppCommands()
        XCTAssertTrue(commands.load(json: #"""
            [{"type": "CommandGroup", "properties": {"placement": "after", "placementTarget": "appTermination"}, "children": [
                {"type": "Button", "id": 3, "properties": {"title": "Quit", "actionID": "host.run", "keyboardShortcut": {"key": "q"}}}]}]
            """#))
        let window: UnsafeMutablePointer<GtkWindow> = typed(gtk_application_window_new(typed(application))!)
        defer { gtk_window_destroy(window) }
        let button = commands.makeMenuButton()
        gtk_window_set_child(window, button)
        XCTAssertTrue(commands.load(json: #"""
            [{"type": "CommandGroup", "properties": {"placement": "before", "placementTarget": "appInfo"}, "children": [
                {"type": "Button", "id": 5, "properties": {"title": "Add to Desktop", "actionID": "host.run"}}]}]
            """#, replacing: "desktop"))

        let map = OpaquePointer(application)
        var shortcuts: [String: String] = [:]
        for index in 0..<g_menu_model_get_n_items(typed(commands.menu.opaquePointer)) {
            guard let section = g_menu_model_get_item_link(typed(commands.menu.opaquePointer), index, "section") else { continue }
            defer { g_object_unref(UnsafeMutableRawPointer(section)) }
            let model = OpaquePointer(section)
            for item in 0..<g_menu_model_get_n_items(typed(model)) {
                guard let label = g_menu_model_get_item_attribute_value(typed(model), item, "label", nil),
                      let action = g_menu_model_get_item_attribute_value(typed(model), item, "action", nil) else { continue }
                let title = swiftString(g_variant_get_string(label, nil)) ?? "?"
                let name = swiftString(g_variant_get_string(action, nil)) ?? "?"
                g_variant_unref(label)
                g_variant_unref(action)
                var accel = ""
                if let list = gtk_application_get_accels_for_action(typed(map), name) {
                    accel = list[0].map { String(cString: $0) } ?? ""
                    g_strfreev(list)
                }
                shortcuts[title.hasPrefix("About ") ? "About" : title] = accel
            }
        }
        XCTAssertEqual(shortcuts, ["Add to Desktop": "", "About": "", "Quit": "<Control>q"], "the application's shortcuts")

        let popover = try XCTUnwrap(gtk_menu_button_get_popover(OpaquePointer(button)))
        let shown = labels(UnsafeMutablePointer<GtkWidget>(OpaquePointer(popover)))
        let about = try XCTUnwrap(shown.firstIndex { $0.hasPrefix("About ") }, "\(shown)")
        XCTAssertNotEqual(shown.indices.contains(about + 1) ? shown[about + 1] : "", "Ctrl+Q", "About shows no shortcut: \(shown)")
        XCTAssertEqual(shown.suffix(2), ["Quit", "Ctrl+Q"], "Quit shows Ctrl+Q: \(shown)")
        withExtendedLifetime(commands) {}
    }

    // MARK: ActionUI JSON in a window the host made (HostWindow, actionUILoadIntoHostWindow*)

    func testAHostWindowIsFilledRegisteredAndSizedAndKeepsItsModelAfterItGoes() throws {
        let application = try makeRegisteredHostApplication("com.abracode.actionui.tests.host.fill")
        defer { release(application) }
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_application_window_new(typed(application))!)
        var destroyed = false
        defer { if !destroyed { gtk_window_destroy(window) } }
        XCTAssertTrue(HostWindow.load(json: Self.json, into: UnsafeMutableRawPointer(window), windowUUID: windowUUID, subtitle: "From the host"))

        // Filled as ActionUI's own windows are: the toolbar view, the content in the toast overlay
        let toolbar = try XCTUnwrap(adw_application_window_get_content(typed(window)))
        XCTAssertNotEqual(g_type_check_instance_is_a(UnsafeMutableRawPointer(toolbar).assumingMemoryBound(to: GTypeInstance.self), adw_toolbar_view_get_type()), 0)
        let overlay = try XCTUnwrap(adw_toolbar_view_get_content(OpaquePointer(toolbar)))
        XCTAssertEqual(adw_toast_overlay_get_child(OpaquePointer(overlay)), WindowRegistry.shared.contentWidget(windowUUID))
        XCTAssertEqual(WindowSubtitle.subtitle(of: window), "From the host")
        let header = try XCTUnwrap(descendant(of: WidgetPointer(OpaquePointer(toolbar)), type: adw_header_bar_get_type()), "a header bar")
        XCTAssertNotNil(descendant(of: header, type: gtk_menu_button_get_type()), "with the primary menu's button")
        XCTAssertNotNil(WindowRegistry.shared.presenter(windowUUID), "the content's modals, alerts and toasts show on it")
        var width: Int32 = 0, height: Int32 = 0
        gtk_window_get_default_size(window, &width, &height)
        XCTAssertGreaterThan(width, 0, "a default size from the content")
        XCTAssertGreaterThan(height, 0)
        XCTAssertEqual(WindowRegistry.shared.gtkWindow(windowUUID), window, "registered")
        // With the height of its bars (header bar and subtitle line), which the window's height includes
        let barsHeight = try XCTUnwrap(WindowRegistry.shared.barsHeight(windowUUID))
        XCTAssertGreaterThan(barsHeight, 0, "the header bar and the subtitle line have a height")
        XCTAssertGreaterThan(height, barsHeight, "the window's default height is the content's plus the bars'")

        // The host closes it: the window leaves the registry, its model stays for the host's code
        gtk_window_destroy(window)
        destroyed = true
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(WindowRegistry.shared.gtkWindow(windowUUID))
        XCTAssertNil(WindowRegistry.shared.barsHeight(windowUUID), "no bars height for a window that is gone")
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID], "the model is the host's to remove")
        ActionUIModel.shared.removeWindow(windowUUID)
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID])
    }

    func testAHostWindowsFileHasTheOriginOfWhereItWasRead() throws {
        let folder = NSTemporaryDirectory() + "actionui-host-origin-\(UUID().uuidString)"
        let resources = folder + "/resources"
        try FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)
        let savedFolder = ActionUIResourceFolder.path
        defer {
            ActionUIConfiguration.updateForTesting { $0.resourceFolder = savedFolder }
            try? FileManager.default.removeItem(atPath: folder)
        }
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = resources }
        try Self.json.write(toFile: resources + "/Main.json", atomically: true, encoding: .utf8)
        try Self.json.write(toFile: folder + "/Other.json", atomically: true, encoding: .utf8)
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        let other: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        let otherUUID = "host-window-origin-outside"
        defer {
            gtk_window_destroy(window)
            gtk_window_destroy(other)
            ActionUIModel.shared.removeWindow(otherUUID)
        }
        XCTAssertTrue(HostWindow.load(url: resources + "/Main.json", into: UnsafeMutableRawPointer(window), windowUUID: windowUUID, subtitle: nil))
        let inside = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 2))
        XCTAssertEqual(inside.trust, .trusted, "\(inside)")
        if case .resource = inside.source {} else { XCTFail("a file in the resource folder: \(inside)") }
        XCTAssertTrue(HostWindow.load(url: "file://" + folder + "/Other.json", into: UnsafeMutableRawPointer(other), windowUUID: otherUUID, subtitle: nil))
        let outside = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: otherUUID, viewID: 2))
        XCTAssertEqual(outside.trust, .lessTrusted, "a file outside the resource folder, as on Apple: \(outside)")
    }

    func testAPlainGtkWindowIsRefusedAndABadJSONShowsWhy() throws {
        // Not an AdwApplicationWindow or AdwWindow: nothing done
        let plain: UnsafeMutablePointer<GtkWindow> = typed(gtk_window_new()!)
        defer { gtk_window_destroy(plain) }
        XCTAssertFalse(HostWindow.load(json: Self.json, into: UnsafeMutableRawPointer(plain), windowUUID: windowUUID, subtitle: nil))
        XCTAssertNil(WindowRegistry.shared.gtkWindow(windowUUID))
        XCTAssertNil(gtk_window_get_child(plain))

        // ActionUI JSON that does not load: false, and the window shows why
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        defer { gtk_window_destroy(window) }
        XCTAssertFalse(HostWindow.load(json: "{ not json", into: UnsafeMutableRawPointer(window), windowUUID: windowUUID, subtitle: nil))
        let toolbar = try XCTUnwrap(adw_window_get_content(typed(window)))
        let overlay = try XCTUnwrap(adw_toolbar_view_get_content(OpaquePointer(toolbar)))
        let shown = try XCTUnwrap(adw_toast_overlay_get_child(OpaquePointer(overlay)))
        XCTAssertNotEqual(g_type_check_instance_is_a(UnsafeMutableRawPointer(shown).assumingMemoryBound(to: GTypeInstance.self), gtk_label_get_type()), 0, "the error, as a label")
        XCTAssertNil(WindowRegistry.shared.contentWidget(windowUUID), "no content")
    }
}
