// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeptWindowKeeper.swift - the keeper process's side of kept windows on macOS (KeptWindows.swift).

#if canImport(AppKit)
import AppKit
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

/// The `--rehost` mode: shows the handed-over windows and quits when the last one closes.
@MainActor
final class KeptWindowKeeper: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var controllers: [String: NSViewController] = [:]

    /// Loads the spool directory, shows its windows, deletes it, and reports on `readyFD`.
    /// Returns false when no window could be shown; the caller then exits.
    func start(spool: URL, readyFD: Int32?) -> Bool {
        let manifest: KeptWindowManifest
        switch KeptWindowSupport.manifest(in: spool) {
        case .success(let read):
            manifest = read
        case .failure(let error):
            // Not deleted: without a manifest this may be any directory. The server removes its own.
            KeptWindowSupport.report("error: " + error.message, to: readyFD)
            return false
        }
        defer { try? FileManager.default.removeItem(at: spool) }
        ActionUISwift.setDefaultActionHandler { _, _, _, _, _ in }  // no agent is listening any more
        for record in manifest.windows {
            show(record, file: spool.appendingPathComponent(record.document))
        }
        guard !windows.isEmpty else {
            KeptWindowSupport.report("error: the new process could not load any kept window", to: readyFD)
            return false
        }
        AppKitPlatform.showInDock()
        // Drawn and sent to the window server before reporting: the server's windows disappear as
        // soon as it hears "ready", and the run loop has not had a pass yet.
        windows.values.forEach { $0.displayIfNeeded() }
        CATransaction.flush()
        KeptWindowSupport.report("ready \(windows.count)", to: readyFD)
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
        window.subtitle = record.subtitle + KeptWindowSupport.subtitleSuffix
        window.setFrame(frame, display: false)
        // Once the view is installed, as openViewer sets a table's rows.
        KeptWindowSupport.restore(record)
        window.delegate = self
        windows[record.window] = window
        controllers[record.window] = controller
        // Not activated: the user keeps focus wherever it was.
        window.orderFrontRegardless()
        AppKitPlatform.listInWindowsMenu(window)
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
    /// ACTIONUI_MCP_TEST_REHOST_REPORT=<path>: for the live test, write what was shown to that
    /// file, then close every window a second later, which must end the process.
    private func writeTestReport(_ manifest: KeptWindowManifest) {
        guard let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_REHOST_REPORT"] else { return }
        let shown: [[String: Any]] = manifest.windows.compactMap { record in
            guard let window = windows[record.window] else { return nil }
            let frame = window.frame
            return KeptWindowSupport.testReportEntry(record, title: window.title, subtitle: window.subtitle,
                                                     frame: [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height])
        }
        KeptWindowSupport.writeTestReport(shown, to: path)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.windows.values.forEach { $0.close() }
        }
    }
    #endif
}
#endif
