package com.abracode.actionui.Views

import androidx.compose.ui.graphics.Color
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ColorPicker] - registry resolution, the COLOR value seed, and
 * the preset swatch palette. The `@Composable` swatch grid and the free-form HSV
 * dialog are exercised by the app; the dialog's HSV<->Color math is unit-tested in
 * `Helpers/ColorHelperTest.kt`.
 */
class ColorPickerTest {

    @Test
    fun `ColorPicker resolves and is COLOR-valued`() {
        assertSame(ColorPicker, ActionUIRegistry.lookup("ColorPicker"))
        assertEquals(ActionUIValueType.COLOR, ColorPicker.valueType)
    }

    @Test
    fun `initialValue parses selectedColor`() {
        val hex = ActionUIElement(id = 1, type = "ColorPicker", properties = buildJsonObject { put("selectedColor", "#FF0000") })
        assertEquals(Color.Red, ColorPicker.initialValue(hex))
        val named = ActionUIElement(id = 1, type = "ColorPicker", properties = buildJsonObject { put("selectedColor", "blue") })
        assertEquals(Color.Blue, ColorPicker.initialValue(named))
    }

    @Test
    fun `initialValue defaults to transparent when selectedColor is absent or invalid`() {
        assertEquals(Color.Transparent, ColorPicker.initialValue(ActionUIElement(id = 1, type = "ColorPicker")))
        val bad = ActionUIElement(id = 1, type = "ColorPicker", properties = buildJsonObject { put("selectedColor", "notacolor") })
        assertEquals(Color.Transparent, ColorPicker.initialValue(bad))
    }

    @Test
    fun `every preset swatch name resolves to a color`() {
        // 15 named presets, all of which parseColor must understand (no silent gaps).
        assertEquals(15, ColorPickerSwatches.size)
        assertTrue(ColorPickerSwatches.contains(Color.Red))
        assertTrue(ColorPickerSwatches.contains(Color.Black))
        assertTrue(ColorPickerSwatches.contains(Color.White))
    }
}
