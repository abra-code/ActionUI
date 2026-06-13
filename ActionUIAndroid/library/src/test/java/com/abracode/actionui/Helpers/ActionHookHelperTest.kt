package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.OpenURLObserver
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the lifecycle action hooks (`ActionHookHelper.kt` and the
 * `ActionUIModel.onOpenURL` delivery): the actionID property validation
 * (`View.swift` parity) and the openURL observer registry / dispatch. The
 * `DisposableEffect` choreography itself is Compose runtime plumbing,
 * exercised on the emulator - the stance the rest of the renderer takes for
 * `@Composable` code.
 */
class ActionHookHelperTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    /** Records the parameters of a handler invocation. */
    private data class Invocation(
        val actionID: String,
        val windowUUID: String,
        val viewID: Int,
        val viewPartID: Int,
        val context: Any?,
    )

    @After
    fun tearDown() {
        // Reset the singleton for the next test (same public-API cleanup the
        // other ActionUIModel suites use).
        ActionUIModel.unregisterActionHandler("hook.url")
        ActionUIModel.unregisterActionHandler("hook.url.b")
        ActionUIModel.removeDefaultActionHandler()
    }

    // ---- resolveActionHookID ----

    @Test
    fun `resolveActionHookID is null when the property is absent`() {
        val logger = CapturingLogger()
        assertNull(resolveActionHookID(buildJsonObject { put("title", "x") }, "onAppearActionID", logger))
        assertNull(resolveActionHookID(null, "onAppearActionID", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveActionHookID reads a String`() {
        val logger = CapturingLogger()
        val props = buildJsonObject { put("onAppearActionID", "view.appeared") }
        assertEquals("view.appeared", resolveActionHookID(props, "onAppearActionID", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveActionHookID warns and ignores a non-String value`() {
        val logger = CapturingLogger()
        assertNull(resolveActionHookID(buildJsonObject { put("openURLActionID", 5) }, "openURLActionID", logger))
        assertNull(resolveActionHookID(buildJsonObject { put("openURLActionID", true) }, "openURLActionID", logger))
        assertNull(resolveActionHookID(buildJsonObject { putJsonObject("openURLActionID") {} }, "openURLActionID", logger))
        assertEquals(3, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("openURLActionID") && it.contains("expected String") })
    }

    // ---- onOpenURL delivery ----

    @Test
    fun `onOpenURL fires each registered observer with the URL as context`() {
        val received = mutableListOf<Invocation>()
        ActionUIModel.registerActionHandler("hook.url") { id, win, view, part, ctx ->
            received.add(Invocation(id, win, view, part, ctx))
        }
        val observerA = OpenURLObserver("hook.url", "", 11)
        val observerB = OpenURLObserver("hook.url", "w2", 12)
        ActionUIModel.registerOpenURLObserver(observerA)
        ActionUIModel.registerOpenURLObserver(observerB)
        try {
            ActionUIModel.onOpenURL("myapp://path?x=1")
        } finally {
            ActionUIModel.unregisterOpenURLObserver(observerA)
            ActionUIModel.unregisterOpenURLObserver(observerB)
        }

        assertEquals(
            listOf(
                Invocation("hook.url", "", 11, 0, "myapp://path?x=1"),
                Invocation("hook.url", "w2", 12, 0, "myapp://path?x=1"),
            ),
            received,
        )
    }

    @Test
    fun `onOpenURL after unregister does not fire`() {
        var calls = 0
        ActionUIModel.registerActionHandler("hook.url") { _, _, _, _, _ -> calls++ }
        val observer = OpenURLObserver("hook.url", "", 11)
        ActionUIModel.registerOpenURLObserver(observer)
        ActionUIModel.unregisterOpenURLObserver(observer)

        ActionUIModel.onOpenURL("myapp://path")

        assertEquals(0, calls)
    }

    @Test
    fun `onOpenURL with no observers is a no-op`() {
        var defaultCalls = 0
        ActionUIModel.setDefaultActionHandler { _, _, _, _, _ -> defaultCalls++ }

        ActionUIModel.onOpenURL("myapp://nobody-listens")

        assertEquals(0, defaultCalls)
    }

    @Test
    fun `an observer unregistering inside its handler does not break delivery`() {
        // Mirrors a handler whose action recomposes the UI away (e.g. dismisses
        // a modal carrying the hook): the dispatch snapshot must not skip or
        // crash on concurrent registry mutation.
        val fired = mutableListOf<String>()
        val observerA = OpenURLObserver("hook.url", "", 1)
        val observerB = OpenURLObserver("hook.url.b", "", 2)
        ActionUIModel.registerActionHandler("hook.url") { _, _, _, _, _ ->
            fired.add("a")
            ActionUIModel.unregisterOpenURLObserver(observerB)
        }
        ActionUIModel.registerActionHandler("hook.url.b") { _, _, _, _, _ -> fired.add("b") }
        ActionUIModel.registerOpenURLObserver(observerA)
        ActionUIModel.registerOpenURLObserver(observerB)
        try {
            ActionUIModel.onOpenURL("myapp://path")
        } finally {
            ActionUIModel.unregisterOpenURLObserver(observerA)
            ActionUIModel.unregisterOpenURLObserver(observerB)
        }

        // The snapshot taken at dispatch still delivers to B (it was composed
        // when the URL arrived), matching the list-copy contract.
        assertEquals(listOf("a", "b"), fired)
    }
}
