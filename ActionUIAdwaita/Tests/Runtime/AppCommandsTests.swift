// Tests/Runtime/AppCommandsTests.swift
/*
 Tests for the application's commands on Linux (AppCommands): the primary menu's sections (the
 top targets' groups, each CommandMenu as a submenu, then the bottom targets and About), placement
 before, after and replacing (a childless replacing group removing About), Dividers as sections,
 a Menu as a submenu (nested, in a CommandMenu or a group, its items firing their actions);
 macOS menu bar names (standard item identifiers, menu titles) as the sections that hold such items;
 commands loaded under a key replaced in place, and removed by an empty array; a menu button's
 popover showing a rebuilt submenu as it is now, one page each; titles with underscores shown as written;
 keyboardShortcut as GTK accelerators; an item's action firing its actionID with the element's id;
 a disabled item's action disabled; Ctrl+Q quitting; a WindowGroup document as its content, its
 title and its commands (its platform overrides applied), loaded once per group, and not before
 its window shows; one that cannot be loaded brings none.
*/

import XCTest
import CAdwaita
@testable import ActionUI
@testable import ActionUIAdwaitaApplication

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
        let application = adw_application_new("com.abracode.actionui.tests.commands", applicationNonUnique)!
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

    func testAMenuIsASubmenuInACommandMenuOrAGroupAndItsItemsFire() throws {
        let application = adw_application_new("com.abracode.actionui.tests.submenus", applicationNonUnique)!
        defer { g_object_unref(UnsafeMutableRawPointer(application)) }
        let commands = AppCommands()
        commands.start(typed(application), name: "Demo")
        XCTAssertTrue(commands.load(json: #"""
            [{"type": "CommandMenu", "properties": {"name": "Commands"}, "children": [
                {"type": "Button", "properties": {"title": "Top", "actionID": "test.new"}},
                {"type": "Menu", "properties": {"title": "Images"}, "children": [
                    {"type": "Button", "properties": {"title": "Convert"}},
                    {"type": "Menu", "properties": {"title": "Resize"}, "children": [
                        {"type": "Button", "id": 21, "properties": {"title": "Half", "actionID": "test.run"}}]},
                    {"type": "Divider"},
                    {"type": "Button", "properties": {"title": "Rotate"}}]}]},
             {"type": "CommandGroup", "properties": {"placement": "after", "placementTarget": "help"}, "children": [
                {"type": "Menu", "properties": {"title": "Guides"}, "children": [
                    {"type": "Button", "properties": {"title": "Start"}}]},
                {"type": "Text", "properties": {"text": "not an item"}}]}]
            """#))
        XCTAssertEqual(outline(commands.menu.opaquePointer), [
            "[Commands>[Top, Images>[[Convert, Resize>[Half]], [Rotate]]]]",
            "[Guides>[Start]]",
            "[About Demo]",
        ])
        // Half: the first section, Commands, Images (index 1), its first section, Resize (index 1), Half
        let half = try XCTUnwrap(actionName(commands.menu.opaquePointer, [0, 0, 1, 0, 1, 0]))
        let map = OpaquePointer(application)
        g_action_activate(try XCTUnwrap(g_action_map_lookup_action(map, String(half.dropFirst(4)))), nil)
        XCTAssertEqual(fired.map(\.actionID), ["test.run"])
        XCTAssertEqual(fired.first?.viewID, 21)
    }

    func testCommandsLoadedUnderAKeyAreReplacedInPlace() {
        let commands = AppCommands()
        let recent = { (titles: [String]) -> String in
            let items = titles.map { #"{"type": "Button", "properties": {"title": "\#($0)"}}"# }.joined(separator: ", ")
            return #"[{"type": "CommandMenu", "properties": {"name": "Recent"}, "children": [\#(items)]}]"#
        }
        XCTAssertTrue(commands.load(json: #"[{"type": "CommandMenu", "properties": {"name": "First"}}]"#))
        XCTAssertTrue(commands.load(json: recent(["a.txt"]), replacing: "recent"))
        XCTAssertTrue(commands.load(json: #"[{"type": "CommandMenu", "properties": {"name": "Last"}}]"#))
        XCTAssertEqual(outline(commands.menu.opaquePointer)[0], "[First>[], Recent>[a.txt], Last>[]]")
        XCTAssertTrue(commands.load(json: recent(["b.txt", "a.txt"]), replacing: "recent"))
        XCTAssertEqual(outline(commands.menu.opaquePointer)[0], "[First>[], Recent>[b.txt, a.txt], Last>[]]",
                       "replaced where it was, not added")
        XCTAssertFalse(commands.load(json: #"{"type": "CommandMenu"}"#, replacing: "recent"), "not an array")
        XCTAssertEqual(outline(commands.menu.opaquePointer)[0], "[First>[], Recent>[b.txt, a.txt], Last>[]]", "unchanged")
        XCTAssertTrue(commands.load(json: "[]", replacing: "recent"))
        XCTAssertEqual(outline(commands.menu.opaquePointer)[0], "[First>[], Last>[]]", "an empty array removes them")
        XCTAssertTrue(commands.load(json: recent(["c.txt"]), replacing: "recent"))
        XCTAssertEqual(outline(commands.menu.opaquePointer)[0], "[First>[], Last>[], Recent>[c.txt]]", "after a removal, at the end")
    }

    /// The pages of a menu button's popover: each name with the labels on it.
    private func popoverPages(_ button: UnsafeMutablePointer<GtkWidget>) -> [String] {
        guard let popover = gtk_menu_button_get_popover(OpaquePointer(button)) else { return [] }
        func find(_ widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
            if g_type_check_instance_is_a(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self), gtk_stack_get_type()) != 0 {
                return widget
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                if let found = find(current) { return found }
                child = gtk_widget_get_next_sibling(current)
            }
            return nil
        }
        func labels(_ widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
            var result: [String] = []
            if g_type_check_instance_is_a(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self), gtk_label_get_type()) != 0 {
                result.append(swiftString(gtk_label_get_text(OpaquePointer(widget))) ?? "")
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                result += labels(current)
                child = gtk_widget_get_next_sibling(current)
            }
            return result
        }
        guard let stack = find(UnsafeMutablePointer<GtkWidget>(OpaquePointer(popover))) else { return [] }
        guard let pages = gtk_stack_get_pages(OpaquePointer(stack)) else { return [] }
        defer { g_object_unref(UnsafeMutableRawPointer(pages)) }
        var result: [String] = []
        for index in 0..<g_list_model_get_n_items(pages) {
            guard let page = g_list_model_get_item(pages, index) else { continue }
            let name = swiftString(gtk_stack_page_get_name(OpaquePointer(page))) ?? "?"
            if let child = gtk_stack_page_get_child(OpaquePointer(page)) {
                result.append(name + ":" + labels(child).filter { !$0.isEmpty }.joined(separator: ","))
            }
            g_object_unref(page)
        }
        return result
    }

    func testAMenuButtonShowsARebuiltSubmenuAsItIsNow() throws {
        let commands = AppCommands()
        let recent = { (titles: [String]) -> String in
            let items = titles.map { #"{"type": "Button", "properties": {"title": "\#($0)"}}"# }.joined(separator: ", ")
            return #"[{"type": "CommandMenu", "properties": {"name": "Recent"}, "children": [\#(items)]}]"#
        }
        XCTAssertTrue(commands.load(json: recent(["a.txt"]), replacing: "recent"))
        let button = commands.makeMenuButton()
        g_object_ref_sink(UnsafeMutableRawPointer(button))
        defer { g_object_unref(UnsafeMutableRawPointer(button)) }
        XCTAssertTrue(commands.load(json: recent(["b.txt", "a.txt"]), replacing: "recent"))
        XCTAssertTrue(commands.load(json: recent(["c.txt", "b.txt", "a.txt"]), replacing: "recent"))
        let pages = popoverPages(button)
        XCTAssertEqual(pages.filter { $0.hasPrefix("Recent:") }, ["Recent:Recent,c.txt,b.txt,a.txt"],
                       "one Recent page, as the menu is now: \(pages)")
    }

    func testTitlesWithUnderscoresShowAsWritten() throws {
        let commands = AppCommands()
        XCTAssertTrue(commands.load(json: #"""
            [{"type": "CommandMenu", "properties": {"name": "My_Menu"}, "children": [
                {"type": "Button", "properties": {"title": "my_file.txt"}},
                {"type": "Menu", "properties": {"title": "sub_menu"}, "children": [
                    {"type": "Button", "properties": {"title": "a_b"}}]}]}]
            """#))
        // The model holds the escaped labels; the popover shows them as written
        XCTAssertEqual(outline(commands.menu.opaquePointer)[0], "[My__Menu>[my__file.txt, sub__menu>[a__b]]]")
        let button = commands.makeMenuButton()
        g_object_ref_sink(UnsafeMutableRawPointer(button))
        defer { g_object_unref(UnsafeMutableRawPointer(button)) }
        let pages = popoverPages(button).filter { !$0.hasPrefix("main:") }
        XCTAssertEqual(pages.sorted(), ["My__Menu:My_Menu,my_file.txt,sub_menu", "sub__menu:sub_menu,a_b"].sorted(), "\(pages)")
    }

    func testAChildlessReplacingGroupRemovesAbout() {
        let commands = AppCommands()
        XCTAssertTrue(commands.load(json: #"[{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "appInfo"}}]"#))
        XCTAssertEqual(outline(commands.menu.opaquePointer), [])
        XCTAssertFalse(commands.load(json: #"{"type": "CommandMenu"}"#), "not an array")
    }

    func testAnItemsActionFiresWithTheElementsIDAndADisabledOneIsDisabled() throws {
        let application = adw_application_new("com.abracode.actionui.tests.actions", applicationNonUnique)!
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

    func testMacOSMenuBarNamesStandForTheirSections() {
        XCTAssertEqual(AppCommands.target("about"), "appInfo")
        XCTAssertEqual(AppCommands.target("quit"), "appTermination")
        XCTAssertEqual(AppCommands.target("newItem"), "newItem")
        // macOS's standard items and menus, where Linux keeps the same kind of item
        XCTAssertEqual(AppCommands.target("new"), "newItem")
        XCTAssertEqual(AppCommands.target("open"), "newItem")
        XCTAssertEqual(AppCommands.target("File"), "newItem")
        XCTAssertEqual(AppCommands.target("close"), "saveItem")
        XCTAssertEqual(AppCommands.target("copy"), "pasteboard")
        XCTAssertEqual(AppCommands.target("Edit"), "undoRedo")
        XCTAssertEqual(AppCommands.target("Format"), "textFormatting")
        XCTAssertEqual(AppCommands.target("minimize"), "windowSize")
        XCTAssertEqual(AppCommands.target("Help"), "help")
        XCTAssertEqual(AppCommands.target("Tools"), "help", "a name neither side has")
        XCTAssertEqual(AppCommands.target(nil), "help")
        let replaced = AppCommands()
        replaced.load(json: #"""
            [{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "new"}, "children": [
                {"type": "Button", "properties": {"title": "New Project"}}]}]
            """#)
        XCTAssertEqual(outline(replaced.menu.opaquePointer), ["[New Project]", "[About \(replaced.appName)]"],
                       "an item replacing macOS's New is first, where New is")
        let commands = AppCommands()
        commands.load(json: #"[{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "about"}}]"#)
        XCTAssertEqual(outline(commands.menu.opaquePointer), [], "removing About by its identifier")
    }

    func testAnItemWithoutAnActionIsDisabled() throws {
        let application = adw_application_new("com.abracode.actionui.tests.noaction", applicationNonUnique)!
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

    func testAWindowGroupsCommandsWaitForItsWindow() throws {
        let document = #"""
            {"type": "WindowGroup", "id": 1, "properties": {"title": "Prepared Group", "windowGroupID": "test-prepared-group"},
             "content": {"type": "Text", "id": 2, "properties": {"text": "Hello"}},
             "commands": [{"type": "CommandMenu", "id": 3, "properties": {"name": "Prepared Tools"}, "children": [
                {"type": "Button", "id": 4, "properties": {"title": "Go", "actionID": "test.run"}}]}]}
            """#
        let app = AdwaitaApplication()
        var prepared: [String] = []
        var shown: [String] = []
        var title: String?
        app.handlers.didFinishLaunching = {
            let window = app.prepareWindow(json: Data(document.utf8), windowUUID: "commands-w1")
            prepared = self.outline(AppCommands.shared.menu.opaquePointer)
            app.presentWindow(prepared: window, title: nil)
            shown = self.outline(AppCommands.shared.menu.opaquePointer)
            title = app.gtkWindow("commands-w1").flatMap { swiftString(gtk_window_get_title($0)) }
            app.closeWindow("commands-w1")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(prepared.joined().contains("Prepared Tools"), "a document that is only checked adds nothing to the menu")
        XCTAssertTrue(shown.joined().contains("Prepared Tools"), "\(shown)")
        XCTAssertEqual(title, "Prepared Group", "the group's title comes with the prepared document")
    }

    func testAWindowGroupThatCannotBeLoadedBringsNoCommands() throws {
        let document = #"""
            {"type": "WindowGroup", "id": 1, "properties": {"title": "Failed Group"},
             "commands": [{"type": "CommandMenu", "id": 3, "properties": {"name": "Failed Tools"}, "children": [
                {"type": "Button", "id": 4, "properties": {"title": "Go", "actionID": "test.run"}}]}]}
            """#
        let app = AdwaitaApplication()
        var shown: [String] = []
        var opened = false
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(document.utf8), windowUUID: "commands-w2", title: nil)
            opened = app.gtkWindow("commands-w2") != nil
            shown = self.outline(AppCommands.shared.menu.opaquePointer)
            app.closeWindow("commands-w2")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(opened, "its window shows the error")
        XCTAssertFalse(shown.joined().contains("Failed Tools"), "\(shown)")
    }

    /// Shows the WindowGroup at `path` and returns the primary menu's outline while it is on screen.
    private func menuWhileShowing(path: String, windowUUID: String) -> [String] {
        let app = AdwaitaApplication()
        var shown: [String] = []
        app.handlers.didFinishLaunching = {
            app.presentWindow(url: path, windowUUID: windowUUID, title: nil)
            shown = self.outline(AppCommands.shared.menu.opaquePointer)
            app.closeWindow(windowUUID)
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        AdwaitaTestHost.drainMainLoop()
        return shown
    }

    private func windowGroupFile(_ folder: URL, name: String, menu: String) throws -> URL {
        let document = """
            {"type": "WindowGroup", "id": 1, "properties": {"title": "\(menu)", "windowGroupID": "\(menu)"},
             "content": {"type": "Text", "id": 2, "properties": {"text": "Hello"}},
             "commands": [{"type": "CommandMenu", "id": 3, "properties": {"name": "\(menu)"}, "children": [
                {"type": "Button", "id": 4, "properties": {"title": "Go", "actionID": "test.run"}}]}]}
            """
        let file = folder.appendingPathComponent(name)
        try Data(document.utf8).write(to: file)
        return file
    }

    func testOnlyAWindowGroupInTheResourceFolderAddsCommands() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-commands-\(UUID().uuidString)")
        let resources = base.appendingPathComponent("Resources")
        let elsewhere = base.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let savedFolder = ActionUIResourceFolder.path
        defer {
            ActionUIConfiguration.updateForTesting { $0.resourceFolder = savedFolder }
            try? FileManager.default.removeItem(at: base)
        }
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = resources.path }

        let own = try windowGroupFile(resources, name: "Main.json", menu: "Own Tools")
        let outside = try windowGroupFile(elsewhere, name: "Other.json", menu: "Outside Tools")
        let linked = try windowGroupFile(elsewhere, name: "Target.json", menu: "Linked Tools")
        let link = resources.appendingPathComponent("Link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: linked)

        XCTAssertTrue(menuWhileShowing(path: own.path, windowUUID: "commands-own").joined().contains("Own Tools"),
                      "a document in the app's resource folder is the app's own")
        XCTAssertFalse(menuWhileShowing(path: outside.path, windowUUID: "commands-outside").joined().contains("Outside Tools"),
                       "a document elsewhere adds no menu commands")
        XCTAssertFalse(menuWhileShowing(path: link.path, windowUUID: "commands-link").joined().contains("Linked Tools"),
                       "a link in the resource folder to a file elsewhere is elsewhere")
        XCTAssertTrue(AdwaitaApplication.isInResourceFolder(own))
        XCTAssertFalse(AdwaitaApplication.isInResourceFolder(resources.appendingPathComponent("../Downloads/Other.json")))

        // Two folders whose names differ only in how the accent is encoded are two folders.
        let composed = base.appendingPathComponent("R\u{E9}sum\u{E9}")
        let decomposed = base.appendingPathComponent("Re\u{301}sume\u{301}")
        try FileManager.default.createDirectory(at: composed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decomposed, withIntermediateDirectories: true)
        let sibling = try windowGroupFile(decomposed, name: "Main.json", menu: "Sibling Tools")
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = composed.path }
        XCTAssertFalse(AdwaitaApplication.isInResourceFolder(sibling), "a folder spelled with a combining accent is elsewhere")
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = "/" }
        XCTAssertFalse(AdwaitaApplication.isInResourceFolder(own), "a resource folder of / trusts nothing")
    }

    func testAWindowGroupLargerThanTheCapIsLeftForTheLoadToRefuse() throws {
        let document = Data(#"{"type": "WindowGroup", "id": 1, "properties": {"title": "Big"}, "content": {"type": "Text", "id": 2}}"#.utf8)
        let saved = WindowModel.maximumJSONSize
        defer { ActionUIConfiguration.updateForTesting { $0.limits.maximumJSONSize = saved } }
        ActionUIConfiguration.updateForTesting { $0.limits.maximumJSONSize = document.count - 1 }
        let group = AdwaitaApplication.shared.windowGroup(document, format: "json")
        XCTAssertEqual(group.data, document, "not parsed, so its smaller content cannot slip under the cap")
        XCTAssertNil(group.title)
        XCTAssertThrowsError(try ActionUIModel.shared.loadWindowDocument(group.data, format: "json", windowUUID: UUID().uuidString)) { error in
            XCTAssertEqual("\(error)", "the ActionUI JSON is larger than 0 MB")
        }
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
        // Not started: About names GLib's application name (a host's own application sets it)
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[Tools>[Go]]", "[About \(commands.appName)]"])
    }

    func testAGroupsCommandsLeaveWithRemoveAndCanComeBack() {
        let commands = AppCommands()
        let json = #"[{"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [{"type": "Button", "properties": {"title": "Go"}}]}]"#
        commands.load(json: json, once: "group")
        commands.removeWindowGroup("group")
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[About \(commands.appName)]"])
        commands.removeWindowGroup("group")
        commands.removeWindowGroup("never loaded")
        commands.load(json: json, once: "group")
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[Tools>[Go]]", "[About \(commands.appName)]"],
                       "a group opened again brings its commands again")
    }

    func testAWindowGroupCannotReplaceQuitButTheHostCan() {
        let commands = AppCommands()
        let replacingQuit = #"""
            [{"type": "CommandGroup", "properties": {"placement": "replacing", "placementTarget": "quit"}, "children": [
                {"type": "Button", "properties": {"title": "Not Quit"}}]},
             {"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [{"type": "Button", "properties": {"title": "Go"}}]}]
            """#
        commands.load(json: replacingQuit, once: "group")
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[Tools>[Go]]", "[About \(commands.appName)]"],
                       "the group's other commands load; the one replacing appTermination does not")
        let host = AppCommands()
        host.load(json: replacingQuit)
        XCTAssertTrue(outline(host.menu.opaquePointer).contains("[Not Quit]"), "the host's own menu may replace Quit")
    }

    func testAWindowGroupsCtrlQShortcutIsIgnoredButTheHostsIsKept() throws {
        let application = adw_application_new("com.abracode.actionui.tests.groupquitkey", applicationNonUnique)!
        defer { g_object_unref(UnsafeMutableRawPointer(application)) }
        let map = OpaquePointer(application)
        func accels(_ action: String) -> [String] {
            var result: [String] = []
            if let list = gtk_application_get_accels_for_action(typed(map), action) {
                var index = 0
                while let accel = list[index] {
                    result.append(String(cString: accel))
                    index += 1
                }
                g_strfreev(list)
            }
            return result
        }
        let json = #"""
            [{"type": "CommandMenu", "properties": {"name": "Tools"}, "children": [
                {"type": "Button", "properties": {"title": "Close All", "actionID": "test.a", "keyboardShortcut": {"key": "Q"}}},
                {"type": "Button", "properties": {"title": "Save", "actionID": "test.b", "keyboardShortcut": {"key": "s"}}},
                {"type": "Menu", "properties": {"title": "More"}, "children": [
                    {"type": "Button", "properties": {"title": "Leave", "actionID": "test.c", "keyboardShortcut": {"key": "q", "modifiers": ["control"]}}},
                    {"type": "Button", "properties": {"title": "Quit Shifted", "actionID": "test.d", "keyboardShortcut": {"key": "q", "modifiers": ["command", "shift"]}}}]}]}]
            """#
        let commands = AppCommands()
        commands.start(typed(application), name: "Demo")
        XCTAssertTrue(commands.load(json: json, once: "group"))
        XCTAssertEqual(outline(commands.menu.opaquePointer), ["[Tools>[Close All, Save, More>[Leave, Quit Shifted]]]", "[About Demo]"],
                       "the items stay")
        XCTAssertEqual(accels(try XCTUnwrap(actionName(commands.menu.opaquePointer, [0, 0, 0]))), [], "Ctrl+Q taken off")
        XCTAssertEqual(accels(try XCTUnwrap(actionName(commands.menu.opaquePointer, [0, 0, 1]))), ["<Control>s"])
        XCTAssertEqual(accels(try XCTUnwrap(actionName(commands.menu.opaquePointer, [0, 0, 2, 0]))), [], "in a submenu too")
        XCTAssertEqual(accels(try XCTUnwrap(actionName(commands.menu.opaquePointer, [0, 0, 2, 1]))), ["<Shift><Control>q"],
                       "Ctrl+Shift+Q is not Quit's")
        XCTAssertEqual(accels("app.actionui-quit"), ["<Control>q"], "Quit keeps Ctrl+Q")

        let host = AppCommands()
        host.start(typed(application), name: "Demo")
        host.load(json: json)
        XCTAssertEqual(accels(try XCTUnwrap(actionName(host.menu.opaquePointer, [0, 0, 0]))), ["<Control>q"],
                       "the host's own menu may give Ctrl+Q to an item")
    }

    func testAGroupsCommandsLeaveTheMenuWithItsLastWindow() throws {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-last-window-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let savedFolder = ActionUIResourceFolder.path
        defer {
            ActionUIConfiguration.updateForTesting { $0.resourceFolder = savedFolder }
            try? FileManager.default.removeItem(at: resources)
        }
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = resources.path }
        let file = try windowGroupFile(resources, name: "Main.json", menu: "Group Tools")

        let app = AdwaitaApplication()
        var withTwo = "", withOne = "", withNone = ""
        app.handlers.didFinishLaunching = {
            app.presentWindow(url: file.path, windowUUID: "last-window-1", title: nil)
            app.presentWindow(url: file.path, windowUUID: "last-window-2", title: nil)
            withTwo = self.outline(AppCommands.shared.menu.opaquePointer).joined()
            app.closeWindow("last-window-1")
            AdwaitaTestHost.drainMainLoop()
            withOne = self.outline(AppCommands.shared.menu.opaquePointer).joined()
            app.closeWindow("last-window-2")
            AdwaitaTestHost.drainMainLoop()
            withNone = self.outline(AppCommands.shared.menu.opaquePointer).joined()
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(withTwo.contains("Group Tools"), withTwo)
        XCTAssertTrue(withOne.contains("Group Tools"), "one window of the group is still open: \(withOne)")
        XCTAssertFalse(withNone.contains("Group Tools"), "the last window closed: \(withNone)")
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
        let application = adw_application_new("com.abracode.actionui.tests.quit", applicationNonUnique)!
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
