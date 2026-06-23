package com.abracode.actionui.Helpers

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for the pure half of the `transition` modifier
 * (`Helpers/TransitionHelper.kt`): mapping a `transition` declaration (shorthand
 * string / dict / array = combined) to an entrance [androidx.compose.animation.EnterTransition].
 * Compose enter transitions are opaque values, so these assert presence (a valid
 * declaration resolves; an invalid / pure-identity one does not). The
 * composition-bound half (the AnimatedVisibility wrapper, gated by
 * `wasDynamicallyInserted`) is exercised on the emulator via the demo.
 */
class TransitionHelperTest {

    @Test
    fun `opacity shorthand resolves to an entrance`() {
        assertNotNull(resolveEnterTransition(JsonPrimitive("opacity")))
    }

    @Test
    fun `all no-param shorthands except identity resolve`() {
        for (name in listOf("opacity", "slide", "scale")) {
            assertNotNull("shorthand '$name'", resolveEnterTransition(JsonPrimitive(name)))
        }
    }

    @Test
    fun `identity shorthand has no entrance`() {
        assertNull(resolveEnterTransition(JsonPrimitive("identity")))
    }

    @Test
    fun `invalid shorthand has no entrance`() {
        assertNull(resolveEnterTransition(JsonPrimitive("explode")))
    }

    @Test
    fun `null declaration has no entrance`() {
        assertNull(resolveEnterTransition(null))
    }

    @Test
    fun `move dict with edge resolves`() {
        val t = buildJsonObject { put("type", "move"); put("edge", "bottom") }
        assertNotNull(resolveEnterTransition(t))
    }

    @Test
    fun `scale dict with factor and anchor resolves`() {
        val t = buildJsonObject { put("type", "scale"); put("scale", 0.5); put("anchor", "topLeading") }
        assertNotNull(resolveEnterTransition(t))
    }

    @Test
    fun `offset dict resolves`() {
        val t = buildJsonObject { put("type", "offset"); put("x", 0.0); put("y", 20.0) }
        assertNotNull(resolveEnterTransition(t))
    }

    @Test
    fun `dict missing type has no entrance`() {
        assertNull(resolveEnterTransition(buildJsonObject { put("edge", "top") }))
    }

    @Test
    fun `dict invalid type has no entrance`() {
        assertNull(resolveEnterTransition(buildJsonObject { put("type", "warp") }))
    }

    @Test
    fun `asymmetric uses its insertion half`() {
        val t = buildJsonObject {
            put("type", "asymmetric")
            put("insertion", "opacity")
            putJsonObject("removal") { put("type", "move"); put("edge", "bottom") }
        }
        assertNotNull(resolveEnterTransition(t))
    }

    @Test
    fun `asymmetric with identity insertion has no entrance`() {
        val t = buildJsonObject {
            put("type", "asymmetric")
            put("insertion", "identity")
            put("removal", "opacity")
        }
        assertNull(resolveEnterTransition(t))
    }

    @Test
    fun `array combines its entries`() {
        val t = buildJsonArray {
            add("opacity")
            addJsonObject { put("type", "scale"); put("scale", 0.8) }
        }
        assertNotNull(resolveEnterTransition(t))
    }

    @Test
    fun `array with an identity entry still resolves the rest`() {
        val t = buildJsonArray { add("identity"); add("opacity") }
        assertNotNull(resolveEnterTransition(t))
    }

    @Test
    fun `array of only invalid entries has no entrance`() {
        val t = buildJsonArray { add("explode"); add("warp") }
        assertNull(resolveEnterTransition(t))
    }
}
