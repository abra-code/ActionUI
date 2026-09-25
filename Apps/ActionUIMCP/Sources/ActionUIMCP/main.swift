// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// main.swift - actionui-mcp: a stdio MCP server that shows native ActionUI windows.
//
// Threads: the main thread runs the AppKit run loop and every window; a background thread reads
// MCP requests from stdin; each tool call runs as a task. The process lives as long as its client
// session: when stdin closes (or SIGTERM, SIGHUP or SIGINT arrives), running calls are cancelled, windows
// opened with `keep` are handed to a keeper process, and the app terminates.
//
// Modes: no arguments runs the MCP server; `--rehost <dir> [--ready-fd <n>]` is the keeper that
// shows kept windows after the session (KeptWindows.swift), started by the server itself.
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
/// window. No Quit item in the server: quitting would end the client's server; closing windows is
/// enough. The keeper serves no one and gets one.
@MainActor
func makeMainMenu(quitItem: Bool) -> NSMenu {
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
    submenu("ActionUI", [item("Hide", #selector(NSApplication.hide(_:)), "h")]
                        + (quitItem ? [.separator(), item("Quit", #selector(NSApplication.terminate(_:)), "q")] : []))
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
    FileHandle.standardOutput.write(Data("""
        actionui-mcp \(serverVersion) - MCP server (stdio) that shows native ActionUI dialogs and windows.
        Started by an MCP client; speaks JSON-RPC on stdin/stdout. Tools: ask_user, pick_path, show, notify, show_document, validate_document, wait, update_window, get_values, screenshot, close_window.
        Environment: ACTIONUI_MCP_LABEL, ACTIONUI_MCP_LOG_LEVEL (error|warning|info|debug).

        """.utf8))
    exit(0)
}
if arguments.contains("--version") {
    FileHandle.standardOutput.write(Data("actionui-mcp \(serverVersion)\n".utf8))
    exit(0)
}

/// The value after `flag`, or nil.
func argument(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex else { return nil }
    return arguments[arguments.index(after: index)]
}
let rehostDirectory = argument(after: "--rehost")
if arguments.contains("--rehost") && rehostDirectory == nil {
    FileHandle.standardError.write(Data("actionui-mcp: --rehost needs a directory\n".utf8))
    exit(2)
}

// First, before anything can print: take stdout for the protocol. The keeper has no protocol.
let writeMessage: @Sendable (Data) -> Void
if rehostDirectory == nil {
    writeMessage = MCPServer.reserveStandardOutput()
} else {
    writeMessage = { _ in }
}

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
app.mainMenu = makeMainMenu(quitItem: rehostDirectory != nil)

if let rehostDirectory {
    let readyFD = argument(after: "--ready-fd").flatMap(Int32.init)
    let keeper = KeptWindowKeeper()
    guard keeper.start(spool: URL(fileURLWithPath: rehostDirectory, isDirectory: true), readyFD: readyFD) else { exit(1) }
    withExtendedLifetime(keeper) { app.run() }  // window delegates are weak
    exit(0)
}

let host = WindowHost(logger: logger)
host.install()

let server = MCPServer(
    name: "actionui-mcp",
    version: serverVersion,
    instructions: """
        Shows native macOS windows on the user's screen. ask_user asks a question with optional \
        fields and waits for the answer; pick_path shows the system file panels; show presents a \
        report, image, PDF, video, web page, diff, or table without waiting; notify shows a short notice \
        that goes away by itself. For anything the canned \
        tools cannot express, write an ActionUI document (see the actionui skill if available), check \
        it with validate_document, and open it with show_document: as a dialog that returns every \
        value, or as a live window whose actions you collect with wait and whose values you change \
        with update_window. screenshot renders a document (or captures a window) so you can check \
        the layout before the user sees it. Element reference, for writing documents: resources \
        actionui://docs/guide, actionui://docs/elements, and actionui://docs/elements/<Type>. Prefer \
        ask_user over asking in chat when you need structured input or an explicit approval.
        """,
    tools: makeTools(host: host, label: environment["ACTIONUI_MCP_LABEL"]),
    resources: DocsResources.make(),
    output: writeMessage)

/// Ends the session once: answers every running call with a cancellation, hands kept windows to a
/// keeper process, and terminates. Runs on the main thread.
var shuttingDown = false
@MainActor
func shutDown(reason: String) {
    guard !shuttingDown else { return }
    shuttingDown = true
    logger.log("session ended (\(reason))", .info)
    server.cancelAll()
    host.handOffKeptWindows()
    NSApp.terminate(nil)
}

// A client normally closes stdin first; SIGTERM follows 2 s later. SIGHUP comes when the terminal
// the client runs in closes, SIGINT from Ctrl-C in a terminal that is not in raw mode. Each would
// otherwise end the process at once, with no handoff.
let signalNames = [SIGTERM: "SIGTERM", SIGHUP: "SIGHUP", SIGINT: "SIGINT"]
var signalSources: [DispatchSourceSignal] = []
for (signalNumber, name) in signalNames {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        MainActor.assumeIsolated { shutDown(reason: name) }
    }
    source.resume()
    signalSources.append(source)
}

server.startReading {
    // stdin closed: the client ended the session. Nobody is left to answer.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { shutDown(reason: "stdin closed") }
    }
}

app.run()
