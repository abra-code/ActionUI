package com.abracode.actionui.Helpers

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for the pure `LoadableView` source helpers: [resolveLoadableSource]
 * (value vs `url`/`filePath`/`name` priority) and [classifyLoadableSource] (Apple's
 * remote / file / bundle heuristics + format-by-extension). No Compose, no IO.
 */
class LoadableSourceTest {

    // --- resolveLoadableSource ------------------------------------------------

    @Test
    fun `runtime value wins over properties when non-blank`() {
        val props = buildJsonObject { put("name", "Bundle.json") }
        assertEquals("runtime.json", resolveLoadableSource("runtime.json", props))
    }

    @Test
    fun `blank runtime value falls back to properties`() {
        val props = buildJsonObject { put("name", "Bundle.json") }
        assertEquals("Bundle.json", resolveLoadableSource("   ", props))
    }

    @Test
    fun `properties priority is url then filePath then name`() {
        val all = buildJsonObject {
            put("url", "https://x/y.json")
            put("filePath", "/tmp/y.json")
            put("name", "Y.json")
        }
        assertEquals("https://x/y.json", resolveLoadableSource(null, all))

        val fileAndName = buildJsonObject {
            put("filePath", "/tmp/y.json")
            put("name", "Y.json")
        }
        assertEquals("/tmp/y.json", resolveLoadableSource(null, fileAndName))

        val nameOnly = buildJsonObject { put("name", "Y.json") }
        assertEquals("Y.json", resolveLoadableSource(null, nameOnly))
    }

    @Test
    fun `no value and no source properties yields null`() {
        assertNull(resolveLoadableSource(null, null))
        assertNull(resolveLoadableSource("", buildJsonObject { put("other", "z") }))
    }

    // --- classifyLoadableSource ----------------------------------------------

    @Test
    fun `http and https classify as remote`() {
        assertEquals(
            LoadableSource.Remote("https://h/v.json", LoadableFormat.JSON),
            classifyLoadableSource("https://h/v.json"),
        )
        assertEquals(
            LoadableSource.Remote("http://h/v.json", LoadableFormat.JSON),
            classifyLoadableSource("http://h/v.json"),
        )
    }

    @Test
    fun `file scheme is stripped to a file path`() {
        assertEquals(
            LoadableSource.FilePath("/tmp/v.json", LoadableFormat.JSON),
            classifyLoadableSource("file:///tmp/v.json"),
        )
    }

    @Test
    fun `a path containing a slash is a file path`() {
        assertEquals(
            LoadableSource.FilePath("/data/local/v.json", LoadableFormat.JSON),
            classifyLoadableSource("/data/local/v.json"),
        )
    }

    @Test
    fun `a bare name with no slash is a bundle resource`() {
        assertEquals(
            LoadableSource.BundleName("Hello.json", LoadableFormat.JSON),
            classifyLoadableSource("Hello.json"),
        )
        // No extension is still a bundle name (the reader appends .json).
        assertEquals(
            LoadableSource.BundleName("Hello", LoadableFormat.JSON),
            classifyLoadableSource("Hello"),
        )
    }

    @Test
    fun `plist extension selects the PLIST format`() {
        assertEquals(
            LoadableSource.BundleName("Hello.plist", LoadableFormat.PLIST),
            classifyLoadableSource("Hello.plist"),
        )
        assertEquals(
            LoadableSource.FilePath("/tmp/v.plist", LoadableFormat.PLIST),
            classifyLoadableSource("/tmp/v.plist"),
        )
    }

    @Test
    fun `blank or null source is None`() {
        assertEquals(LoadableSource.None, classifyLoadableSource(null))
        assertEquals(LoadableSource.None, classifyLoadableSource("   "))
    }

    @Test
    fun `surrounding whitespace is trimmed before classifying`() {
        assertEquals(
            LoadableSource.BundleName("Hello.json", LoadableFormat.JSON),
            classifyLoadableSource("  Hello.json  "),
        )
    }
}
