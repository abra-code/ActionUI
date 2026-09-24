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

import AppKit
import ActionUI
import ActionUISwiftAdapter

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
        let order = NSApp.orderedWindows  // front to back
        let kept = keptDocuments.compactMap { id, file in windows[id].map { (id: id, file: file, window: $0) } }
            .sorted { (order.firstIndex(of: $0.window) ?? Int.max) > (order.firstIndex(of: $1.window) ?? Int.max) }
        guard !kept.isEmpty else { return }

        let spool = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-mcp-rehost-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var records: [KeptWindowRecord] = []
            for entry in kept {
                let name = entry.id + ".json"
                try FileManager.default.moveItem(at: entry.file, to: spool.appendingPathComponent(name))
                keptDocuments[entry.id] = nil
                let state = snapshot(windowID: entry.id)
                let frame = entry.window.frame
                records.append(KeptWindowRecord(
                    window: entry.id, document: name, title: entry.window.title, subtitle: entry.window.subtitle,
                    frame: [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
                    styleMask: entry.window.styleMask.rawValue, values: state.values, rows: state.rows))
            }
            let manifest = KeptWindowManifest(version: KeptWindowManifest.currentVersion, windows: records)
            try JSONEncoder().encode(manifest).write(to: spool.appendingPathComponent(KeptWindowManifest.fileName))
        } catch {
            logger.log("could not hand kept windows to a new process: \(error.localizedDescription)", .error)
            try? FileManager.default.removeItem(at: spool)
            return
        }
        guard let executable = Bundle.main.executableURL?.path else {
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

/// Starts the keeper with posix_spawn: a new session (POSIX_SPAWN_SETSID), so signals the client
/// sends to the server's process group miss it; only descriptors 0-3 are passed
/// (POSIX_SPAWN_CLOEXEC_DEFAULT), so it never holds the client's pipes open. Descriptor 3 is the
/// write end of a pipe on which the keeper reports one line once its windows are up.
enum KeeperLauncher {
    enum Outcome {
        case ready(String)
        case notReady(String)
        case failed(String)
    }

    static let readyFD: Int32 = 3

    static func launch(executable: String, spool: String, timeout: Double) -> Outcome {
        var pipeFDs: [Int32] = [-1, -1]
        guard pipe(&pipeFDs) == 0 else { return .failed("pipe failed (errno \(errno))") }
        let readEnd = pipeFDs[0]
        let writeEnd = pipeFDs[1]
        defer { close(readEnd) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, readyFD)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                     | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        // The server ignores SIGPIPE, SIGTERM and SIGHUP; an ignored disposition survives exec.
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGPIPE, SIGTERM, SIGHUP, SIGINT] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        let arguments = [executable, "--rehost", spool, "--ready-fd", String(readyFD)]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
        close(writeEnd)
        guard status == 0 else { return .failed("posix_spawn failed (errno \(status))") }

        // One line: "ready <n>" or "error: <text>". EOF without it means the keeper exited.
        var line = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 512)
        while !line.contains(UInt8(ascii: "\n")) {
            let remaining = Int(deadline.timeIntervalSinceNow * 1000)
            guard remaining > 0 else { return .notReady("the new process (pid \(pid)) did not report within \(timeout) s") }
            var descriptor = pollfd(fd: readEnd, events: Int16(POLLIN), revents: 0)
            let polled = poll(&descriptor, 1, Int32(remaining))
            if polled < 0 {
                if errno == EINTR { continue }
                return .notReady("poll failed (errno \(errno))")
            }
            if polled == 0 { continue }
            let count = read(readEnd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                return .notReady("read failed (errno \(errno))")
            }
            if count == 0 { break }
            line.append(contentsOf: buffer[0..<count])
        }
        let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("ready") { return .ready("pid \(pid), \(text)") }
        return .failed(text.isEmpty ? "the new process (pid \(pid)) exited without showing a window" : text)
    }
}

// MARK: - Keeper side

/// The `--rehost` mode: shows the handed-over windows and quits when the last one closes.
@MainActor
final class KeptWindowKeeper: NSObject, NSWindowDelegate {
    static let subtitleSuffix = " (session ended)"

