package com.abracode.actionui.Common

import java.io.ByteArrayOutputStream
import java.io.PrintStream
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The library's default loggers print warnings and errors in a release build and every
 * level in a debug build, as the Swift model's default logger does; a ConsoleLogger
 * drops the levels above its maximum.
 */
class ConsoleLoggerTest {

    @Test
    fun `the default level is warnings in a release build and every level in a debug build`() {
        assertEquals(LoggerLevel.warning, ConsoleLogger.defaultMaxLevel(debug = false))
        assertEquals(LoggerLevel.verbose, ConsoleLogger.defaultMaxLevel(debug = true))
    }

    @Test
    fun `a logger at warning prints errors and warnings only`() {
        val out = ByteArrayOutputStream()
        val err = ByteArrayOutputStream()
        val savedOut = System.out
        val savedErr = System.err
        System.setOut(PrintStream(out, true))
        System.setErr(PrintStream(err, true))
        try {
            val logger = ConsoleLogger(LoggerLevel.warning)
            for (level in LoggerLevel.entries) logger.log("line at ${level.name}", level)
        } finally {
            System.setOut(savedOut)
            System.setErr(savedErr)
        }
        assertEquals("", out.toString())
        assertEquals(
            listOf("[ActionUI][error] line at error", "[ActionUI][warning] line at warning"),
            err.toString().lines().filter { it.isNotEmpty() },
        )
    }
}
