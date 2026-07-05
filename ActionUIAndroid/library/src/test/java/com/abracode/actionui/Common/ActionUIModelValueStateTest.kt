package com.abracode.actionui.Common

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [ActionUIModel]'s value / state bridge - the host-side
 * `get/setElementValue[FromString]` and `get/setElementState[FromString]`
 * surface ported from the Swift `ActionUIModel`. A window is registered via
 * [ActionUIModel.loadDescription]; the tests then read and write element values
 * out-of-band exactly as host code would from an action handler.
 *
 * The numeric / boolean value-type paths are exercised through tiny fake
 * registered builders ([FakeValueBuilder]), since the only real value-bearing
 * controls today are the String-typed text fields.
 */
class ActionUIModelValueStateTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        val errors = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            when (level) {
                LoggerLevel.warning -> warnings.add(message)
                LoggerLevel.error -> errors.add(message)
                else -> {}
            }
        }
    }

    /** Minimal builder declaring a [valueType]; never actually composed in unit tests. */
    private class FakeValueBuilder(override val valueType: ActionUIValueType) : ActionUIViewConstruction {
        @Composable
        override fun BuildView(element: ActionUIElement, modifier: Modifier) { /* not rendered */ }
    }

    private lateinit var logger: CapturingLogger

    @Before
    fun setUp() {
        logger = CapturingLogger()
        ActionUIModel.logger = logger

        ActionUIRegistry.register("FakeBoolean", FakeValueBuilder(ActionUIValueType.BOOLEAN))
        ActionUIRegistry.register("FakeInt", FakeValueBuilder(ActionUIValueType.INT))
        ActionUIRegistry.register("FakeDouble", FakeValueBuilder(ActionUIValueType.DOUBLE))
        // A valueless (NONE) stand-in for the "warns on a valueless element"
        // test. `Text` used to fill that role, but it is now STRING-valued
        // (value-bridge parity with SwiftUI), so it cannot.
        ActionUIRegistry.register("FakeNone", FakeValueBuilder(ActionUIValueType.NONE))

        val root = ActionUIElement(
            id = 100, type = "VStack",
            children = listOf(
                ActionUIElement(id = 1, type = "TextField", properties = buildJsonObject { put("text", "hi") }),
                ActionUIElement(id = 2, type = "FakeBoolean"),
                ActionUIElement(id = 3, type = "FakeInt"),
                ActionUIElement(id = 4, type = "FakeDouble"),
                ActionUIElement(id = 5, type = "FakeNone"),
                ActionUIElement(id = 6, type = "DatePicker", properties = buildJsonObject { put("selectedDate", "2024-07-16") }),
                ActionUIElement(id = 7, type = "ColorPicker", properties = buildJsonObject { put("selectedColor", "#FF8800") }),
                ActionUIElement(id = 8, type = "List"),
            )
        )
        ActionUIModel.loadDescription(root, windowUUID = "")
    }

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    // MARK: - Value API

    @Test
    fun `getElementValue returns the seeded initial value`() {
        assertEquals("hi", ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `setElementValue then getElementValue round-trips`() {
        ActionUIModel.setElementValue(viewID = 1, value = "bye")
        assertEquals("bye", ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `getElementValueAsString returns the string for a string control`() {
        assertEquals("hi", ActionUIModel.getElementValueAsString(viewID = 1))
    }

    @Test
    fun `setElementValueFromString parses boolean int and double by declared type`() {
        ActionUIModel.setElementValueFromString(viewID = 2, value = "true")
        ActionUIModel.setElementValueFromString(viewID = 3, value = "42")
        ActionUIModel.setElementValueFromString(viewID = 4, value = "3.5")

        assertEquals(true, ActionUIModel.getElementValue(viewID = 2))
        assertEquals(42, ActionUIModel.getElementValue(viewID = 3))
        assertEquals(3.5, ActionUIModel.getElementValue(viewID = 4))
        assertEquals("true", ActionUIModel.getElementValueAsString(viewID = 2))
        assertEquals("42", ActionUIModel.getElementValueAsString(viewID = 3))
    }

    @Test
    fun `setElementValueFromString warns and skips on a malformed number`() {
        ActionUIModel.setElementValueFromString(viewID = 3, value = "not-a-number")
        assertNull(ActionUIModel.getElementValue(viewID = 3))
        assertTrue(logger.warnings.any { it.contains("Int") })
    }

    @Test
    fun `setElementValueFromString warns on a valueless element`() {
        ActionUIModel.setElementValueFromString(viewID = 5, value = "x") // FakeNone => NONE
        assertNull(ActionUIModel.getElementValue(viewID = 5))
        assertTrue(logger.warnings.any { it.contains("no value") })
    }

    @Test
    fun `value API on an unknown view warns and returns null`() {
        assertNull(ActionUIModel.getElementValue(viewID = 999))
        assertTrue(logger.warnings.any { it.contains("999") })
    }

    // MARK: - Value API (B6 value-bridge types)

    @Test
    fun `DATE value seeds from selectedDate and serializes ISO`() {
        assertEquals(LocalDate.of(2024, 7, 16), ActionUIModel.getElementValue(viewID = 6))
        assertEquals("2024-07-16", ActionUIModel.getElementValueAsString(viewID = 6))
    }

    @Test
    fun `setElementValueFromString parses an ISO date`() {
        ActionUIModel.setElementValueFromString(viewID = 6, value = "2025-01-02")
        assertEquals(LocalDate.of(2025, 1, 2), ActionUIModel.getElementValue(viewID = 6))
        assertEquals("2025-01-02", ActionUIModel.getElementValueAsString(viewID = 6))
    }

    @Test
    fun `setElementValueFromString warns and skips on a malformed date`() {
        ActionUIModel.setElementValueFromString(viewID = 6, value = "not-a-date")
        assertEquals(LocalDate.of(2024, 7, 16), ActionUIModel.getElementValue(viewID = 6)) // unchanged
        assertTrue(logger.warnings.any { it.contains("date") })
    }

    @Test
    fun `COLOR value seeds from selectedColor and serializes hex`() {
        assertEquals("#FF8800", ActionUIModel.getElementValueAsString(viewID = 7))
    }

    @Test
    fun `setElementValueFromString parses hex and named colors and serializes back`() {
        ActionUIModel.setElementValueFromString(viewID = 7, value = "#00FF00")
        assertEquals("#00FF00", ActionUIModel.getElementValueAsString(viewID = 7))
        ActionUIModel.setElementValueFromString(viewID = 7, value = "red")
        assertEquals("#FF0000", ActionUIModel.getElementValueAsString(viewID = 7))
    }

    @Test
    fun `setElementValueFromString warns and skips on a malformed color`() {
        ActionUIModel.setElementValueFromString(viewID = 7, value = "notacolor")
        assertEquals("#FF8800", ActionUIModel.getElementValueAsString(viewID = 7)) // unchanged
        assertTrue(logger.warnings.any { it.contains("color") })
    }

    @Test
    fun `STRING_LIST seeds empty and round-trips tab-separated`() {
        assertEquals(emptyList<String>(), ActionUIModel.getElementValue(viewID = 8))
        ActionUIModel.setElementValueFromString(viewID = 8, value = "a\tb\tc")
        assertEquals(listOf("a", "b", "c"), ActionUIModel.getElementValue(viewID = 8))
        assertEquals("a\tb\tc", ActionUIModel.getElementValueAsString(viewID = 8))
    }

    @Test
    fun `STRING_LIST drops empty fields like Apple's split`() {
        ActionUIModel.setElementValueFromString(viewID = 8, value = "")
        assertEquals(emptyList<String>(), ActionUIModel.getElementValue(viewID = 8))
    }

    // MARK: - State API

    @Test
    fun `setElementState then getElementState round-trips`() {
        ActionUIModel.setElementState(viewID = 1, key = "k", value = 5)
        assertEquals(5, ActionUIModel.getElementState(viewID = 1, key = "k"))
        assertEquals("5", ActionUIModel.getElementStateAsString(viewID = 1, key = "k"))
    }

    @Test
    fun `setElementState rejects a type change for an existing key`() {
        ActionUIModel.setElementState(viewID = 1, key = "k", value = 5)
        ActionUIModel.setElementState(viewID = 1, key = "k", value = "five")
        assertEquals(5, ActionUIModel.getElementState(viewID = 1, key = "k"))
        assertTrue(logger.errors.any { it.contains("Type mismatch") })
    }

    @Test
    fun `setElementStateFromString stores a new key as a plain string`() {
        ActionUIModel.setElementStateFromString(viewID = 1, key = "s", value = "hello")
        assertEquals("hello", ActionUIModel.getElementState(viewID = 1, key = "s"))
    }

    @Test
    fun `setElementStateFromString parses into an existing key's type`() {
        ActionUIModel.setElementState(viewID = 1, key = "n", value = 1)
        ActionUIModel.setElementStateFromString(viewID = 1, key = "n", value = "10")
        assertEquals(10, ActionUIModel.getElementState(viewID = 1, key = "n"))
    }

    @Test
    fun `setElementStateFromString warns on a malformed value for an existing typed key`() {
        ActionUIModel.setElementState(viewID = 1, key = "b", value = true)
        ActionUIModel.setElementStateFromString(viewID = 1, key = "b", value = "nope")
        assertEquals(true, ActionUIModel.getElementState(viewID = 1, key = "b"))
        assertTrue(logger.warnings.any { it.contains("Boolean") })
    }

    @Test
    fun `getElementState warns and returns null for a missing key`() {
        assertNull(ActionUIModel.getElementState(viewID = 1, key = "ghost"))
        assertTrue(logger.warnings.any { it.contains("ghost") })
    }

    @Test
    fun `setElementState allows differing List implementations for the same key`() {
        // The NavigationStack.navigationPath pattern: seed with an empty list
        // (EmptyList), then push with a singleton (SingletonList). Both are List,
        // so the write must be accepted (concrete ::class differs, logical type does not).
        ActionUIModel.setElementState(viewID = 1, key = "navigationPath", value = emptyList<Int>())
        ActionUIModel.setElementState(viewID = 1, key = "navigationPath", value = listOf(50))
        assertEquals(listOf(50), ActionUIModel.getElementState(viewID = 1, key = "navigationPath"))
        assertTrue(logger.errors.none { it.contains("Type mismatch") })

        // A larger list (ArrayList) is likewise accepted.
        ActionUIModel.setElementState(viewID = 1, key = "navigationPath", value = listOf(50, 51))
        assertEquals(listOf(50, 51), ActionUIModel.getElementState(viewID = 1, key = "navigationPath"))
        assertTrue(logger.errors.none { it.contains("Type mismatch") })
    }

    @Test
    fun `setElementState still rejects switching between a List and a scalar`() {
        ActionUIModel.setElementState(viewID = 1, key = "p", value = listOf(1))
        ActionUIModel.setElementState(viewID = 1, key = "p", value = 7) // scalar into a list key
        assertEquals(listOf(1), ActionUIModel.getElementState(viewID = 1, key = "p"))
        assertTrue(logger.errors.any { it.contains("Type mismatch") })
    }
}
