// ActionUIRemoteTests/TestSupport.swift
//
// Test-only helpers. The core test target has its own versions of these (ActionUIModel+Test,
// XCTestLogger); test targets cannot share sources, and the remote tests deliberately trigger
// engine error logs (type mismatches, refused inserts), so they need a logger that records
// rather than fails.

import Foundation
@testable import ActionUI

extension ActionUIModel {
    /// Forget every window and handler so each test starts from an empty engine.
    static func resetForRemoteTests() {
        shared.windowModels.removeAll()
        shared.actionHandlers.removeAll()
        shared.removeDefaultActionHandler()
    }
}

/// Prints warnings and errors to the test log and swallows the rest. Never fails a test.
final class QuietLogger: ActionUILogger, Sendable {
    private let maxLevel: LoggerLevel

    init(maxLevel: LoggerLevel = .warning) {
        self.maxLevel = maxLevel
    }

    func log(_ message: String, _ level: LoggerLevel) {
        guard level.rawValue <= maxLevel.rawValue else { return }
        print("[\(level)] \(message)")
    }
}
