package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for the pure substitution core of [TemplateHelper]: column-reference
 * replacement in strings, recursive substitution through JSON, and whole-element
 * substitution. The `@Composable` [TemplateHelper.BuildTemplateRow] is exercised
 * by the app.
 */
class TemplateHelperTest {

    private val row = listOf("Mercury", "1", "rocky")

    @Test
    fun `substitutes 1-based column references`() {
        assertEquals("Mercury", TemplateHelper.substituteString("$1", row))
        assertEquals("1", TemplateHelper.substituteString("$2", row))
        assertEquals("rocky", TemplateHelper.substituteString("$3", row))
    }

    @Test
    fun `dollar-zero joins all columns`() {
        assertEquals("Mercury, 1, rocky", TemplateHelper.substituteString("$0", row))
    }

    @Test
    fun `substitution is embedded and combines multiple refs`() {
        assertEquals("Mercury (rocky)", TemplateHelper.substituteString("$1 ($3)", row))
    }

    @Test
    fun `out-of-range reference is left literal`() {
        assertEquals("$9", TemplateHelper.substituteString("$9", row))
    }

    @Test
    fun `multi-digit reference reads the right column (not dollar-1 then 2)`() {
        val wide = (1..12).map { "c$it" } // c1..c12
        assertEquals("c12", TemplateHelper.substituteString("$12", wide))
    }

    @Test
    fun `single pass does not re-substitute a column value containing a reference`() {
        // Column 0 itself contains "$2"; single-pass means it is not re-expanded.
        assertEquals("$2", TemplateHelper.substituteString("$1", listOf("\$2", "evil")))
    }

    @Test
    fun `substituteJson reaches nested strings and leaves non-strings alone`() {
        val input = buildJsonObject {
            put("text", "$1")
            put("count", 7)            // number untouched
            put("flag", true)          // boolean untouched
            put("nested", buildJsonObject { put("label", "$3") })
            put("list", buildJsonArray { add(JsonPrimitive("$2")); add(JsonPrimitive(5)) })
        }

        val out = TemplateHelper.substituteJson(input, row) as JsonObject
        assertEquals("Mercury", (out["text"] as JsonPrimitive).content)
        assertEquals("7", (out["count"] as JsonPrimitive).content)
        assertEquals("true", (out["flag"] as JsonPrimitive).content)
        assertEquals("rocky", (out["nested"]!!.jsonObject["label"] as JsonPrimitive).content)
        assertEquals("1", (out["list"]!!.jsonArray[0] as JsonPrimitive).content)
        assertEquals("5", (out["list"]!!.jsonArray[1] as JsonPrimitive).content)
    }

    @Test
    fun `substituteElement substitutes properties, children, and content`() {
        val template = ActionUIElement(
            id = 1, type = "HStack",
            properties = buildJsonObject { put("title", "$1") },
            children = listOf(
                ActionUIElement(type = "Text", properties = buildJsonObject { put("text", "$2") }),
            ),
            content = ActionUIElement(type = "Text", properties = buildJsonObject { put("text", "$3") }),
        )

        val out = TemplateHelper.substituteElement(template, row)

        assertEquals("Mercury", (out.properties!!["title"] as JsonPrimitive).content)
        assertEquals("1", (out.children!![0].properties!!["text"] as JsonPrimitive).content)
        assertEquals("rocky", (out.content!!.properties!!["text"] as JsonPrimitive).content)
    }
}
