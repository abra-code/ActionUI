// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WinUIPlatform+Mark.swift - the yellow and black mark under the title bar of every actionui-mcp window
// on Windows, as on macOS and Linux (AppKitPlatform+HazardStrip.swift, AdwaitaPlatform+HazardStrip.swift):
// on `show` windows a bar holding where the content came from (a file, with a button that shows it
// selected in File Explorer, or a web address), when the window was shown, and Save (Copy URL for content
// from the network); on the others a thin striped line. WinUIApplication draws it above the window's
// content (WindowOptions.mark), outside the ActionUI JSON, so the agent can neither change it nor press
// its buttons; it keeps working in a kept window after the session ends. Who asked leads the window's
// title (windowTitle).

#if os(Windows)
import FoundationEssentials
import WinSDK
import ucrt
import ActionUI
import ActionUIWinUIApplication
import MCPStdio

@MainActor
enum WinUIWindowMarks {
    /// The mark for a window: the bar for a `show` window's `footer`, else the strip or the line.
    static func mark(_ mark: WindowMark, footer: ShowFooter?, windowID: String) -> WinUIApplication.WindowMark {
        guard mark == .strip, let footer else {
            return WinUIApplication.WindowMark(kind: mark == .line ? .line : .strip)
        }
        // A file's path as Windows writes it (Foundation gives "C:/a/b").
        let path = footer.path.map { String($0.map { $0 == "/" ? "\\" : $0 }) }
        let source = (path ?? footer.url).map(ShowFooter.shownSource)
        typealias Button = WinUIApplication.WindowMark.Button
        var reveal: Button?
        if let path {
            // Selects the file in File Explorer; never opens it. A file that is gone gets a beep.
            reveal = Button(title: "Show in Folder", symbol: "folder", toolTip: "Show in File Explorer") {
                if !WinUIApplication.revealInFileExplorer(path: path) {
                    _ = MessageBeep(UINT(MB_OK))
                }
            }
        }
        var button: Button?
        if let save = footer.save {
            button = Button(title: "Save\u{2026}", toolTip: "Save a copy of what the window shows") {
                saveCopy(save, windowID: windowID)
            }
            #if DEBUG
            scheduleTestSave(save, windowID: windowID)
            #endif
        } else if let url = footer.url {
            button = Button(title: "Copy URL", toolTip: "Copy the web address") {
                _ = WinUIApplication.copyToClipboard(url)
            }
        }
        return WinUIApplication.WindowMark(kind: .strip, row: .init(source: source, reveal: reveal, time: shownTime(footer.shownAt),
                                                                    timeToolTip: "When the window was shown", button: button))
    }

