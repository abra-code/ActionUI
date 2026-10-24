// Tests/Runtime/AppCommandsTests.swift
/*
 Tests for the application's commands on Linux (AppCommands): the primary menu's sections (the
 top targets' groups, each CommandMenu as a submenu, then the bottom targets and About), placement
 before, after and replacing (a childless replacing group removing About), Dividers as sections;
 keyboardShortcut as GTK accelerators; an item's action firing its actionID with the element's id;
 a disabled item's action disabled; Ctrl+Q quitting; a WindowGroup document as its content, its
 title and its commands (its platform overrides applied), loaded once per group.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class AppCommandsTests: XCTestCase {
    private var fired: [(actionID: String, viewID: Int)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        fired = []
        for id in ["test.new", "test.run", "test.about"] {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, viewID, _, _ in
                MainActor.assumeIsolated { self?.fired.append((actionID, viewID)) }
            }
        }
    }

    override func tearDown() async throws {
        for id in ["test.new", "test.run", "test.about"] {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
    }

    /// The menu as text: a section as "[...]", a submenu as "Name>[...]", an item as its label.
    private func outline(_ model: OpaquePointer) -> [String] {
        var lines: [String] = []
        for index in 0..<g_menu_model_get_n_items(typed(model)) {
            if let section = g_menu_model_get_item_link(typed(model), index, "section") {
                lines.append("[" + outline(OpaquePointer(section)).joined(separator: ", ") + "]")
                g_object_unref(UnsafeMutableRawPointer(section))
            } else if let submenu = g_menu_model_get_item_link(typed(model), index, "submenu") {
                lines.append(label(model, index) + ">[" + outline(OpaquePointer(submenu)).joined(separator: ", ") + "]")
                g_object_unref(UnsafeMutableRawPointer(submenu))
            } else {
                lines.append(label(model, index))
            }
        }
        return lines
    }

    private func label(_ model: OpaquePointer, _ index: Int32) -> String {
        guard let value = g_menu_model_get_item_attribute_value(typed(model), index, "label", nil) else { return "?" }
        defer { g_variant_unref(value) }
        return swiftString(g_variant_get_string(value, nil)) ?? "?"
    }

    /// The action name an item at `path` (indexes through sections and submenus) activates.
    private func actionName(_ model: OpaquePointer, _ path: [Int32]) -> String? {
        var current = model
        var owned: [UnsafeMutableRawPointer] = []
        defer { owned.forEach { g_object_unref($0) } }
        for index in path.dropLast() {
            guard let link = g_menu_model_get_item_link(typed(current), index, "section")
                    ?? g_menu_model_get_item_link(typed(current), index, "submenu") else { return nil }
            owned.append(UnsafeMutableRawPointer(link))
            current = OpaquePointer(link)
        }
        guard let value = g_menu_model_get_item_attribute_value(typed(current), path.last!, "action", nil) else { return nil }
        defer { g_variant_unref(value) }
        return swiftString(g_variant_get_string(value, nil))
    }

    private static let commands = #"""
        [{"type": "CommandMenu", "id": 4, "properties": {"name": "Tools"}, "children": [
            {"type": "Button", "id": 5, "properties": {"title": "New Action", "actionID": "test.new",
             "keyboardShortcut": {"key": "N", "modifiers": ["command", "shift"]}}},
            {"type": "Divider", "id": 6},
            {"type": "Button", "id": 7, "properties": {"title": "Run", "actionID": "test.run", "disabled": true}}]},
         {"type": "CommandGroup", "id": 8, "properties": {"placement": "after", "placementTarget": "appInfo"}, "children": [
            {"type": "Button", "id": 9, "properties": {"title": "About Module", "actionID": "test.about"}}]},
         {"type": "CommandGroup", "id": 10, "properties": {"placement": "before", "placementTarget": "newItem"}, "children": [
            {"type": "Button", "id": 11, "properties": {"title": "Open Recent"}}]}]
        """#

    func testTheMenuHasTheTopGroupsTheCommandMenusAndAboutLast() {
        let application = adw_application_new("com.abracode.actionui.tests.commands", G_APPLICATION_NON_UNIQUE)!
        defer { g_object_unref(UnsafeMutableRawPointer(application)) }
        let commands = AppCommands()
        commands.start(typed(application), name: "Demo")
        XCTAssertTrue(commands.load(json: Self.commands))
        XCTAssertEqual(outline(commands.menu.opaquePointer), [
            "[Open Recent]",
            "[Tools>[[New Action], [Run]]]",
            "[About Demo, About Module]",
        ])
    }

    func testAChildlessReplacingGroupRemovesAbout() {
        let commands = AppCommands()
        XCTAssertTrue(commands.load(json: #"[{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "appInfo"}}]"#))
        XCTAssertEqual(outline(commands.menu.opaquePointer), [])
        XCTAssertFalse(commands.load(json: #"{"type": "CommandMenu"}"#), "not an array")
    }

    func testAnItemsActionFiresWithTheElementsIDAndADisabledOneIsDisabled() throws {
        let application = adw_application_new("com.abracode.actionui.tests.actions", G_APPLICATION_NON_UNIQUE)!
        defer { g_object_unref(UnsafeMutableRawPointer(application)) }
        let commands = AppCommands()
        commands.start(typed(application), name: "Demo")
        commands.load(json: Self.commands)
        let menu = commands.menu.opaquePointer
        // Tools is the second section's only item, a submenu of two sections.
        let newAction = try XCTUnwrap(actionName(menu, [1, 0, 0, 0]))
        let runAction = try XCTUnwrap(actionName(menu, [1, 0, 1, 0]))
        XCTAssertTrue(newAction.hasPrefix("app."))
        // The application is not registered (not run), so its actions are reached through the map.
        let map = OpaquePointer(application)
        g_action_activate(try XCTUnwrap(g_action_map_lookup_action(map, String(newAction.dropFirst(4)))), nil)
        XCTAssertEqual(fired.map(\.actionID), ["test.new"])
        XCTAssertEqual(fired.first?.viewID, 5)
        XCTAssertEqual(g_action_get_enabled(try XCTUnwrap(g_action_map_lookup_action(map, String(runAction.dropFirst(4))))), 0)
        var accels: [String] = []
        if let list = gtk_application_get_accels_for_action(typed(map), newAction) {
            var index = 0
            while let accel = list[index] {
                accels.append(String(cString: accel))
                index += 1
            }
            g_strfreev(list)
        }
        XCTAssertEqual(accels, ["<Shift><Control>n"], "GTK's own spelling of Ctrl+Shift+N")
        if let quit = gtk_application_get_accels_for_action(typed(map), "app.actionui-quit") {
            XCTAssertEqual(quit[0].map { String(cString: $0) }, "<Control>q", "Ctrl+Q quits, as in GNOME apps")
            g_strfreev(quit)
        } else {
            XCTFail("no Ctrl+Q")
        }
    }

    func testTheMacOSIdentifiersOfAboutAndQuitNameTheirTargets() {
        XCTAssertEqual(AppCommands.target("about"), "appInfo")
        XCTAssertEqual(AppCommands.target("quit"), "appTermination")
        XCTAssertEqual(AppCommands.target("newItem"), "newItem")
        XCTAssertEqual(AppCommands.target("Format"), "help", "a target Linux does not have")
        XCTAssertEqual(AppCommands.target(nil), "help")
        let commands = AppCommands()
        commands.load(json: #"[{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "about"}}]"#)
        XCTAssertEqual(outline(commands.menu.opaquePointer), [], "removing About by its identifier")
    }

    func testAnItemWithoutAnActionIsDisabled() throws {
        let application = adw_application_new("com.abracode.actionui.tests.noaction", G_APPLICATION_NON_UNIQUE)!
        defer { g_object_unref(UnsafeMutableRawPointer(application)) }
        let commands = AppCommands()
        commands.start(typed(application), name: "Demo")
        commands.load(json: Self.commands)
        // "Open Recent" (no actionID) is the first section's only item.
        let name = try XCTUnwrap(actionName(commands.menu.opaquePointer, [0, 0]))
        XCTAssertEqual(g_action_get_enabled(try XCTUnwrap(g_action_map_lookup_action(OpaquePointer(application), String(name.dropFirst(4))))), 0,
                       "greyed out, as AppKit shows a menu item without an action")
    }

    func testAWindowGroupDocumentIsItsContentWithItsTitle() throws {
        let document = #"""
            {"type": "WindowGroup", "id": 1, "properties": {"title": "Default Window", "windowGroupID": "test-group"},
             "content": {"type": "Text", "id": 2, "properties": {"text": "Hello"}},
             "commands": [{"type": "CommandMenu", "id": 3, "properties": {"name": "Group Tools"}, "children": [
                {"type": "Button", "id": 4, "properties": {"title": "Go", "actionID": "test.run"}}]}]}
            """#
        let group = AdwaitaApplication.shared.windowGroup(Data(document.utf8), format: "json")
        XCTAssertEqual(group.title, "Default Window")
        let content = try XCTUnwrap(try ActionUIJSON.value(from: String(decoding: group.data, as: UTF8.self)) as? [String: Any])
        XCTAssertEqual(content["type"] as? String, "Text")
        XCTAssertEqual(content["id"] as? Int, 2)
        XCTAssertEqual(group.commands?.key, "test-group", "its commands, for the primary menu once it has loaded")
        XCTAssertTrue(group.commands?.json.contains("Group Tools") ?? false)
        XCTAssertNil(group.error)
        let plain = Data(#"{"type": "Text", "id": 1}"#.utf8)
        XCTAssertEqual(AdwaitaApplication.shared.windowGroup(plain, format: "json").data, plain, "any other document as it is")
        XCTAssertNil(AdwaitaApplication.shared.windowGroup(plain, format: "json").title)
    }

    func testAWindowGroupWithoutContentCannotBeLoaded() {
        let group = AdwaitaApplication.shared.windowGroup(Data(#"{"type": "WindowGroup", "properties": {"title": "Empty"}}"#.utf8), format: "json")
        XCTAssertEqual(group.error, "the WindowGroup has no content", "as Apple shows \"No content provided\"")
        XCTAssertEqual(group.title, "Empty")
    }

    func testAWindowGroupsPlatformOverridesApply() throws {
        let document = #"""
            {"type": "WindowGroup", "id": 1, "properties": {"title": "Mac Window", "title:linux": "Linux Window"},
             "content": {"type": "Text", "id": 2}, "content:linux": {"type": "Text", "id": 3}}
            """#
        let group = AdwaitaApplication.shared.windowGroup(Data(document.utf8), format: "json")
        XCTAssertEqual(group.title, "Linux Window")
        let content = try XCTUnwrap(try ActionUIJSON.value(from: String(decoding: group.data, as: UTF8.self)) as? [String: Any])
        XCTAssertEqual(content["id"] as? Int, 3)
    }

    func testAGroupsCommandsLoadOnceForAllItsWindows() {
        let commands = AppCommands()
        let json = #"[{"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [{"type": "Button", "properties": {"title": "Go"}}]}]"#
        commands.load(json: json, once: "group")
        commands.load(json: json, once: "group")
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[Tools>[Go]]", "[About ]"])
    }

    func testShortcutsBecomeGTKAccelerators() {
        XCTAssertEqual(AppCommands.accelerator(["key": "N", "modifiers": ["command", "shift"]]), "<Control><Shift>n")
        XCTAssertEqual(AppCommands.accelerator(["key": "s"]), "<Control>s", "no modifiers given: command")
        XCTAssertEqual(AppCommands.accelerator(["key": "s", "modifiers": [String]()]), "s", "an empty list: none")
        XCTAssertEqual(AppCommands.accelerator(["key": "return", "modifiers": ["option"]]), "<Alt>Return")
        XCTAssertEqual(AppCommands.accelerator(["key": ",", "modifiers": ["control"]]), "<Control>comma")
        XCTAssertEqual(AppCommands.accelerator(["key": "F5", "modifiers": [String]()]), "F5")
        XCTAssertNil(AppCommands.accelerator(["key": "nonsense"]))
        XCTAssertEqual(AppCommands.accelerator(["key": "k", "modifiers": ["hyper"]]), "<Control>k",
                       "only unknown names: command, as on macOS, not the bare key")
    }

    func testItemsReplacingAppTerminationShowAndTakeCtrlQ() throws {
        let application = adw_application_new("com.abracode.actionui.tests.quit", G_APPLICATION_NON_UNIQUE)!
        defer { g_object_unref(UnsafeMutableRawPointer(application)) }
        let commands = AppCommands()
        commands.start(typed(application), name: "Demo")
        commands.load(json: #"""
            [{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "appTermination"}, "children": [
                {"type": "Button", "id": 3, "properties": {"title": "Quit Demo", "actionID": "test.run",
                 "keyboardShortcut": {"key": "q"}}}]}]
            """#)
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[About Demo]", "[Quit Demo]"])
        let quitItem = try XCTUnwrap(actionName(commands.menu.opaquePointer, [1, 0]))
        let map = OpaquePointer(application)
        let accels = try XCTUnwrap(gtk_application_get_accels_for_action(typed(map), quitItem))
        XCTAssertEqual(accels[0].map { String(cString: $0) }, "<Control>q", "the host's item has Ctrl+Q")
        g_strfreev(accels)
        XCTAssertNil(g_action_map_lookup_action(map, "actionui-quit"), "replaced: no quit action of its own")
    }
}
