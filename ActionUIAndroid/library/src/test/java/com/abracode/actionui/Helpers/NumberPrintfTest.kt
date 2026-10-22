package com.abracode.actionui.Helpers

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * NumberPrintf checked against the labelFormat parity cases every renderer checks
 * (FormatParity/labelformat-cases.json at the repository root, recorded from the C library on a
 * Mac): each format and value gives the case's expected text, or is refused where it expects null.
 */
class NumberPrintfTest {
    /** The cases file; unit tests run in the library module's folder. */
    private val cases: JsonObject by lazy {
        Json.parseToJsonElement(File("../../FormatParity/labelformat-cases.json").readText()).jsonObject
    }

    /** A number, or one JSON cannot write: "inf", "-inf", "nan", "-0". */
    private fun value(case: JsonObject): Double {
        val primitive = case["value"]!!.jsonPrimitive
        primitive.doubleOrNull?.takeIf { !primitive.isString }?.let { return it }
        return when (primitive.content) {
            "inf" -> Double.POSITIVE_INFINITY
            "-inf" -> Double.NEGATIVE_INFINITY
            "-0" -> -0.0
            else -> Double.NaN
        }
    }

    private fun separator(case: JsonObject): String =
        (case["decimalSeparator"] as? JsonPrimitive)?.contentOrNull ?: "."

    private fun expected(case: JsonObject): String? = (case["expected"] as? JsonPrimitive)?.contentOrNull

    @Test
    fun `every case gives its expected text`() {
        for (element in cases["cases"]!!.jsonArray) {
            val case = element.jsonObject
            val format = case["format"]!!.jsonPrimitive.content
            assertEquals("$format with ${case["value"]}", expected(case), NumberPrintf.format(format, value(case), separator(case)))
        }
    }

    @Test
    fun `the plain value is percent g with the separator`() {
        for (element in cases["plain"]!!.jsonArray) {
            val case = element.jsonObject
            assertEquals("plain ${case["value"]}", expected(case), NumberPrintf.plain(value(case), separator(case)))
        }
    }
}
