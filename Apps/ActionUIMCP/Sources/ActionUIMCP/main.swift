// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// main.swift - actionui-mcp: a stdio MCP server that shows native ActionUI windows.
//
// Threads: the main thread runs the main loop and every window; a background thread reads MCP
// requests from stdin; each tool call runs as a task. The process lives as long as its client
// session: when stdin closes (or SIGTERM, SIGHUP or SIGINT arrives), running calls are cancelled, windows
// opened with `keep` are handed to a keeper process, and the app terminates.
//
// Modes: no arguments runs the MCP server; `--rehost <dir> [--ready-fd <n>]` is the keeper that
// shows kept windows after the session (KeptWindows.swift), started by the server itself.
//
// Environment:
//   ACTIONUI_MCP_LABEL      shown after the client name in every window's title bar
//   ACTIONUI_MCP_LOG_LEVEL  error | warning (default) | info | debug; ActionUI log lines go to stderr

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#endif
import Dispatch
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

let serverVersion = "0.2.1"

let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("-h") || arguments.contains("--help") {
    print("""
        actionui-mcp \(serverVersion) - MCP server (stdio) that shows native ActionUI dialogs and windows.
        Started by an MCP client; speaks JSON-RPC on stdin/stdout. Tools: ask_user, pick_path, show, notify, show_document, validate_document, wait, update_window, get_values, screenshot, close_window.
        Environment: ACTIONUI_MCP_LABEL, ACTIONUI_MCP_LOG_LEVEL (error|warning|info|debug).
        """)
    exit(0)
}
if arguments.contains("--version") {
    print("actionui-mcp \(serverVersion)")
    exit(0)
}

/// The value after `flag`, or nil.
func argument(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex else { return nil }
    return arguments[arguments.index(after: index)]
}
let rehostDirectory = argument(after: "--rehost")
if arguments.contains("--rehost") && rehostDirectory == nil {
    HostSupport.logLine("actionui-mcp: --rehost needs a directory")
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
HostPlatform.registerAddOns()
HostPlatform.prepareApplication(isKeeper: rehostDirectory != nil)

if let rehostDirectory {
    let readyFD = argument(after: "--ready-fd").flatMap(Int32.init)
    let keeper = KeptWindowKeeper()
    guard keeper.start(spool: URL(fileURLWithPath: rehostDirectory, isDirectory: true), readyFD: readyFD) else { exit(1) }
    withExtendedLifetime(keeper) { HostPlatform.runApplication() }  // window delegates and handlers hold it weakly
    exit(0)
}

let host = WindowHost(logger: logger)
host.install()

let server = MCPServer(
    name: "actionui-mcp",
    version: serverVersion,
    instructions: """
        Shows native \(HostPlatform.systemName) windows on the user's screen. ask_user asks a question with optional \
        fields and waits for the answer; pick_path shows the system file panels; show presents a \
        \(HostPlatform.shownContent) without waiting; notify shows a short notice \
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
    parse: HostSupport.parseMessage,
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
    HostPlatform.terminateApplication()
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

HostPlatform.runApplication()
exit(0)
