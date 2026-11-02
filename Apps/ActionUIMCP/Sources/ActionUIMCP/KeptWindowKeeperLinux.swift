// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeptWindowKeeperLinux.swift - the keeper process's side of kept windows on Linux
// (KeptWindows.swift). Wayland tells an application neither where its windows are nor their order,
// so the windows open again at their size, where the compositor puts them. Each takes the keyboard
// focus as it opens, as every window does there (AdwaitaPlatform).

#if os(Linux)
import FoundationEssentials
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

/// The `--rehost` mode: shows the handed-over windows and ends when the user closes the last one.
@MainActor
final class KeptWindowKeeper {
    /// How long the keeper waits for its windows to be on screen before it reports, in tries of 20 ms.
    private static let drawTries = 60
    private let application = AdwaitaApplication.shared
    /// The windows shown, in the manifest's order.
    private var shown: [KeptWindowRecord] = []

    /// Loads the spool directory, asks for its windows, which show when the application starts,
    /// deletes it, and reports on `readyFD` once the windows are on screen. Returns false when no
    /// window could be loaded; the caller then exits.
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
        guard !shown.isEmpty else {
            KeptWindowSupport.report("error: the new process could not load any kept window", to: readyFD)
            return false
        }
        application.handlers.didFinishLaunching = { [weak self] in
            self?.reportWhenOnScreen(readyFD: readyFD)
        }
        return true
    }

    private func show(_ record: KeptWindowRecord, file: URL) {
        guard record.frame.count == 4, let data = try? Data(contentsOf: file) else { return }
        let prepared = application.prepareWindow(json: data, windowUUID: record.window)
        guard prepared.error == nil else { return }
        var options = AdwaitaApplication.WindowOptions(subtitle: record.subtitle + KeptWindowSupport.subtitleSuffix)
        // The content's size (AdwaitaPlatform.keptWindowStates); 0 when it was not known.
        if record.frame[2] > 0, record.frame[3] > 0 {
            options.contentSize = (Int(record.frame[2]), Int(record.frame[3]))
        }
        options.isResizable = record.styleMask & AdwaitaPlatform.resizableStyle != 0
        // Into the model, which the window's widgets are built from when it shows.
        KeptWindowSupport.restore(record)
        application.presentWindow(prepared: prepared, title: record.title, options: options)
        shown.append(record)
    }

    /// Reports once every window is on screen and laid out, or after `drawTries`: the server's
    /// windows go as soon as it hears "ready".
    private func reportWhenOnScreen(readyFD: Int32?) {
        Task { @MainActor in
            for _ in 0..<Self.drawTries {
                if shown.allSatisfy({ application.windowOptions(windowUUID: $0.window) != nil }) { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            KeptWindowSupport.report("ready \(shown.count)", to: readyFD)
            #if DEBUG
            writeTestReport()
            #endif
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_REHOST_REPORT=<path>: for the live test, write what was shown to that
    /// file, then close every window a second later and end, as the user's close of the last
    /// window would. The frame is the content's size; the title is the one asked for (the runtime
    /// does not hand out a window's title).
    private func writeTestReport() {
        guard let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_REHOST_REPORT"] else { return }
        let entries: [[String: Any]] = shown.compactMap { record in
            guard let options = application.windowOptions(windowUUID: record.window) else { return nil }
            let size = options.contentSize ?? (0, 0)
            return KeptWindowSupport.testReportEntry(record, title: record.title, subtitle: options.subtitle ?? "",
                                                     frame: [0, 0, Double(size.width), Double(size.height)])
        }
        KeptWindowSupport.writeTestReport(entries, to: path)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            for record in shown {
                application.closeWindow(record.window)
            }
            // The host's close of the last window leaves the application running; the user's ends it.
            application.terminate()
        }
    }
    #endif
}
#endif
