// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeptWindowKeeper+Windows.swift - kept windows on Windows (KeptWindows.swift): the launcher that starts
// the keeper, and the keeper process's side. The windows open again at their content's size, where
// Windows puts them, without taking the focus.

#if os(Windows)

import FoundationEssentials
import ucrt
import WinSDK
import ActionUI
import ActionUISwiftAdapter
import ActionUIWinUIApplication
import MCPStdio

/// Starts the keeper with CreateProcessW. It inherits one handle only, the write end of a pipe on which it
/// reports one line once its windows are up (a handle list: never the client's pipes, which would keep the
/// session open). It has no console and a process group of its own, so the client's Ctrl+C or Ctrl+Break
/// misses it, and it leaves the client's job when the job lets it, so ending the job does not end it.
enum KeeperLauncher {
    enum Outcome {
        case ready(String)
        case notReady(String)
        case failed(String)
    }

    /// PROC_THREAD_ATTRIBUTE_HANDLE_LIST, a macro Swift does not see: ProcThreadAttributeHandleList (2)
    /// with PROC_THREAD_ATTRIBUTE_INPUT.
    private static let handleListAttribute = DWORD_PTR(0x0002_0002)

    static func launch(executable: String, spool: String, timeout: Double) -> Outcome {
        var security = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                           lpSecurityDescriptor: nil, bInheritHandle: true)
        var readEnd: HANDLE? = nil
        var writeEnd: HANDLE? = nil
        guard CreatePipe(&readEnd, &writeEnd, &security, 0), let readEnd, let writeEnd else {
            return .failed("CreatePipe failed (Windows error \(GetLastError()))")
        }
        defer { CloseHandle(readEnd) }
        var writeEndOpen = true
        defer { if writeEndOpen { CloseHandle(writeEnd) } }
        guard SetHandleInformation(readEnd, DWORD(HANDLE_FLAG_INHERIT), 0) else {
            return .failed("SetHandleInformation failed (Windows error \(GetLastError()))")
        }

