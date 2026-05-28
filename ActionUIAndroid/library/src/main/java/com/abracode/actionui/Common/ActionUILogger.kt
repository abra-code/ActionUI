package com.abracode.actionui.Common

/**
 * Logger interface for the ActionUI library with leveled messages.
 *
 * Mirror of Swift `ActionUILogger` protocol in
 * `ActionUI/Common/ActionUILogger.swift`. Implementations should be safe to
 * invoke from any thread the renderer happens to run on.
 *
 * Used for debugging, error reporting, and informational logging during view
 * rendering and validation.
 */
interface ActionUILogger {
    /**
     * Logs a message with the specified severity level.
     *
     * @param message The message to log.
     * @param level The severity level of the message.
     */
    fun log(message: String, level: LoggerLevel)
}

/**
 * Severity levels for ActionUI logging. Lower [rawValue] means higher severity.
 *
 * Mirror of Swift `LoggerLevel` enum. The raw values must agree across both
 * platforms so JSON-driven configuration ("log up to level 3") behaves the
 * same way on Android and Apple targets.
 */
enum class LoggerLevel(val rawValue: Int) {
    /** Critical issue that may prevent normal operation (e.g., invalid JSON). */
    error(1),
    /** Non-critical issue that may affect functionality (e.g., dropped key). */
    warning(2),
    /** General information for debugging or tracking. */
    info(3),
    /** Detailed debugging information. */
    debug(4),
    /** Exhaustive diagnostic information. */
    verbose(5);
}
