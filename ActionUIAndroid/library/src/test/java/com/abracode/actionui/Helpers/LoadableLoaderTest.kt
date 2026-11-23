package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIConfiguration
import com.abracode.actionui.Common.ConsoleLogger
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
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

    /** A local server that answers each connection with [answer] (null: reads the request and says nothing). */
    private fun withServer(answer: ((Socket) -> Unit)?, test: (String) -> Unit) {
        ServerSocket(0, 4, InetAddress.getLoopbackAddress()).use { server ->
            val accepted = mutableListOf<Socket>()
            val thread = Thread {
                try {
                    while (true) {
                        val socket = server.accept()
                        synchronized(accepted) { accepted += socket }
                        answer?.invoke(socket)
                    }
                } catch (_: IOException) {
                    // The server closed at the end of the test.
                }
            }.apply { isDaemon = true; start() }
            try {
                test("http://127.0.0.1:${server.localPort}/panel.json")
            } finally {
                server.close()
                synchronized(accepted) { accepted.forEach { it.close() } }
                thread.join(2_000)
            }
        }
    }

    private fun connect(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = LOADABLE_REMOTE_TIMEOUT_MS
            readTimeout = LOADABLE_REMOTE_TIMEOUT_MS
        }

    @Test
    fun `a server that never answers is cut off at the load deadline, not the read timeout`() = withServer(null) { url ->
        val started = System.nanoTime()
        val connection = connect(url)
        try {
            withLoadDeadline(connection, url, limitMs = 300) { connection.responseCode }
            fail("a load past its deadline returns nothing")
        } catch (e: IOException) {
            assertTrue(e.message.orEmpty(), e.message.orEmpty().contains("took longer than 0.3 seconds"))
        }
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        assertTrue("ended after $elapsedMs ms, well before the $LOADABLE_REMOTE_TIMEOUT_MS ms read timeout", elapsedMs < 5_000)
    }

    @Test
    fun `a load that ends in time returns its result`() = withServer({ socket ->
        socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".toByteArray())
        socket.getOutputStream().flush()
    }) { url ->
        val connection = connect(url)
        val body = withLoadDeadline(connection, url, limitMs = 10_000) {
            connection.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        }
        assertEquals("{}", body)
    }

    // The configuration's maximumDownloadTime is the deadline a load takes by default; null is none.
    @Test
    fun `the load deadline is the configured maximum download time`() {
        val saved = ActionUIConfiguration.current
        try {
            assertEquals(120_000L, loadableRemoteTotalTimeoutMs)
            ActionUIConfiguration.replaceForTesting(saved.copy(limits = saved.limits.copy(maximumDownloadTime = 0.3)))
            assertEquals(300L, loadableRemoteTotalTimeoutMs)
            ActionUIConfiguration.replaceForTesting(saved.copy(limits = saved.limits.copy(maximumDownloadTime = 0.0001)))
            assertEquals("at least 1 ms", 1L, loadableRemoteTotalTimeoutMs)
            ActionUIConfiguration.replaceForTesting(saved.copy(limits = saved.limits.copy(maximumDownloadTime = null)))
            assertNull(loadableRemoteTotalTimeoutMs)
        } finally {
            ActionUIConfiguration.replaceForTesting(saved)
        }
    }

    @Test
    fun `a configured deadline cuts off a load that takes no limit of its own`() = withServer(null) { url ->
        val saved = ActionUIConfiguration.current
        ActionUIConfiguration.replaceForTesting(saved.copy(limits = saved.limits.copy(maximumDownloadTime = 0.3)))
        val started = System.nanoTime()
        try {
            val connection = connect(url)
            withLoadDeadline(connection, url) { connection.responseCode }
            fail("a load past its deadline returns nothing")
        } catch (e: IOException) {
            assertTrue(e.message.orEmpty(), e.message.orEmpty().contains("took longer than 0.3 seconds"))
        } finally {
            ActionUIConfiguration.replaceForTesting(saved)
        }
        assertTrue((System.nanoTime() - started) / 1_000_000 < 5_000)
    }

    @Test
    fun `with no deadline a slow load finishes`() = withServer({ socket ->
        Thread.sleep(600)
        socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".toByteArray())
        socket.getOutputStream().flush()
    }) { url ->
        val connection = connect(url)
        val body = withLoadDeadline(connection, url, limitMs = null) {
            connection.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        }
        assertEquals("{}", body)
    }
}
