// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// HostLogger.swift - ActionUI's log, on stderr (stdout belongs to the protocol), with a capture
// window: while a document loads, errors and warnings are also collected so they can be returned
// to the agent that wrote the document.

import Foundation
import ActionUI

final class HostLogger: ActionUILogger, @unchecked Sendable {
    struct Entry {
        let level: LoggerLevel
        let message: String
    }

    private let maxLevel: LoggerLevel
    private let lock = NSLock()
    /// Non-nil while a capture is running; guarded by `lock`. ActionUI may log from any thread.
    private var captured: [Entry]?

    init(maxLevel: LoggerLevel) {
        self.maxLevel = maxLevel
    }

    func log(_ message: String, _ level: LoggerLevel) {
        lock.withLock {
            if captured != nil, level == .error || level == .warning {
                captured?.append(Entry(level: level, message: message))
            }
        }
        guard level.rawValue <= maxLevel.rawValue else { return }
        FileHandle.standardError.write(Data("[actionui-mcp][\(level)] \(message)\n".utf8))
    }

    /// Collects errors and warnings logged while `body` runs. Not reentrant; callers are on the
    /// main actor and never nest.
    func capture<T>(_ body: () throws -> T) rethrows -> (result: T, entries: [Entry]) {
        lock.withLock { captured = [] }
        defer { lock.withLock { captured = nil } }
        let result = try body()
        // ActionUI reports some problems more than once (validation runs again when the view is
        // built); the agent needs each message once.
        var seen: Set<String> = []
        let entries = lock.withLock { captured ?? [] }.filter { seen.insert($0.message).inserted }
        return (result, entries)
    }
}
