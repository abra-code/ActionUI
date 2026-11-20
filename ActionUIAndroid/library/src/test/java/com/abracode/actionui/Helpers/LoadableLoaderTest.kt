package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ConsoleLogger
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import java.io.File
import java.nio.file.Files
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Unit tests for the source-loading helpers shared by the embedded `LoadableView`
 * element and the top-level `ActionUI.RenderSource` entry. Covers the parts that
 * need no Android framework: decoding and the remote `.plist` short-circuit.
 * (The local bundle/file reads go through `AssetManager` / the filesystem and are
 * exercised by the demo app's `LoadableView.json` and the build's JSON verifier.)
 */
class LoadableLoaderTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val logger = ConsoleLogger()

    @Test
    fun `decodeDescription returns Loaded for a valid JSON description`() {
        val result = decodeDescription("""{"type":"VStack","id":7}""", json, logger)
        assertTrue("expected Loaded, got $result", result is DescriptionLoad.Loaded)
        val element = (result as DescriptionLoad.Loaded).element
        assertEquals("VStack", element.type)
        assertEquals(7, element.id)
    }

    @Test
    fun `decodeDescription returns Failed for malformed JSON`() {
        val result = decodeDescription("not json {", json, logger)
        assertTrue("expected Failed, got $result", result is DescriptionLoad.Failed)
    }

    @Test
    fun `decodeDescription refuses text nested deeper than 512 levels instead of overflowing the stack`() {
        // Before the limit, 10000 levels threw StackOverflowError out of the parser or the filter.
        for (text in listOf(
            "[".repeat(100_000) + "]".repeat(100_000),
            """{"type":"VStack","content":""".repeat(10_000) + """{"type":"Text"}""" + "}".repeat(10_000),
        )) {
            assertEquals(DescriptionLoad.Failed("Nested deeper than 512 levels"), decodeDescription(text, json, logger))
        }
        // 512 levels decode, and brackets inside strings do not count.
        val deepest = """{"type":"VStack","content":""".repeat(510) + """{"type":"Text","properties":{"text":"[[{{\"["}}""" + "}".repeat(510)
        assertTrue(decodeDescription(deepest, json, logger) is DescriptionLoad.Loaded)
    }

    @Test
    fun `the nesting rule refuses a repeat and a deep chain`() {
        assertNull(loadableNestingRefusal("b", listOf("a")))
        assertEquals("it includes itself", loadableNestingRefusal("a", listOf("a", "b")))
        val deep = (0 until 16).map { "doc$it" }
        assertEquals("LoadableViews are nested more than 16 deep", loadableNestingRefusal("next", deep))
        assertNull(loadableNestingRefusal("next", deep.dropLast(1)))
    }

    @Test
    fun `a nesting key names a file by its canonical path and an asset by its opened path`() {
        val folder = createTempDirectory("nesting-key").toFile()
        try {
            val file = File(folder, "a.json").apply { writeText("{}") }
            File(folder, "sub").mkdir()
            val link = File(folder, "link.json").toPath()
            Files.createSymbolicLink(link, file.toPath())
            val key = loadableNestingKey(LoadableSource.FilePath(file.path, LoadableFormat.JSON))
            assertEquals(key, loadableNestingKey(LoadableSource.FilePath(link.toString(), LoadableFormat.JSON)))
            assertEquals(key, loadableNestingKey(LoadableSource.FilePath(folder.path + "/./sub/../a.json", LoadableFormat.JSON)))
            assertEquals(
                loadableNestingKey(LoadableSource.BundleName("Settings", LoadableFormat.JSON)),
                loadableNestingKey(LoadableSource.BundleName("Settings.json", LoadableFormat.JSON)),
            )
            assertEquals("https://example.com/a.json?x=1", loadableNestingKey(LoadableSource.Remote("https://example.com/a.json?x=1", LoadableFormat.JSON)))
            assertNull(loadableNestingKey(LoadableSource.None))
        } finally {
            folder.deleteRecursively()
        }
    }

    @Test
    fun `only a regular file is read`() {
        val folder = createTempDirectory("regular-file").toFile()
        try {
            val file = File(folder, "a.json").apply { writeText("{\"type\":\"Text\",\"id\":3}") }
            val link = File(folder, "link.json").toPath()
            Files.createSymbolicLink(link, file.toPath())
            val zeroLink = File(folder, "zero.json").toPath()
            Files.createSymbolicLink(zeroLink, File("/dev/zero").toPath())
            assertEquals("{\"type\":\"Text\",\"id\":3}", readRegularFileText(link.toString()))
            for (path in listOf("/dev/zero", "/dev/null", folder.path, zeroLink.toString())) {
                try {
                    readRegularFileText(path)
                    fail("$path was read")
                } catch (e: NotARegularFileException) {
                    assertEquals("$path is not a regular file", e.message)
                }
                try {
                    readRegularFileBytes(path)
                    fail("$path was read as bytes")
                } catch (e: NotARegularFileException) {
                    assertEquals("$path is not a regular file", e.message)
                }
            }
            assertEquals(file.readBytes().toList(), readRegularFileBytes(link.toString()).toList())
            // A missing file keeps its own read error.
            try {
                readRegularFileText(File(folder, "missing.json").path)
                fail("a missing file was read")
            } catch (e: NotARegularFileException) {
                fail("a missing file is not reported as a device")
            } catch (e: java.io.IOException) {
            }
        } finally {
            folder.deleteRecursively()
        }
    }

    @Test
    fun `loadRemoteDescription defers a plist url without fetching`() = runBlocking {
        val source = classifyLoadableSource("https://example.com/view.plist")
        assertTrue("expected Remote, got $source", source is LoadableSource.Remote)
        val result = loadRemoteDescription(source as LoadableSource.Remote, json, logger)
        assertTrue("expected Deferred, got $result", result is DescriptionLoad.Deferred)
    }
}
