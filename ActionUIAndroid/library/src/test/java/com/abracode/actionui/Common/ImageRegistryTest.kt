package com.abracode.actionui.Common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for the pure parts of `ImageRegistry.kt`: the map-backed
 * [imageRegistryOf] and the [normalizeAssetDrawableName] transform shared (by
 * contract) with the `actionui-images.gradle` build step. The
 * [DiscoveringImageRegistry] needs Android [android.content.res.Resources] and
 * is exercised by the demo app, the stance the renderer takes for framework
 * code. Resolution through `selectImageSource` / `selectLabelIcon` is covered
 * in `ImageResolverTest` / `LabelIconResolverTest`.
 */
class ImageRegistryTest {

    // -----------------------------------------------------------------------
    // imageRegistryOf - the explicit map
    // -----------------------------------------------------------------------

    @Test
    fun `map registry resolves its entries and misses everything else`() {
        val registry = imageRegistryOf("My Logo" to 42, "AppIcon-Dark" to 7)
        assertEquals(42, registry.drawableFor("My Logo"))
        assertEquals(7, registry.drawableFor("AppIcon-Dark"))
        assertNull(registry.drawableFor("my logo"))      // keys are literal, not normalized
        assertNull(registry.drawableFor("Unmapped"))
    }

    @Test
    fun `registries compose - map first, fallback second (the documented pattern)`() {
        val map = imageRegistryOf("My Logo" to 42)
        val fallback = imageRegistryOf("Star Badge" to 7)
        val composed = ActionUIImageRegistry { name ->
            map.drawableFor(name) ?: fallback.drawableFor(name)
        }
        assertEquals(42, composed.drawableFor("My Logo"))
        assertEquals(7, composed.drawableFor("Star Badge"))
        assertNull(composed.drawableFor("Neither"))
    }

    // -----------------------------------------------------------------------
    // normalizeAssetDrawableName - the Apple-name -> resource-name transform
    // -----------------------------------------------------------------------

    @Test
    fun `normalization lowercases and replaces non-resource characters`() {
        assertEquals("my_logo", normalizeAssetDrawableName("My Logo"))
        assertEquals("my_image_foo", normalizeAssetDrawableName("my.image.foo"))
        assertEquals("appicon_dark", normalizeAssetDrawableName("AppIcon-Dark"))
        assertEquals("caf__menu", normalizeAssetDrawableName("Café Menu"))
    }

    @Test
    fun `already-legal resource names pass through unchanged`() {
        assertEquals("my_logo", normalizeAssetDrawableName("my_logo"))
        assertEquals("logo2", normalizeAssetDrawableName("logo2"))
    }

    @Test
    fun `normalization is lossy by design - distinct Apple names can collide`() {
        // Documented in ImageRegistry.kt: prefer the explicit map on collision.
        assertEquals(
            normalizeAssetDrawableName("My Logo"),
            normalizeAssetDrawableName("my-logo"),
        )
    }

    @Test
    fun `the discovery prefix is the keep-rule convention`() {
        // actionui_keep.xml keeps @drawable/aui_*; the prefix must stay in sync.
        assertEquals("aui_", AUI_DRAWABLE_PREFIX)
    }
}
