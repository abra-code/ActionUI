// Common/XCTestLogger.swift
import Foundation
import XCTest
@testable import ActionUI

/// A logger that uses XCTest assertions for error-level messages and console output for other levels.
/// Designed for use in unit tests to fail tests on errors while logging warnings, info, debug, and verbose messages to the console.
final class XCTestLogger: ActionUILogger, Sendable {
    /// The maximum logging level to include (e.g., set to .info to exclude debug and verbose logs).
    /// Logs with a level.rawValue greater than maxLevel.rawValue are ignored.
    private let maxLevel: Level
    
    /// Initializes the logger with a maximum logging level.
    /// - Parameter maxLevel: The maximum level to log (default: .verbose).
    init(maxLevel: Level = .verbose) {
        self.maxLevel = maxLevel
    }
    
    /// Logs a message with the specified severity level.
    /// - Uses XCTAssert for error-level messages to fail tests.
    /// - Uses print for warning, info, debug, and verbose levels.
    /// - Filters out logs with level.rawValue greater than maxLevel.rawValue.
    func log(_ message: String, _ level: Level) {
        guard level.rawValue <= maxLevel.rawValue else { return }
        
        switch level {
        case .error:
            XCTFail("[ERROR] \(message)")
        case .warning:
            print("[WARNING] \(message)")
        case .info:
            print("[INFO] \(message)")
        case .debug:
            print("[DEBUG] \(message)")
        case .verbose:
            print("[VERBOSE] \(message)")
        }
    }
}
