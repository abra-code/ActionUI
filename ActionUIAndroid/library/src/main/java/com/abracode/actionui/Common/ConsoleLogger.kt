package com.abracode.actionui.Common

/**
 * An [ActionUILogger] that prints to stderr/stdout, with a per-level filter.
 *
 * Mirror of Swift `ConsoleLogger` in `ActionUI/Common/ConsoleLogger.swift`.
 * Logs whose `level.rawValue` exceeds [maxLevel].rawValue are discarded —
 * use this in performance-critical paths to drop noisy DEBUG/VERBOSE output.
 *
 * Errors and warnings go to `System.err`; INFO/DEBUG/VERBOSE go to `System.out`.
 *
 * @param maxLevel Highest level to print; defaults to [LoggerLevel.verbose].
 */
class ConsoleLogger(
    private val maxLevel: LoggerLevel = LoggerLevel.verbose
) : ActionUILogger {

    override fun log(message: String, level: LoggerLevel) {
        if (level.rawValue > maxLevel.rawValue) return
        val line = "[ActionUI][${level.name}] $message"
        when (level) {
            LoggerLevel.error, LoggerLevel.warning -> System.err.println(line)
            else                                   -> println(line)
        }
    }
}
