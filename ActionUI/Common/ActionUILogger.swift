// Common/ActionUILogger.swift
import Foundation

/// Protocol for logging messages in the ActionUI library with specified severity levels.
/// Used for debugging, error reporting, and informational logging during view rendering and validation.
protocol ActionUILogger {
    /// Logs a message with the specified severity level.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - level: The severity level of the message (error, warning, info, debug, or verbose).
    func log(_ message: String, _ level: Level)
}

/// Enum defining the severity levels for logging in the ActionUI library.
/// Uses Int raw values to enable filtering logs below a certain level (e.g., log only if level.rawValue <= maxLevel).
/// Lower values indicate higher severity.
enum Level: Int {
    /// Indicates a critical issue that may prevent normal operation (e.g., invalid JSON causing view rendering failure).
    case error = 1
    /// Indicates a non-critical issue that may affect functionality (e.g., missing optional property with a fallback).
    case warning = 2
    /// Indicates general information for debugging or tracking (e.g., view registration or state update).
    case info = 3
    /// Indicates detailed debugging information for developers (e.g., intermediate state changes or binding updates).
    case debug = 4
    /// Indicates exhaustive diagnostic information (e.g., every property validation or view construction step).
    case verbose = 5
}
