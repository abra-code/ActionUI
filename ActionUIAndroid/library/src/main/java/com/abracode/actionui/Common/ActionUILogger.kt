package com.abracode.actionui.Common

import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * CompositionLocal carrying the active [ActionUILogger] through the rendered
 * tree. `ActionUI.Render` provides it; element builders read it via
 * `LocalActionUILogger.current` to forward warnings (unknown colors, missing
 * SwiftUI-only alignment equivalents, etc.) without threading an explicit
 * logger parameter through every Composable signature.
 *
 * `staticCompositionLocalOf` because the logger rarely changes within a
 * rendered tree — subtree overrides aren't expected and the value is read
 * frequently.
 */
val LocalActionUILogger: ProvidableCompositionLocal<ActionUILogger> =
    staticCompositionLocalOf { ConsoleLogger() }

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