    /// The date and time in the user's locale, short forms, as Windows writes them.
    static func shownTime(_ date: Date) -> String {
        // From seconds since 1970 to a FILETIME (100 ns since 1601), then to local time.
        // A date from a kept window's manifest may be any number: UInt64() traps on NaN or one out of range.
        let seconds = date.timeIntervalSince1970 + 11_644_473_600
        guard seconds >= 0, seconds < 900_000_000_000 else { return "" }
        let ticks = UInt64(seconds * 10_000_000)
        var utcFile = FILETIME(dwLowDateTime: DWORD(truncatingIfNeeded: ticks), dwHighDateTime: DWORD(truncatingIfNeeded: ticks >> 32))
        var utc = SYSTEMTIME()
        var local = SYSTEMTIME()
        guard FileTimeToSystemTime(&utcFile, &utc), SystemTimeToTzSpecificLocalTime(nil, &utc, &local) else { return "" }
        func formatted(_ write: (UnsafeMutablePointer<WCHAR>, Int32) -> Int32) -> String {
            var buffer = [WCHAR](repeating: 0, count: 128)
            let count = buffer.withUnsafeMutableBufferPointer { write($0.baseAddress!, Int32($0.count)) }
            return count > 0 ? String(decoding: buffer.prefix(Int(count) - 1), as: UTF16.self) : ""
        }
        let day = formatted { GetDateFormatEx(nil, DWORD(DATE_SHORTDATE), &local, nil, $0, $1, nil) }
        let time = formatted { GetTimeFormatEx(nil, DWORD(TIME_NOSECONDS), &local, nil, $0, $1) }
        return [day, time].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Asks where with Windows' save dialog, then writes there; the dialog confirms replacing a file.
    /// Nothing is written anywhere else.
    private static func saveCopy(_ save: ShowSave, windowID: String) {
        let settings = JSONValue.object(["title": .string("Save a Copy"), "nameFieldStringValue": .string(offeredName(save))])
        _ = AppPanels.beginSavePanel(json: settings.serialized()) { path in
            guard let path else { return }
            write(save.content, to: path, windowID: windowID) { error in
                guard let error else { return }
                showError("The copy could not be saved.", String(describing: error))
            }
        }
    }

    /// The name the dialog offers, with the characters Windows does not allow in a file name as "-". A "\"
    /// from the agent's title would make the dialog save into another folder than the one it shows
    /// ("..\Startup\page.html"); ShowSave.fileName replaces only "/" and ":".
    private static func offeredName(_ save: ShowSave) -> String {
        String(save.suggestedName.map { "\\<>\"|?*".contains($0) ? "-" : $0 })
    }

    /// Writes `content` to `destination`; `done` gets the error, or nil. A chart is drawn first (WinUI
    /// draws asynchronously), then written as the other kinds are.
    private static func write(_ content: ShowSave.Content, to destination: String, windowID: String,
                              done: @escaping @MainActor (Error?) -> Void) {
        if case .file(let path) = content {
            done(Result(catching: { try copyFile(path, to: destination) }).error)
            return
        }
        if case .chart = content {
            let file = HostSupport.sessionFolder.appendingPathComponent("chart-\(UUID().uuidString).png")
            WinUIApplication.shared.captureContentPNG(windowUUID: windowID, path: file.path) { written in
                defer { try? FileManager.default.removeItem(at: file) }
                done(Result(catching: {
                    guard written, let png = try? Data(contentsOf: file) else { throw MCPToolError("the chart could not be drawn") }
                    try writeBytes(of: content, windowID: windowID, chartPNG: png, to: destination)
                }).error)
            }
            return
        }
        done(Result(catching: { try writeBytes(of: content, windowID: windowID, chartPNG: Data(), to: destination) }).error)
    }

    private static func writeBytes(of content: ShowSave.Content, windowID: String, chartPNG: Data, to destination: String) throws {
        guard let data = try ShowSave.bytes(of: content, windowID: windowID, chartPNG: { chartPNG }) else { return }
        try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    /// Copies the file at `path` beside `destination`, then moves it over it: the destination is replaced
    /// whole or not at all. Saving a file onto itself writes nothing (it is already there).
    /// The paths are taken apart as text: a file URL's path drops a network share's host ("\\server\share").
    private static func copyFile(_ path: String, to destination: String) throws {
        func windowsForm(_ path: String) -> String { String(path.map { $0 == "/" ? "\\" : $0 }) }
        let target = windowsForm(destination)
        if windowsForm(path).lowercased() == target.lowercased() { return }
        guard let cut = target.lastIndex(of: "\\") else { throw MCPToolError("cannot save to \(destination): not a full path") }
        let staged = String(target[...cut]) + ".\(target[target.index(after: cut)...]).\(UUID().uuidString)"
        do {
            try FileManager.default.copyItem(atPath: path, toPath: staged)
            let failure: DWORD = staged.withCString(encodedAs: UTF16.self) { from in
                target.withCString(encodedAs: UTF16.self) { to in
                    MoveFileExW(from, to, DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) ? 0 : GetLastError()
                }
            }
            guard failure == 0 else { throw MCPToolError("could not write \(destination) (error \(failure))") }
        } catch {
            try? FileManager.default.removeItem(atPath: staged)
            throw error
        }
    }

    /// An alert with `heading` and `body`, over the active window (the one saved from may have closed meanwhile).
    private static func showError(_ heading: String, _ body: String) {
        let json = JSONValue.object(["title": .string(heading), "message": .string(body), "buttons": .array([.string("OK")])]).serialized()
        if let chosen = json.withCString({ actionUIAppRunAlert($0) }) {
            free(chosen)  // strdup from the same C runtime (actionUIFreeString is the C adapter's, not linked here)
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_SAVE_DIR=<folder>: for the live test, 1.5 seconds after the window opens, save as
    /// the Save button does, into that folder under the offered name, with no dialog.
    private static func scheduleTestSave(_ save: ShowSave, windowID: String) {
        guard let folder = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_SAVE_DIR"] else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            write(save.content, to: URL(fileURLWithPath: folder).appendingPathComponent(offeredName(save)).path, windowID: windowID) { error in
                if let error { HostSupport.logLine("[actionui-mcp] test save failed: \(error)") }
            }
        }
    }
    #endif
}

private extension Result where Failure == Error {
    /// The error, or nil when it succeeded.
    var error: Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
#endif