        var listSize: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, 1, 0, &listSize)
        guard listSize > 0 else { return .failed("InitializeProcThreadAttributeList failed (Windows error \(GetLastError()))") }
        let listMemory = UnsafeMutableRawPointer.allocate(byteCount: Int(listSize), alignment: 16)
        defer { listMemory.deallocate() }
        let list = LPPROC_THREAD_ATTRIBUTE_LIST(listMemory)
        guard InitializeProcThreadAttributeList(list, 1, 0, &listSize) else {
            return .failed("InitializeProcThreadAttributeList failed (Windows error \(GetLastError()))")
        }
        defer { DeleteProcThreadAttributeList(list) }
        // Read by CreateProcessW: alive until it returns.
        let inherited = UnsafeMutablePointer<HANDLE?>.allocate(capacity: 1)
        defer { inherited.deallocate() }
        inherited.initialize(to: writeEnd)
        guard UpdateProcThreadAttribute(list, 0, handleListAttribute, inherited, SIZE_T(MemoryLayout<HANDLE?>.size), nil, nil) else {
            return .failed("UpdateProcThreadAttribute failed (Windows error \(GetLastError()))")
        }

        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        // No standard handles: without this, the keeper would get the server's handle values, which name
        // nothing (or something else) in a process that did not inherit them.
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.lpAttributeList = list

        let handleValue = UInt(bitPattern: writeEnd)
        let arguments = [executable, "--rehost", spool, "--ready-fd", String(handleValue)]
        var commandLine = Array(arguments.map(quotedArgument).joined(separator: " ").utf16) + [0]
        let baseFlags = DWORD(EXTENDED_STARTUPINFO_PRESENT) | DWORD(CREATE_UNICODE_ENVIRONMENT) | DWORD(DETACHED_PROCESS)
            | DWORD(CREATE_NEW_PROCESS_GROUP)
        var process = PROCESS_INFORMATION()
        // In the folder that holds the spool (the user's temporary folder), not the server's: a process's
        // current folder cannot be deleted or renamed on Windows, and a keeper may run for days. The
        // server takes only absolute paths, so nothing resolves against it.
        // Only a drive path (else the server's own folder): CreateProcessW refuses one it cannot use.
        let parent = spool.lastIndex(where: { $0 == "\\" || $0 == "/" }).map { String(spool[..<$0]) }
        let folder = parent.flatMap { HostSupport.isAbsolutePath($0) ? $0 : nil }
        func start(_ flags: DWORD) -> Bool {
            executable.withCString(encodedAs: UTF16.self) { application in
                withOptionalWideString(folder) { currentFolder in
                    withUnsafeMutablePointer(to: &startup) { info in
                        info.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { startupInfo in
                            CreateProcessW(application, &commandLine, nil, nil, true, flags, nil, currentFolder, startupInfo, &process)
                        }
                    }
                }
            }
        }
        // A job that does not allow leaving it refuses the breakaway: then the keeper stays in it.
        var started = start(baseFlags | DWORD(CREATE_BREAKAWAY_FROM_JOB))
        if !started, GetLastError() == DWORD(ERROR_ACCESS_DENIED) {
            started = start(baseFlags)
        }
        guard started else { return .failed("CreateProcessW failed (Windows error \(GetLastError()))") }
        CloseHandle(process.hThread)
        defer { CloseHandle(process.hProcess) }
        // The keeper holds its own copy; closed here, its exit ends the pipe.
        CloseHandle(writeEnd)
        writeEndOpen = false
        let pid = process.dwProcessId

        // One line: "ready <n>" or "error: <text>". The end of the pipe without it means the keeper exited.
        var line: [UInt8] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 512)
        while !line.contains(UInt8(ascii: "\n")) {
            guard deadline.timeIntervalSinceNow > 0 else {
                return .notReady("the new process (pid \(pid)) did not report within \(timeout) s")
            }
            var available: DWORD = 0
            guard PeekNamedPipe(readEnd, nil, 0, nil, &available, nil) else {
                if GetLastError() == DWORD(ERROR_BROKEN_PIPE) { break }
                return .notReady("PeekNamedPipe failed (Windows error \(GetLastError()))")
            }
            if available == 0 {
                Sleep(20)
                continue
            }
            var count: DWORD = 0
            guard ReadFile(readEnd, &buffer, DWORD(buffer.count), &count, nil) else {
                if GetLastError() == DWORD(ERROR_BROKEN_PIPE) { break }
                return .notReady("ReadFile failed (Windows error \(GetLastError()))")
            }
            line.append(contentsOf: buffer[0..<Int(count)])
        }
        let text = String(decoding: line, as: UTF8.self).trimmed
        if text.hasPrefix("ready") { return .ready("pid \(pid), \(text)") }
        return .failed(text.isEmpty ? "the new process (pid \(pid)) exited without showing a window" : text)
    }

    /// `body` with `text` as a NUL-terminated UTF-16 string, or nil.
    private static func withOptionalWideString<Result>(_ text: String?, _ body: (UnsafePointer<UInt16>?) -> Result) -> Result {
        guard let text else { return body(nil) }
        return text.withCString(encodedAs: UTF16.self) { body($0) }
    }

    /// `argument` as CommandLineToArgvW and the C runtime read it back: in quotes, with a quote escaped by a
    /// backslash and the backslashes before a quote (or the closing one) doubled.
    static func quotedArgument(_ argument: String) -> String {
        var quoted = "\""
        var backslashes = 0
        for character in argument {
            if character == "\\" {
                backslashes += 1
                continue
            }
            if character == "\"" {
                quoted += String(repeating: "\\", count: backslashes * 2 + 1) + "\""
            } else {
                quoted += String(repeating: "\\", count: backslashes) + String(character)
            }
            backslashes = 0
        }
        return quoted + String(repeating: "\\", count: backslashes * 2) + "\""
    }
}

/// The `--rehost` mode: shows the handed-over windows and ends when the user closes the last one.
@MainActor
final class KeptWindowKeeper {
    /// How long the keeper waits for its windows to be on screen before it reports, in tries of 20 ms.
    private static let drawTries = 60

    private let application = WinUIApplication.shared
    /// The windows shown, in the manifest's order.
    private var shown: [KeptWindowRecord] = []

