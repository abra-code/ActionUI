package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [Picker]. Covers the pure options parser ([parsePickerOptions],
 * incl. the simple-array, explicit-tag, section, divider, and invalid-entry
 * cases mirrored from the Apple `extractSections`), the style resolution
 * ([resolvePickerStyle], incl. the `wheel` -> menu fallback), the initial value
 * (first option's tag), and the String-tag value bridge end-to-end.
 *
 * The `@Composable` rendering of each style is exercised by running the app.
 */
class PickerTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `registry resolves Picker and it declares a String value type`() {
        assertSame(Picker, ActionUIRegistry.lookup("Picker"))
        assertEquals(ActionUIValueType.STRING, Picker.valueType)
    }

    @Test
    fun `simple string array auto-tags one-based`() {
        val sections = parsePickerOptions(
            buildJsonArray { add("One"); add("Two"); add("Three") },
            logger = null,
        )
        assertEquals(1, sections.size)
        assertNull(sections[0].title)
        assertEquals(
            listOf(PickerOption("One", "1"), PickerOption("Two", "2"), PickerOption("Three", "3")),
            sections[0].items,
        )
    }

    @Test
    fun `explicit title-tag dicts are honored`() {
        val sections = parsePickerOptions(
            buildJsonArray {
                addJsonObject { put("title", "Yes"); put("tag", "y") }
                addJsonObject { put("title", "No"); put("tag", "n") }
            },
            logger = null,
        )
        assertEquals(listOf(PickerOption("Yes", "y"), PickerOption("No", "n")), sections.flatMap { it.items })
    }

    @Test
    fun `section and divider entries split items into sections`() {
        val sections = parsePickerOptions(
            buildJsonArray {
                addJsonObject { put("section", "Group 1") }
                addJsonObject { put("title", "Alpha"); put("tag", "a") }
                addJsonObject { put("divider", true) }
                addJsonObject { put("title", "Beta"); put("tag", "b") }
            },
            logger = null,
        )
        assertEquals(2, sections.size)
        assertEquals("Group 1", sections[0].title)
        assertEquals(listOf(PickerOption("Alpha", "a")), sections[0].items)
        assertNull(sections[1].title)
        assertEquals(listOf(PickerOption("Beta", "b")), sections[1].items)
    }

    @Test
    fun `entries missing title or tag are skipped with a warning`() {
        val logger = CapturingLogger()
        val sections = parsePickerOptions(
            buildJsonArray {
                addJsonObject { put("title", "Good"); put("tag", "g") }
                addJsonObject { put("title", "NoTag") }
                addJsonObject { put("tag", "lonely") }
            },
            logger = logger,
        )
        assertEquals(listOf(PickerOption("Good", "g")), sections.flatMap { it.items })
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `non-array options warns and yields nothing`() {
        val logger = CapturingLogger()
        assertTrue(parsePickerOptions(JsonPrimitive("nope"), logger).isEmpty())
        assertTrue(logger.warnings.any { it.contains("must be an array") })
    }

    @Test
    fun `style resolves menu, segmented and radioGroup - wheel and unknown fall back to menu`() {
        val logger = CapturingLogger()
        assertEquals(PickerStyle.Menu, resolvePickerStyle(null, logger))
        assertEquals(PickerStyle.Menu, resolvePickerStyle("menu", logger))
        assertEquals(PickerStyle.Segmented, resolvePickerStyle("segmented", logger))
        assertEquals(PickerStyle.RadioGroup, resolvePickerStyle("radioGroup", logger))
        assertEquals(PickerStyle.Menu, resolvePickerStyle("wheel", logger))
        assertEquals(PickerStyle.Menu, resolvePickerStyle("spinner", logger))
        assertTrue(logger.warnings.any { it.contains("wheel") })
        assertTrue(logger.warnings.any { it.contains("spinner") })
    }

    @Test
    fun `initial value is the first option tag, or null without options`() {
        assertEquals("1", Picker.initialValue(pickerElement(buildJsonArray { add("A"); add("B") })))
        assertEquals(
            "a",
            Picker.initialValue(
                pickerElement(buildJsonArray { addJsonObject { put("title", "Alpha"); put("tag", "a") } })
            ),
        )
        assertNull(Picker.initialValue(ActionUIElement(id = 1, type = "Picker")))
    }

    @Test
    fun `host can read the seeded tag and set the selection from a string`() {
        ActionUIModel.loadDescription(
            pickerElement(buildJsonArray { add("A"); add("B"); add("C") }),
            windowUUID = "",
        )

        assertEquals("1", ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "3")
        assertEquals("3", ActionUIModel.getElementValue(viewID = 1))
        assertEquals("3", ActionUIModel.getElementValueAsString(viewID = 1))
    }

    private fun pickerElement(options: kotlinx.serialization.json.JsonArray): ActionUIElement =
        ActionUIElement(id = 1, type = "Picker", properties = buildJsonObject { put("options", options) })
}
