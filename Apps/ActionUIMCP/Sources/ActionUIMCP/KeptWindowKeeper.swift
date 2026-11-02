// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeptWindowKeeper.swift - the keeper process's side of kept windows (KeptWindows.swift).

#if canImport(AppKit)
import AppKit
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

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

    /// Properties the agent set (checked when it set them), then rows, then values, so a replaced
    /// chart description is in place before its rows and a table's selection finds its row. Only
    /// rows and values that differ from the freshly loaded document are written, so nothing the
    /// user did not change is touched.
    private func restore(_ record: KeptWindowRecord) {
        let id = record.window
        for (key, named) in record.properties ?? [:] {
            guard let viewID = Int(key) else { continue }
            for (name, json) in named {
                guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) else { continue }
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
        } else {
            // A keeper can run for days: the closed window's model goes with it, after this turn,
            // as the server does.
            DispatchQueue.main.async { ActionUISwift.removeWindow(windowUUID: id) }
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_REHOST_REPORT=<path>: for the live test, write what was shown (pid, and per
    /// window the manifest frame, the actual frame, title, subtitle, values, row counts and restored
    /// properties) to that file, then close every window a second later, which must end the
    /// process.
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
            // Each restored property as the element now holds it, re-encoded as JSON text.
            var properties: [String: [String: String]] = [:]
            for (key, named) in record.properties ?? [:] {
                guard let viewID = Int(key) else { continue }
                for name in named.keys {
                    let value = ActionUISwift.getElementProperty(windowUUID: record.window, viewID: viewID, propertyName: name)
                    properties[key, default: [:]][name] = value.map { JSONValue(any: $0).serialized() } ?? "missing"
                }
            }
            return ["title": window.title, "subtitle": window.subtitle, "manifest_frame": record.frame,
                    "frame": [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
                    "values": values, "row_counts": rowCounts, "properties": properties]
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
#endif
