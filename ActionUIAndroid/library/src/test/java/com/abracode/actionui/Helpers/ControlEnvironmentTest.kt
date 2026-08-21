package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the control-environment parsing in `ControlEnvironment.kt`:
 * the `buttonStyle` / `controlSize` vocabularies (mirroring the `View.swift`
 * validators) and the `disabled` flag. The CompositionLocal propagation itself
 * is Compose runtime plumbing, exercised by running the app - the stance the
 * rest of the renderer takes for `@Composable` code.
 */
class ControlEnvironmentTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    // ---- parseButtonStyle ----

    @Test
    fun `parseButtonStyle resolves the full SwiftUI vocabulary`() {
        val logger = CapturingLogger()
        assertEquals(ActionUIButtonStyle.AUTOMATIC, parseButtonStyle("automatic", logger))
        assertEquals(ActionUIButtonStyle.PLAIN, parseButtonStyle("plain", logger))
        assertEquals(ActionUIButtonStyle.BORDERLESS, parseButtonStyle("borderless", logger))
        assertEquals(ActionUIButtonStyle.BORDERED, parseButtonStyle("bordered", logger))
        assertEquals(ActionUIButtonStyle.BORDERED_PROMINENT, parseButtonStyle("borderedProminent", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseButtonStyle warns and skips an unknown style`() {
        val logger = CapturingLogger()
        assertNull(parseButtonStyle("fancy", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("buttonStyle 'fancy'"))
    }

    // ---- parseControlSize ----

    @Test
    fun `parseControlSize resolves the full SwiftUI vocabulary`() {
        val logger = CapturingLogger()
        assertEquals(ActionUIControlSize.MINI, parseControlSize("mini", logger))
        assertEquals(ActionUIControlSize.SMALL, parseControlSize("small", logger))
        assertEquals(ActionUIControlSize.REGULAR, parseControlSize("regular", logger))
        assertEquals(ActionUIControlSize.LARGE, parseControlSize("large", logger))
        assertEquals(ActionUIControlSize.EXTRA_LARGE, parseControlSize("extraLarge", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseControlSize warns and skips an unknown size`() {
        val logger = CapturingLogger()
        assertNull(parseControlSize("huge", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("controlSize 'huge'"))
    }

    // ---- resolveDisabled ----

    @Test
    fun `resolveDisabled is false when the property is absent`() {
        val logger = CapturingLogger()
        assertFalse(resolveDisabled(buildJsonObject { put("title", "x") }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveDisabled reads a Boolean`() {
        val logger = CapturingLogger()
        assertTrue(resolveDisabled(buildJsonObject { put("disabled", true) }, logger))
        assertFalse(resolveDisabled(buildJsonObject { put("disabled", false) }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveDisabled warns and ignores a non-Boolean value`() {
        val logger = CapturingLogger()
        assertFalse(resolveDisabled(buildJsonObject { put("disabled", 1) }, logger))
        assertFalse(resolveDisabled(buildJsonObject { putJsonObject("disabled") {} }, logger))
        assertEquals(2, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("disabled") })
    }

    // ---- resolveLabelsHidden ----

    @Test
    fun `resolveLabelsHidden is false when the property is absent`() {
        val logger = CapturingLogger()
        assertFalse(resolveLabelsHidden(buildJsonObject { put("title", "x") }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveLabelsHidden reads a Boolean`() {
        val logger = CapturingLogger()
        assertTrue(resolveLabelsHidden(buildJsonObject { put("labelsHidden", true) }, logger))
        assertFalse(resolveLabelsHidden(buildJsonObject { put("labelsHidden", false) }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveLabelsHidden warns and ignores a non-Boolean value`() {
        val logger = CapturingLogger()
        assertFalse(resolveLabelsHidden(buildJsonObject { put("labelsHidden", "yes") }, logger))
        assertFalse(resolveLabelsHidden(buildJsonObject { putJsonObject("labelsHidden") {} }, logger))
        assertEquals(2, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("labelsHidden") })
    }

    // ---- disabledLocalOverride: runtime-reactive `disabled`, both directions + narrowing (#33) ----
    //
    // These test the decision ProvideReactiveEnvironment makes on the host-merged EFFECTIVE element
    // (authored properties + setElementProperty overrides, merged by ViewModifierHelper.mergeProperties).
    // `null` means "provide nothing" -> the subtree inherits the ancestor value (SwiftUI AND-down);
    // `false` means "narrow this subtree to disabled". The end-to-end control behaviour (a re-enabled
    // Button fires; a disabled ancestor keeps a child disabled) is exercised on-device by
    // demoApp/assets/View.disabledReactive.json - the codebase convention for CompositionLocal wiring.

    @Test
    fun `disabledLocalOverride narrows only when disabled, else inherits`() {
        // disabled:true -> provide false (narrow to disabled).
        assertEquals(false, disabledLocalOverride(buildJsonObject { put("disabled", true) }))
        // disabled:false / absent -> null (inherit), so an element cannot re-enable itself past a
        // disabled ancestor - SwiftUI's AND-down is preserved.
        assertNull(disabledLocalOverride(buildJsonObject { put("disabled", false) }))
        assertNull(disabledLocalOverride(buildJsonObject { put("title", "x") }))
        assertNull(disabledLocalOverride(null))
    }

    @Test
    fun `runtime disabled override re-enables an authored-disabled element and re-disables it`() {
        val authored = buildJsonObject { put("title", "Save"); put("disabled", true) }
        // Authored disabled:true -> narrows to disabled (Save cannot fire).
        assertEquals(false, disabledLocalOverride(authored))
        // setElementProperty(disabled,false) merges over the authored value; the effective element
        // now provides NOTHING, so the control inherits the enabled ancestor value (re-enabled ->
        // it fires). This is the Apple/web behaviour the old provider - which read the parent's
        // static child.properties and only narrowed - could never reach.
        val enabled = mergeProperties(authored, mapOf("disabled" to JsonPrimitive(false)))
        assertNull(disabledLocalOverride(enabled))
        // setElementProperty(disabled,true) again re-narrows to disabled (both directions reactive).
        val reDisabled = mergeProperties(authored, mapOf("disabled" to JsonPrimitive(true)))
        assertEquals(false, disabledLocalOverride(reDisabled))
    }

    @Test
    fun `runtime disabled override can disable an element the JSON never declared`() {
        val effective = mergeProperties(
            buildJsonObject { put("title", "x") },
            mapOf("disabled" to JsonPrimitive(true)),
        )
        assertEquals(false, disabledLocalOverride(effective))
    }

    // ---- hidden also disables: the CONTROL half of "a hidden element is inert" ----
    //
    // `hidden` narrows BOTH locals. The input one (below) stands the scroll containers down;
    // this one stands every CONTROL down, over the road `disabled` already travels to each
    // clickable in the library. It replaced blocking input in `hiddenSubtree` by consuming
    // pointer events, which also consumed them for whatever was BEHIND the hidden element -
    // the very bug that was written to fix. See ModifierResolver.hiddenSubtree.

    @Test
    fun `hidden narrows the enabled local, so a hidden control cannot fire`() {
        assertEquals(false, disabledLocalOverride(buildJsonObject { put("hidden", true) }))
        // With a title and no `disabled` of its own - the shape of SharedCare's hidden
        // "Clear filters" Button, which sat over the live feed and used to eat its taps.
        assertEquals(
            false,
            disabledLocalOverride(buildJsonObject { put("title", "Clear filters"); put("hidden", true) }),
        )
    }

    @Test
    fun `hidden false does not re-enable a disabled element`() {
        // Both flags are narrowing, so neither can undo the other: still disabled.
        assertEquals(
            false,
            disabledLocalOverride(buildJsonObject { put("disabled", true); put("hidden", false) }),
        )
        // And a visible element with neither flag still inherits.
        assertNull(disabledLocalOverride(buildJsonObject { put("hidden", false) }))
    }

    @Test
    fun `a runtime unhide re-enables the control it hid`() {
        val authored = buildJsonObject { put("title", "Show earlier"); put("hidden", true) }
        assertEquals(false, disabledLocalOverride(authored))
        // setElementProperty(hidden,false) is how the host reveals it; the control has to
        // come back with it, or revealing a button would leave a dead one on screen.
        val shown = mergeProperties(authored, mapOf("hidden" to JsonPrimitive(false)))
        assertNull(disabledLocalOverride(shown))
    }

    // ---- inputEnabledLocalOverride: a hidden subtree is non-interactive (#34) ----

    @Test
    fun `inputEnabledLocalOverride narrows only when hidden, else inherits`() {
        assertEquals(false, inputEnabledLocalOverride(buildJsonObject { put("hidden", true) }))
        assertNull(inputEnabledLocalOverride(buildJsonObject { put("hidden", false) }))
        assertNull(inputEnabledLocalOverride(buildJsonObject { put("title", "x") }))
        assertNull(inputEnabledLocalOverride(null))
    }

    @Test
    fun `hidden input gating reacts to a runtime hidden override in both directions`() {
        val authored = buildJsonObject { put("hidden", true) }
        assertEquals(false, inputEnabledLocalOverride(authored))
        // setElementProperty(hidden,false) -> shown again -> input restored (inherit).
        val shown = mergeProperties(authored, mapOf("hidden" to JsonPrimitive(false)))
        assertNull(inputEnabledLocalOverride(shown))
    }
}
