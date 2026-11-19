package com.abracode.actionui.Common

import com.abracode.actionui.BuildConfig

/**
 * An [ActionUILogger] that prints to stderr/stdout, with a per-level filter.
 *
 * Mirror of Swift `ConsoleLogger` in `ActionUI/Common/ConsoleLogger.swift`.
 * Logs whose `level.rawValue` exceeds [maxLevel].rawValue are discarded -
 * use this in performance-critical paths to drop noisy DEBUG/VERBOSE output.
 *
 * Errors and warnings go to `System.err`; INFO/DEBUG/VERBOSE go to `System.out`.
 *
 * The library's own default loggers ([com.abracode.actionui.ActionUI.defaultLogger],
 * [ActionUIModel.logger] and the composition default) use [defaultMaxLevel]: warnings and
 * errors in a release build of the library, every level in a debug build, as the Swift
 * model's default logger does. Standard output and standard error go to the device log,
 * where addresses, paths and dialog texts in the detailed lines do not belong in a
 * release app. A host that wants every level passes `ConsoleLogger(LoggerLevel.verbose)`.
 *
 * @param maxLevel Highest level to print; defaults to [LoggerLevel.verbose].
 */
class ConsoleLogger(
    private val maxLevel: LoggerLevel = LoggerLevel.verbose
) : ActionUILogger {

    companion object {
        /** The level the library's default loggers print up to (see the class comment). */
        val defaultMaxLevel: LoggerLevel get() = defaultMaxLevel(BuildConfig.DEBUG)

        internal fun defaultMaxLevel(debug: Boolean): LoggerLevel =
            if (debug) LoggerLevel.verbose else LoggerLevel.warning
    }

    override fun log(message: String, level: LoggerLevel) {
        if (level.rawValue > maxLevel.rawValue) return
        val line = "[ActionUI][${level.name}] $message"
        when (level) {
            LoggerLevel.error, LoggerLevel.warning -> System.err.println(line)
            else                                   -> println(line)
        }
    }
}
