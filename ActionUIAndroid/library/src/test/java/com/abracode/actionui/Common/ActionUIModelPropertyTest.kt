package com.abracode.actionui.Common

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [ActionUIModel]'s property API - `get/setElementProperty`,
 * the runtime property-override surface ported from the Swift `ActionUIModel`
 * - and for the [ViewModel.mutationToken] contract the `animation` modifier
 * watches: the token increments on every property / state / value setter.
 *
 * The render-side half of the contract (overrides merged into the element at
 * the shared build entry point) is covered by `ViewModifierHelperTest`.
 */
class ActionUIModelPropertyTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private lateinit var logger: CapturingLogger

    @Before
    fun setUp() {
        logger = CapturingLogger()
        ActionUIModel.logger = logger

        val root = ActionUIElement(
            id = 100, type = "VStack",
            children = listOf(
                ActionUIElement(
                    id = 1, type = "Text",
                    properties = buildJsonObject {
                        put("title", "hello")
                        put("opacity", 0.5)
                        put("zIndex", 2)
                    }
                ),
                ActionUIElement(id = 2, type = "TextField", properties = buildJsonObject { put("text", "hi") }),
            )
        )
        ActionUIModel.loadDescription(root, windowUUID = "")
    }

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    private fun viewModel(id: Int): ViewModel = ActionUIModel.windowModels[""]!!.viewModels[id]!!

    // MARK: - getElementProperty

    @Test
    fun `getElementProperty returns authored values as plain Kotlin types`() {
        assertEquals("hello", ActionUIModel.getElementProperty(viewID = 1, propertyName = "title"))
        assertEquals(0.5, ActionUIModel.getElementProperty(viewID = 1, propertyName = "opacity"))
        // A whole JSON number reads as Long (no Int/Long distinction in JSON).
        assertEquals(2L, ActionUIModel.getElementProperty(viewID = 1, propertyName = "zIndex"))
    }

    @Test
    fun `getElementProperty warns and returns null for an absent property`() {
        assertNull(ActionUIModel.getElementProperty(viewID = 1, propertyName = "missing"))
        assertTrue(logger.warnings.any { it.contains("'missing' not found") })
    }

    @Test
    fun `getElementProperty warns and returns null for an unknown element`() {
        assertNull(ActionUIModel.getElementProperty(viewID = 99, propertyName = "title"))
        assertTrue(logger.warnings.any { it.contains("No ViewModel found") })
    }

    // MARK: - setElementProperty

    @Test
    fun `setElementProperty then getElementProperty round-trips the override`() {
        ActionUIModel.setElementProperty(viewID = 1, propertyName = "opacity", value = 0.25)
        assertEquals(0.25, ActionUIModel.getElementProperty(viewID = 1, propertyName = "opacity"))
    }

    @Test
    fun `setElementProperty can establish a property the JSON never declared`() {
        ActionUIModel.setElementProperty(viewID = 1, propertyName = "hidden", value = true)
        assertEquals(true, ActionUIModel.getElementProperty(viewID = 1, propertyName = "hidden"))
    }

    @Test
    fun `setElementProperty accepts nested lists and maps`() {
        ActionUIModel.setElementProperty(
            viewID = 1, propertyName = "offset",
            value = mapOf("x" to 8, "y" to -4.5)
        )
        val offset = ActionUIModel.getElementProperty(viewID = 1, propertyName = "offset")
        assertEquals(mapOf("x" to 8L, "y" to -4.5), offset)

        ActionUIModel.setElementProperty(viewID = 1, propertyName = "tags", value = listOf("a", "b"))
        assertEquals(listOf("a", "b"), ActionUIModel.getElementProperty(viewID = 1, propertyName = "tags"))
    }

    @Test
    fun `setElementProperty warns and writes nothing for an unrepresentable value`() {
        ActionUIModel.setElementProperty(viewID = 1, propertyName = "opacity", value = Any())
        assertTrue(logger.warnings.any { it.contains("Unsupported value type") })
        assertEquals(0.5, ActionUIModel.getElementProperty(viewID = 1, propertyName = "opacity"))
        assertTrue(viewModel(1).propertyOverrides.isEmpty())
    }

    @Test
    fun `setElementProperty is a warning no-op for an unknown element`() {
        ActionUIModel.setElementProperty(viewID = 99, propertyName = "opacity", value = 0.1)
        assertTrue(logger.warnings.any { it.contains("No ViewModel found") })
    }

    @Test
    fun `overrides land in the ViewModel and leave authored properties intact`() {
        ActionUIModel.setElementProperty(viewID = 1, propertyName = "opacity", value = 0.25)
        assertEquals(setOf("opacity"), viewModel(1).propertyOverrides.keys)
        // The authored layer still answers for non-overridden keys.
        assertEquals("hello", ActionUIModel.getElementProperty(viewID = 1, propertyName = "title"))
    }

    // MARK: - mutationToken (the animation modifier's default watch)

    @Test
    fun `mutationToken increments on property state and value setters`() {
        val viewModel = viewModel(2)
        assertEquals(0, viewModel.mutationToken)

        ActionUIModel.setElementValue(viewID = 2, value = "bye")
        assertEquals(1, viewModel.mutationToken)

        ActionUIModel.setElementState(viewID = 2, key = "flag", value = true)
        assertEquals(2, viewModel.mutationToken)

        ActionUIModel.setElementProperty(viewID = 2, propertyName = "opacity", value = 0.5)
        assertEquals(3, viewModel.mutationToken)
    }

    @Test
    fun `mutationToken does not increment on a failed property write`() {
        val viewModel = viewModel(1)
        ActionUIModel.setElementProperty(viewID = 1, propertyName = "x", value = Any())
        assertEquals(0, viewModel.mutationToken)
    }
}
