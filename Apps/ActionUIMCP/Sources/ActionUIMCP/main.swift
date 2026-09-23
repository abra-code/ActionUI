// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// main.swift - actionui-mcp: a stdio MCP server that shows native ActionUI windows.
//
// Threads: the main thread runs the AppKit run loop and every window; a background thread reads
// MCP requests from stdin; each tool call runs as a task. The process lives as long as its client
// session: when stdin closes, running calls are cancelled and the app terminates.
//
// Environment:
//   ACTIONUI_MCP_LABEL      shown after the client name in every window's title bar
//   ACTIONUI_MCP_LOG_LEVEL  error | warning (default) | info | debug; ActionUI log lines go to stderr

import AppKit
import ActionUI
import ActionUISwiftAdapter
import MCPStdio
import ActionUIQuickLook
import ActionUIDiff
import ActionUICachedImage
import ActionUIRichText

let serverVersion = "0.1.0"

/// Edit and Window menus, so text fields get copy, paste, undo and select all, and Cmd-W closes a
/// window. No Quit item: quitting would end the client's server; closing windows is enough.
@MainActor
func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    func submenu(_ title: String, _ items: [NSMenuItem]) {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        mainMenu.addItem(holder)
    }
    func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }
    submenu("ActionUI", [item("Hide", #selector(NSApplication.hide(_:)), "h")])
    submenu("Edit", [
        item("Undo", Selector(("undo:")), "z"),
        item("Redo", Selector(("redo:")), "z", [.command, .shift]),
        .separator(),
        item("Cut", #selector(NSText.cut(_:)), "x"),
        item("Copy", #selector(NSText.copy(_:)), "c"),
        item("Paste", #selector(NSText.paste(_:)), "v"),
        item("Select All", #selector(NSText.selectAll(_:)), "a"),
    ])
    submenu("Window", [
        item("Close", #selector(NSWindow.performClose(_:)), "w"),
        item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
    ])
    return mainMenu
}

let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("-h") || arguments.contains("--help") {
    FileHandle.standardError.write(Data("""
        actionui-mcp \(serverVersion) - MCP server (stdio) that shows native ActionUI dialogs and windows.
        Started by an MCP client; speaks JSON-RPC on stdin/stdout. Tools: ask_user, pick_path, show, show_document, validate_document, wait, update_window, get_values, close_window.
        Environment: ACTIONUI_MCP_LABEL, ACTIONUI_MCP_LOG_LEVEL (error|warning|info|debug).

        """.utf8))
    exit(0)
}
if arguments.contains("--version") {
    FileHandle.standardError.write(Data("actionui-mcp \(serverVersion)\n".utf8))
    exit(0)
}

// First, before anything can print: take stdout for the protocol.
let writeMessage = MCPServer.reserveStandardOutput()

let environment = ProcessInfo.processInfo.environment
let logLevel: LoggerLevel = switch environment["ACTIONUI_MCP_LOG_LEVEL"]?.lowercased() {
case "error": .error
case "info": .info
case "debug": .debug
default: .warning
}
let logger = HostLogger(maxLevel: logLevel)
// Also reaches ActionUIRegistry's logger, where unknown element types are reported.
ActionUISwift.setLogger(logger)
ActionUIQuickLook.register()
ActionUIDiff.register()
ActionUICachedImage.register()
ActionUIRichText.register()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.mainMenu = makeMainMenu()

let host = WindowHost(logger: logger)
host.install()

let server = MCPServer(
    name: "actionui-mcp",
    version: serverVersion,
    instructions: """
        Shows native macOS windows on the user's screen. ask_user asks a question with optional \
        fields and waits for the answer; pick_path shows the system file panels; show presents a \
        report, image, PDF, video, web page, diff, or table without waiting. For anything the canned \
        tools cannot express, write an ActionUI document (see the actionui skill if available), check \
        it with validate_document, and open it with show_document: as a dialog that returns every \
        value, or as a live window whose actions you collect with wait and whose values you change \
        with update_window. Prefer ask_user over asking in chat when you need structured input or an \
        explicit approval.
        """,
    tools: makeTools(host: host, label: environment["ACTIONUI_MCP_LABEL"]),
    output: writeMessage)

server.startReading {
    // stdin closed: the client ended the session. Nobody is left to answer.
    server.cancelAll()
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

app.run()
