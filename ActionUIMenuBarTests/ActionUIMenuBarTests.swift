// ActionUIMenuBarTests/ActionUIMenuBarTests.swift
/*
 Tests for ActionUIMenuBar's JSON items (macOS): a Menu element is a submenu titled with its title,
 nested in a CommandMenu or a CommandGroup, holding its own Buttons, Dividers and Menus; a Button
 in it is the host's item (the item builder's), with the title and shortcut set; an element that
 is not a menu item is left out.
*/

import AppKit
import XCTest
import ActionUI
import ActionUIMenuBar

@MainActor
final class ActionUIMenuBarTests: XCTestCase {

    /// A menu as text: an item as its title, a separator as "-", a submenu as "Title>[...]".
    private func outline(_ menu: NSMenu) -> [String] {
        menu.items.map { item in
            if item.isSeparatorItem {
                return "-"
            }
            if let submenu = item.submenu {
                return item.title + ">[" + outline(submenu).joined(separator: ", ") + "]"
            }
            return item.title
        }
    }

    private func topLevel(_ title: String) -> NSMenu? {
        NSApp.mainMenu?.items.first { $0.submenu?.title == title }?.submenu
    }

    func testAMenuIsASubmenuInACommandMenuOrAGroup() throws {
        _ = NSApplication.shared
        ActionUIMenuBarBuilder.installDefaultMenuBar(appName: "Demo")
        var built: [String] = []
        ActionUIMenuBarBuilder.loadMenuBarCommands(json: #"""
            [{"type": "CommandMenu", "properties": {"name": "Commands"}, "children": [
                {"type": "Button", "properties": {"title": "Top", "actionID": "test.top"}},
                {"type": "Menu", "properties": {"title": "Images"}, "children": [
                    {"type": "Button", "properties": {"title": "Convert", "actionID": "test.convert"}},
                    {"type": "Menu", "properties": {"title": "Resize"}, "children": [
                        {"type": "Button", "properties": {"title": "Half", "actionID": "test.half",
                         "keyboardShortcut": {"key": "j", "modifiers": ["command", "option"]}}}]},
                    {"type": "Divider"},
                    {"type": "Button", "properties": {"title": "Rotate", "actionID": "test.rotate"}}]}]},
             {"type": "CommandGroup", "properties": {"placement": "after", "placementTarget": "help"}, "children": [
                {"type": "Menu", "properties": {"title": "Guides"}, "children": [
                    {"type": "Button", "properties": {"title": "Start", "actionID": "test.start"}}]},
                {"type": "Text", "properties": {"text": "not an item"}}]}]
            """#) { properties in
            built.append(properties["actionID"] as? String ?? "?")
            return NSMenuItem(title: "", action: nil, keyEquivalent: "")
        }

        let commands = try XCTUnwrap(topLevel("Commands"))
        XCTAssertEqual(outline(commands), ["Top", "Images>[Convert, Resize>[Half], -, Rotate]"])
        XCTAssertEqual(built, ["test.top", "test.convert", "test.half", "test.rotate", "test.start"],
                       "every Button, nested or not, is the host's item")
        let half = try XCTUnwrap(commands.item(withTitle: "Images")?.submenu?.item(withTitle: "Resize")?.submenu?.item(withTitle: "Half"))
        XCTAssertEqual(half.keyEquivalent, "j")
        XCTAssertEqual(half.keyEquivalentModifierMask, [.command, .option])

        let help = try XCTUnwrap(topLevel("Help"))
        let guides = try XCTUnwrap(help.item(withTitle: "Guides"))
        XCTAssertEqual(guides.submenu.map(outline), ["Start"])
        XCTAssertNil(help.items.first { $0.title == "not an item" })
    }
}
