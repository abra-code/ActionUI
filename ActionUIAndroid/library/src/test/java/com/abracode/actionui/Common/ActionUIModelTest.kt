package com.abracode.actionui.Common

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ActionUIModel]'s action-dispatch surface. Mirrors the
 * intent of the Apple-side `ActionUIModel` action-handler tests: specific
 * handlers win over the default, the default catches unmatched ids, and
 * unregistering removes routing.
 *
 * [ActionUIModel] is a process-wide singleton, so each test cleans up the
 * handlers it registers (via the same public API a client would use) in
 * [tearDown] to keep tests independent.
 */
class ActionUIModelTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    /** Records the parameters of the most recent handler invocation. */
    private data class Invocation(
        val actionID: String,
        val windowUUID: String,
        val viewID: Int,
        val viewPartID: Int,
        val context: Any?
    )

    @After
    fun tearDown() {
        // Reset the singleton to a clean state for the next test.
        ActionUIModel.unregisterActionHandler("a")
        ActionUIModel.unregisterActionHandler("b")
        ActionUIModel.removeDefaultActionHandler()
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `registered handler receives all dispatch parameters`() {
        var captured: Invocation? = null
        ActionUIModel.registerActionHandler("a") { id, win, view, part, ctx ->
            captured = Invocation(id, win, view, part, ctx)
        }

        ActionUIModel.actionHandler("a", windowUUID = "w1", viewID = 7, viewPartID = 3, context = "payload")

        assertEquals(Invocation("a", "w1", 7, 3, "payload"), captured)
    }

    @Test
    fun `specific handler wins over default`() {
        var specificCalls = 0
        var defaultCalls = 0
        ActionUIModel.registerActionHandler("a") { _, _, _, _, _ -> specificCalls++ }
        ActionUIModel.setDefaultActionHandler { _, _, _, _, _ -> defaultCalls++ }

        ActionUIModel.actionHandler("a", viewID = 1)

        assertEquals(1, specificCalls)
        assertEquals(0, defaultCalls)
    }

    @Test
    fun `default handler catches unmatched actionID`() {
        var defaultId: String? = null
        ActionUIModel.setDefaultActionHandler { id, _, _, _, _ -> defaultId = id }

        ActionUIModel.actionHandler("unregistered", viewID = 1)

        assertEquals("unregistered", defaultId)
    }

    @Test
    fun `unregister removes routing so default takes over`() {
        var specificCalls = 0
        var defaultCalls = 0
        ActionUIModel.registerActionHandler("a") { _, _, _, _, _ -> specificCalls++ }
        ActionUIModel.setDefaultActionHandler { _, _, _, _, _ -> defaultCalls++ }

        ActionUIModel.unregisterActionHandler("a")
        ActionUIModel.actionHandler("a", viewID = 1)

        assertEquals(0, specificCalls)
        assertEquals(1, defaultCalls)
    }

    @Test
    fun `no handler and no default warns`() {
        val logger = CapturingLogger()
        ActionUIModel.logger = logger

        ActionUIModel.actionHandler("ghost", viewID = 1)

        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.first().contains("ghost"))
    }

    @Test
    fun `registering same actionID twice replaces the handler`() {
        var firstCalls = 0
        var secondCalls = 0
        ActionUIModel.registerActionHandler("a") { _, _, _, _, _ -> firstCalls++ }
        ActionUIModel.registerActionHandler("a") { _, _, _, _, _ -> secondCalls++ }

        ActionUIModel.actionHandler("a", viewID = 1)

        assertEquals(0, firstCalls)
        assertEquals(1, secondCalls)
    }

    @Test
    fun `context defaults to null when omitted`() {
        var captured: Any? = "sentinel"
        ActionUIModel.registerActionHandler("a") { _, _, _, _, ctx -> captured = ctx }

        ActionUIModel.actionHandler("a", viewID = 1)

        assertNull(captured)
    }
}