    private var windows: [String: NSWindow] = [:]
    private var controllers: [String: NSViewController] = [:]

    /// Loads the spool directory, shows its windows, deletes it, and reports on `readyFD`.
    /// Returns false when no window could be shown; the caller then exits.
    func start(spool: URL, readyFD: Int32?) -> Bool {
        let manifest: KeptWindowManifest
        do {
            let data = try Data(contentsOf: spool.appendingPathComponent(KeptWindowManifest.fileName))
            manifest = try JSONDecoder().decode(KeptWindowManifest.self, from: data)
        } catch {
            // Not deleted: without a manifest this may be any directory. The server removes its own.
            report("error: the new process could not read the kept windows: \(error.localizedDescription)", to: readyFD)
            return false
        }
        defer { try? FileManager.default.removeItem(at: spool) }
        guard manifest.version == KeptWindowManifest.currentVersion else {
            report("error: kept windows manifest version \(manifest.version) is not supported", to: readyFD)
            return false
        }
        ActionUISwift.setDefaultActionHandler { _, _, _, _, _ in }  // no agent is listening any more
        for record in manifest.windows {
            show(record, file: spool.appendingPathComponent(record.document))
        }
        guard !windows.isEmpty else {
            report("error: the new process could not load any kept window", to: readyFD)
            return false
        }
        NSApp.setActivationPolicy(.regular)
        // Drawn and sent to the window server before reporting: the server's windows disappear as
        // soon as it hears "ready", and the run loop has not had a pass yet.
        windows.values.forEach { $0.displayIfNeeded() }
        CATransaction.flush()
        report("ready \(windows.count)", to: readyFD)
        #if DEBUG
        writeTestReport(manifest)
        #endif
        return true
    }

    private func show(_ record: KeptWindowRecord, file: URL) {
        guard record.frame.count == 4 else { return }
        // Local loading is synchronous: the file can go once the view is built.
        let controller = ActionUISwift.loadHostingController(from: file, windowUUID: record.window, isContentView: true)
        let frame = NSRect(x: record.frame[0], y: record.frame[1], width: record.frame[2], height: record.frame[3])
        let window = NSWindow(contentRect: frame, styleMask: NSWindow.StyleMask(rawValue: record.styleMask),
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.view
        // After the content view, which resets both (see WindowHost.openWindow).
        window.title = record.title
        window.subtitle = record.subtitle + Self.subtitleSuffix
        window.setFrame(frame, display: false)
        // Once the view is installed, as openViewer sets a table's rows.
        restore(record)
        window.delegate = self
        windows[record.window] = window
        controllers[record.window] = controller
        // Not activated: the user keeps focus wherever it was.
        window.orderFrontRegardless()
    }

    /// Rows first, then values, so a table's selection finds its row. Only what differs from the
    /// freshly loaded document is written, so nothing the user did not change is touched.
    private func restore(_ record: KeptWindowRecord) {
        let id = record.window
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

    private func report(_ line: String, to fd: Int32?) {
        guard let fd else { return }
        // A server that stopped waiting has closed the read end; EPIPE then, not a fatal SIGPIPE.
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        let data = Array((line + "\n").utf8)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        controllers[id] = nil
        if windows.isEmpty {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_REHOST_REPORT=<path>: for the live test, write what was shown (pid, and per
    /// window the manifest frame, the actual frame, title, subtitle, values) to that file, then
    /// close every window a second later, which must end the process.
    private func writeTestReport(_ manifest: KeptWindowManifest) {
        guard let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_REHOST_REPORT"] else { return }
        let shown: [[String: Any]] = manifest.windows.compactMap { record in
            guard let window = windows[record.window] else { return nil }
            let frame = window.frame
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
            return ["title": window.title, "subtitle": window.subtitle, "manifest_frame": record.frame,
                    "frame": [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
                    "values": values, "row_counts": rowCounts]
        }
        let report: [String: Any] = ["pid": Int(getpid()), "windows": shown]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.windows.values.forEach { $0.close() }
        }
    }
    #endif
}
