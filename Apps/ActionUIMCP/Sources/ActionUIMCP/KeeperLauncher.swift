// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeeperLauncher.swift - starts the process that keeps windows after the session (KeptWindows.swift).

#if canImport(Darwin)
import Foundation
#else
import FoundationEssentials
import Glibc
#endif

/// Starts the keeper with posix_spawn: a new session (POSIX_SPAWN_SETSID), so signals the client
/// sends to the server's process group miss it; only descriptors 0-3 are passed (macOS:
/// POSIX_SPAWN_CLOEXEC_DEFAULT; Linux: the descriptors above 3 closed in the child), so it never
/// holds the client's pipes open. Descriptor 3 is the write end of a pipe on which the keeper
/// reports one line once its windows are up.
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

        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        // glibc's POSIX_SPAWN_SETSID (spawn.h, glibc 2.26 and later), which Swift does not see: it
        // is declared only with _GNU_SOURCE.
        let flags: Int32 = 0x80
        #endif
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, readyFD)
        #if !canImport(Darwin)
        // What POSIX_SPAWN_CLOEXEC_DEFAULT does on macOS (glibc 2.34 and later).
        posix_spawn_file_actions_addclosefrom_np(&actions, readyFD + 1)
        #endif

        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(flags | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
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
        #if canImport(Darwin)
        let status = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
        #else
        // glibc declares environ only with _GNU_SOURCE, too: the same variables, built here.
        var environment: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { environment.forEach { free($0) } }
        let status = posix_spawn(&pid, executable, &actions, &attributes, &argv, &environment)
        #endif
        close(writeEnd)
        guard status == 0 else { return .failed("posix_spawn failed (errno \(status))") }

        // One line: "ready <n>" or "error: <text>". EOF without it means the keeper exited.
        var line: [UInt8] = []
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
        let text = String(decoding: line, as: UTF8.self).trimmed
        if text.hasPrefix("ready") { return .ready("pid \(pid), \(text)") }
        return .failed(text.isEmpty ? "the new process (pid \(pid)) exited without showing a window" : text)
    }
}
