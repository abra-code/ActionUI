// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeptWindows.swift - windows that outlive the session. A window opened with `keep: true` (show,
// show_document in window mode) keeps its staged document file. When the session ends (stdin
// closes, or SIGTERM, SIGHUP or SIGINT arrives), the server moves those files into a spool directory, adds
// a manifest with each window's frame, title and current values, and starts a keeper process:
// this executable again, as `actionui-mcp --rehost <dir>`, in a session of its own, so a signal
// the client sends to the server does not reach it. The keeper shows the same windows at the
// same places (on Linux at the same size, where the compositor puts them), deletes the spool
// directory, and quits when its last window closes. Its windows are no longer connected to any
// agent: actions go nowhere, and the subtitle says so.
//
// SIGKILL sent to the server with no earlier stdin EOF or SIGTERM leaves no chance to hand off.
// Clients close stdin first (the TypeScript SDK waits 2 s before SIGTERM, 2 s more before
// SIGKILL), and a client that dies abruptly closes the pipe as well, so the EOF path covers both.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#endif
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

/// One window handed to the keeper.
struct KeptWindowRecord: Codable {
    let window: String
    /// File name of the document inside the spool directory.
    let document: String
    let title: String
    let subtitle: String
    /// x, y, width, height of the window frame, in screen coordinates.
    let frame: [Double]
    let styleMask: UInt
    /// Element values as ActionUI strings, keyed by view id.
    let values: [String: String]
    /// Table and list rows, keyed by view id.
    let rows: [String: [[String]]]
    /// Properties update_window set, keyed by view id and name, each value as JSON text. Set again
    /// after the document loads and before rows and values. Absent in manifests that predate it.
    let properties: [String: [String: String]]?
}

struct KeptWindowManifest: Codable {
    static let fileName = "manifest.json"
    static let currentVersion = 1
    let version: Int
    /// Back to front: the keeper orders each window front in turn, which restores the stacking.
    let windows: [KeptWindowRecord]
}

// MARK: - Keeper side, on every system

/// What the keeper does the same everywhere: read the spool directory, set a window's state back,
/// report to the server. Each system's KeptWindowKeeper shows the windows.
@MainActor
enum KeptWindowSupport {
    static let subtitleSuffix = " (session ended)"

    /// The manifest in `spool`, or why it cannot be used.
    static func manifest(in spool: URL) -> Result<KeptWindowManifest, MCPToolError> {
        let manifest: KeptWindowManifest
        do {
            let data = try Data(contentsOf: spool.appendingPathComponent(KeptWindowManifest.fileName))
            manifest = try JSONDecoder().decode(KeptWindowManifest.self, from: data)
        } catch {
            return .failure(MCPToolError("the new process could not read the kept windows: \(error.displayText)"))
        }
        guard manifest.version == KeptWindowManifest.currentVersion else {
            return .failure(MCPToolError("kept windows manifest version \(manifest.version) is not supported"))
        }
        return .success(manifest)
    }

    /// Properties the agent set (checked when it set them), then rows, then values, so a replaced
    /// chart description is in place before its rows and a table's selection finds its row. Only
    /// rows and values that differ from the freshly loaded document are written, so nothing the
    /// user did not change is touched.
    static func restore(_ record: KeptWindowRecord) {
        let id = record.window
        for (key, named) in record.properties ?? [:] {
            guard let viewID = Int(key) else { continue }
            for (name, json) in named {
                guard let value = propertyValue(json) else { continue }
                ActionUISwift.setElementProperty(windowUUID: id, viewID: viewID, propertyName: name, value: value)
            }
        }
        for (key, rows) in record.rows {
            guard let viewID = Int(key), ActionUISwift.getElementRows(windowUUID: id, viewID: viewID) != rows else { continue }
            ActionUISwift.setElementRows(windowUUID: id, viewID: viewID, rows: rows)
        }
        for (key, value) in record.values {
            guard let viewID = Int(key),
                  ActionUISwift.getElementValueAsString(windowUUID: id, viewID: viewID) != value else { continue }
            ActionUISwift.setElementValueFromString(windowUUID: id, viewID: viewID, value: value)
        }
    }

    /// A property value from its JSON text, a bare string or number included.
    private static func propertyValue(_ json: String) -> Any? {
        #if canImport(Darwin)
        try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        #else
        (try? HostSupport.parseJSON(Data(json.utf8)))?.any
        #endif
    }

