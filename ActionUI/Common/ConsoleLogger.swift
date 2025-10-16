// Helpers/ConsoleLogger.swift
import Foundation

/// A logger that outputs messages to the console for all severity levels.
/// Supports filtering logs based on a maximum level to reduce output in performance-critical scenarios.
//@MainActor
public class ConsoleLogger: ActionUILogger {
    /// The maximum logging level to include (e.g., set to .info to exclude debug and verbose logs).
    /// Logs with a level.rawValue greater than maxLevel.rawValue are ignored.
    private let maxLevel: Level
    
    /// Initializes the logger with a maximum logging level.
    /// - Parameter maxLevel: The maximum level to log (default: .verbose).
    public init(maxLevel: Level = .verbose) {
        self.maxLevel = maxLevel
    }
    
    /// Logs a message to the console with the specified severity level.
    /// - Filters out logs with level.rawValue greater than maxLevel.rawValue.
    public func log(_ message: String, _ level: Level) {
        guard level.rawValue <= maxLevel.rawValue else { return }
        print("[ActionUI][\(level)] \(message)")
    }
}
