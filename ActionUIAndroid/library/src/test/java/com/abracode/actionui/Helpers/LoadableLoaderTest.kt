package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ConsoleLogger
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the source-loading seam shared by the embedded `LoadableView`
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
    fun `loadRemoteDescription defers a plist url without fetching`() = runBlocking {
        val source = classifyLoadableSource("https://example.com/view.plist")
        assertTrue("expected Remote, got $source", source is LoadableSource.Remote)
        val result = loadRemoteDescription(source as LoadableSource.Remote, json, logger)
        assertTrue("expected Deferred, got $result", result is DescriptionLoad.Deferred)
    }
}