    /// Writes one line to the server on `fd` and closes it. A server that stopped waiting has closed
    /// the read end: the write then fails with EPIPE, not a fatal SIGPIPE.
    static func report(_ line: String, to fd: Int32?) {
        guard let fd else { return }
        #if canImport(Darwin)
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        #else
        // Linux has no per-descriptor setting; the keeper has no other pipe to write to.
        signal(SIGPIPE, SIG_IGN)
        #endif
        let data = Array((line + "\n").utf8)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    #if DEBUG
    /// The live test's view of a shown window (ACTIONUI_MCP_TEST_REHOST_REPORT): the manifest
    /// frame and the actual one, title, subtitle, values, row counts and restored properties.
    static func testReportEntry(_ record: KeptWindowRecord, title: String, subtitle: String, frame: [Double]) -> [String: Any] {
        var values: [String: String] = [:]
        for key in record.values.keys {
            if let viewID = Int(key) {
                values[key] = ActionUISwift.getElementValueAsString(windowUUID: record.window, viewID: viewID)
            }
        }
        var rowCounts: [String: Int] = [:]
        for key in record.rows.keys {
            if let viewID = Int(key) {
                rowCounts[key] = ActionUISwift.getElementRows(windowUUID: record.window, viewID: viewID)?.count ?? -1
            }
        }
        // Each restored property as the element now holds it, re-encoded as JSON text.
        var properties: [String: [String: String]] = [:]
        for (key, named) in record.properties ?? [:] {
            guard let viewID = Int(key) else { continue }
            for name in named.keys {
                let value = ActionUISwift.getElementProperty(windowUUID: record.window, viewID: viewID, propertyName: name)
                properties[key, default: [:]][name] = value.map { JSONValue(any: $0).serialized() } ?? "missing"
            }
        }
        return ["title": title, "subtitle": subtitle, "manifest_frame": record.frame, "frame": frame,
                "values": values, "row_counts": rowCounts, "properties": properties]
    }

    /// Writes the test report to `path`.
    static func writeTestReport(_ windows: [[String: Any]], to path: String) {
        let report: [String: Any] = ["pid": Int(getpid()), "windows": windows]
        try? Data(JSONValue(any: report).serialized().utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    #endif
}

// MARK: - Server side

extension WindowHost {
    /// Seconds the server waits for the keeper to report that its windows are up, so the two sets
    /// overlap instead of flickering. Well inside the 2 s a client gives between EOF and SIGTERM.
    static let keeperReadyTimeout = 1.5

    /// Hands every open kept window to a keeper process. Called once, at shutdown. Failures are
    /// logged; the windows then close with the process, as windows that are not kept do.
    func handOffKeptWindows() {
        let kept = platform.keptWindowStates(Array(keptDocuments.keys))
        guard !kept.isEmpty else { return }

        let spool = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-mcp-rehost-\(UUID().uuidString)", isDirectory: true)
        #if os(Linux)
        // /tmp is open to every user there. FileManager makes the folder with the umask's mode and
        // only then sets 0700, and takes a folder that is already there; mkdir does neither.
        guard mkdir(spool.path, 0o700) == 0 else {
            let code = errno
            logger.log("could not hand kept windows to a new process: could not create \(spool.path) (errno \(code))", .error)
            return
        }
        #endif
        do {
            #if !os(Linux)
            try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            #endif
            var records: [KeptWindowRecord] = []
            for entry in kept {
                guard let file = keptDocuments[entry.id] else { continue }
                let name = entry.id + ".json"
                try FileManager.default.moveItem(at: file, to: spool.appendingPathComponent(name))
                keptDocuments[entry.id] = nil
                let state = snapshot(windowID: entry.id)
                let properties = agentProperties[entry.id].map { byID in
                    Dictionary(uniqueKeysWithValues: byID.map { id, named in (String(id), named.mapValues { $0.serialized() }) })
                }
                records.append(KeptWindowRecord(
                    window: entry.id, document: name, title: entry.title, subtitle: entry.subtitle,
                    frame: entry.frame, styleMask: entry.styleMask, values: state.values, rows: state.rows,
                    properties: properties))
            }
            let manifest = KeptWindowManifest(version: KeptWindowManifest.currentVersion, windows: records)
            try JSONEncoder().encode(manifest).write(to: spool.appendingPathComponent(KeptWindowManifest.fileName))
        } catch {
            logger.log("could not hand kept windows to a new process: \(error.displayText)", .error)
            try? FileManager.default.removeItem(at: spool)
            return
        }
        guard let executable = HostSupport.executablePath else {
            logger.log("could not hand kept windows to a new process: the executable path is unknown", .error)
            try? FileManager.default.removeItem(at: spool)
            return
        }
        switch KeeperLauncher.launch(executable: executable, spool: spool.path, timeout: Self.keeperReadyTimeout) {
        case .ready(let report):
            logger.log("handed \(kept.count) kept window(s) to a new process: \(report)", .info)
        case .notReady(let problem):
            // The keeper may still come up; it owns the spool directory now.
            logger.log("kept windows: \(problem)", .warning)
        case .failed(let problem):
            logger.log("could not hand kept windows to a new process: \(problem)", .error)
            try? FileManager.default.removeItem(at: spool)
        }
    }

    /// Every element value (as ActionUI's string form) and every table's rows, so the keeper shows
    /// what the user saw: rows `show` set after loading, values update_window or the user changed.
    private func snapshot(windowID: String) -> (values: [String: String], rows: [String: [[String]]]) {
        var values: [String: String] = [:]
        var rows: [String: [[String]]] = [:]
        for id in ActionUISwift.getElementInfo(windowUUID: windowID).keys {
            if let list = ActionUISwift.getElementRows(windowUUID: windowID, viewID: id) {
                rows[String(id)] = list
            }
            if let value = ActionUISwift.getElementValueAsString(windowUUID: windowID, viewID: id) {
                values[String(id)] = value
            }
        }
        return (values, rows)
    }
}
