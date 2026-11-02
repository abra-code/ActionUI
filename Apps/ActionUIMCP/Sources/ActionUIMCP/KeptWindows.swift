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
// same places, deletes the spool directory, and quits when its last window closes. Its windows
// are no longer connected to any agent: actions go nowhere, and the title bar says so.
//
// SIGKILL sent to the server with no earlier stdin EOF or SIGTERM leaves no chance to hand off.
// Clients close stdin first (the TypeScript SDK waits 2 s before SIGTERM, 2 s more before
// SIGKILL), and a client that dies abruptly closes the pipe as well, so the EOF path covers both.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
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
        do {
            try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
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