    /// Loads the spool directory, asks for its windows, which show when the application starts, deletes
    /// it, and reports on `readyFD` (the value of the pipe handle the launcher passed) once the windows are
    /// on screen. Returns false when no window could be loaded; the caller then exits.
    func start(spool: URL, readyFD: Int32?) -> Bool {
        let report = readyFD.flatMap(Self.descriptor(handleValue:))
        let manifest: KeptWindowManifest
        switch KeptWindowSupport.manifest(in: spool) {
        case .success(let read):
            manifest = read
        case .failure(let error):
            // Not deleted: without a manifest this may be any directory. The server removes its own.
            KeptWindowSupport.report("error: " + error.message, to: report)
            return false
        }
        defer { try? FileManager.default.removeItem(at: spool) }
        // The kept windows are the server's own, handed over in the spool folder (MCPTrustPolicy).
        MCPTrustPolicy.install(windowFolder: spool)
        ActionUISwift.setDefaultActionHandler { _, _, _, _, _ in }  // no agent is listening any more
        for record in manifest.windows {
            show(record, file: spool.appendingPathComponent(record.json))
        }
        guard !shown.isEmpty else {
            KeptWindowSupport.report("error: the new process could not load any kept window", to: report)
            return false
        }
        application.handlers.didFinishLaunching = { [weak self] in
            self?.reportWhenOnScreen(report)
        }
        return true
    }

    /// A C runtime descriptor for the pipe handle whose value the launcher passed; nil when it names no pipe
    /// (the keeper started by hand with a made-up number).
    private static func descriptor(handleValue: Int32) -> Int32? {
        guard handleValue > 0, let handle = HANDLE(bitPattern: Int(handleValue)), GetFileType(handle) == DWORD(FILE_TYPE_PIPE) else {
            return nil
        }
        // Not handed on to processes the keeper starts.
        _ = SetHandleInformation(handle, DWORD(HANDLE_FLAG_INHERIT), 0)
        let fd = _open_osfhandle(Int(handleValue), _O_WRONLY)
        return fd >= 0 ? fd : nil
    }

    private func show(_ record: KeptWindowRecord, file: URL) {
        guard record.frame.count == 4, let data = try? Data(contentsOf: file) else { return }
        let prepared = application.prepareWindow(json: data, windowUUID: record.window)
        guard prepared.error == nil else { return }
        var options = WinUIApplication.WindowOptions(subtitle: record.subtitle + KeptWindowSupport.subtitleSuffix)
        // The content's size (WinUIPlatform.keptWindowStates); 0 when it was not known.
        if record.frame[2] > 0, record.frame[3] > 0 {
            options.contentSize = (Int(record.frame[2].rounded()), Int(record.frame[3].rounded()))
        }
        options.isResizable = record.styleMask & WinUIPlatform.resizableStyle != 0
        // Where it was, when that is still on a monitor (WinUIApplication.WindowOptions.position).
        if record.styleMask & WinUIPlatform.positionedStyle != 0,
           let x = Int32(exactly: record.frame[0].rounded()), let y = Int32(exactly: record.frame[1].rounded()) {
            options.position = (x, y)
        }
        // The user keeps the focus wherever it was, as on macOS.
        options.activates = false
        // Into the model, which the window's tree is built from when it shows.
        KeptWindowSupport.restore(record)
        application.presentWindow(prepared: prepared, title: record.title, options: options)
        shown.append(record)
    }

    /// Reports once every window is laid out, or after `drawTries`: the server's windows go as soon as it
    /// hears "ready".
    private func reportWhenOnScreen(_ report: Int32?) {
        Task { @MainActor in
            for _ in 0..<Self.drawTries {
                if shown.allSatisfy({ application.contentSize(windowUUID: $0.window) != nil }) { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            KeptWindowSupport.report("ready \(shown.count)", to: report)
            #if DEBUG
            writeTestReport()
            #endif
        }
    }

    #if DEBUG
    /// ACTIONUI_MCP_TEST_REHOST_REPORT=<path>: for the live test, write what was shown to that file, then
    /// close every window a second later and end, as the user's close of the last window would. The frame
    /// is the window's place and its content's size, as WinUIPlatform.keptWindowStates gives them; the title is
    /// the one asked for.
    private func writeTestReport() {
        guard let path = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_REHOST_REPORT"] else { return }
        let entries: [[String: Any]] = shown.compactMap { record in
            guard let size = application.contentSize(windowUUID: record.window),
                  let position = application.position(windowUUID: record.window) else { return nil }
            return KeptWindowSupport.testReportEntry(record, title: record.title,
                                                     subtitle: record.subtitle + KeptWindowSupport.subtitleSuffix,
                                                     frame: [Double(position.x), Double(position.y),
                                                             size.width.rounded(), size.height.rounded()])
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
