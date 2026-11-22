package com.abracode.actionui.Common

import com.abracode.actionui.Helpers.descriptionMaxBytes
import com.abracode.actionui.Helpers.DescriptionLoad
import com.abracode.actionui.Helpers.LoadableFormat
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.decodeDescription
import com.abracode.actionui.Helpers.readRegularFileText
import com.abracode.actionui.Helpers.utf8LongerThan
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.file.Files
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The trust policy's default rules, the host's policy, the id rule for less-trusted content, and the document cap. */
class TrustPolicyTest {

    private val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/docs/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, 3)
    private val folders = mutableListOf<File>()

    @After
    fun tearDown() {
        folders.forEach { it.deleteRecursively() }
        ActionUIConfiguration.replaceForTesting()
        ActionUIModel.trustPolicy = DefaultTrustPolicy
    }

    private fun allows(capability: ActionUICapability, origin: JSONContentOrigin = remote) = DefaultTrustPolicy.allowsByDefault(capability, origin)

    @Test
    fun `trusted content may do anything`() {
        for (capability in listOf(ActionUICapability.OpenLink("intent://x"), ActionUICapability.WebView("file:///etc/hosts"),
            ActionUICapability.ReadLocalFile("/etc/hosts"), ActionUICapability.WindowTitle, ActionUICapability.PresentModal)) {
            assertTrue(capability.toString(), allows(capability, JSONContentOrigin.HOST))
        }
    }

    @Test
    fun `less-trusted content opens only web and mail links and shows only web addresses`() {
        assertTrue(allows(ActionUICapability.OpenLink("https://example.com/")))
        assertTrue(allows(ActionUICapability.OpenLink("MAILTO:someone@example.com")))
        for (refused in listOf("file:///sdcard/a.pdf", "intent://scan/#Intent;end", "content://contacts/1", "tel:123", "relative/path", "javascript:alert(1)")) {
            assertFalse(refused, allows(ActionUICapability.OpenLink(refused)))
        }
        assertTrue(allows(ActionUICapability.WebView("http://example.com/")))
        assertTrue("inline html", allows(ActionUICapability.WebView(null)))
        assertFalse(allows(ActionUICapability.WebView("file:///android_asset/index.html")))
        assertFalse(allows(ActionUICapability.WebView("javascript:alert(1)")))
    }

    @Test
    fun `less-trusted html keeps only its own document's origin as its base`() {
        assertTrue(allows(ActionUICapability.WebViewBaseURL("https://example.com/other/")))
        assertTrue(allows(ActionUICapability.WebViewBaseURL("https://EXAMPLE.com:443/")))
        assertFalse(allows(ActionUICapability.WebViewBaseURL("https://bank.example/")))
        assertFalse(allows(ActionUICapability.WebViewBaseURL("http://example.com/")))
        val file = JSONContentOrigin(JSONContentOrigin.Source.File("/sdcard/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, 3)
        assertFalse("a local file's html gets no base", allows(ActionUICapability.WebViewBaseURL("https://example.com/"), file))
    }

    @Test
    fun `less-trusted content reads local files only inside the resource folders and neither titles nor presents`() {
        val resources = Files.createTempDirectory("actionui-res").toFile().also { folders += it }
        val inside = File(resources, "pic.png").apply { writeText("x") }
        assertFalse(allows(ActionUICapability.ReadLocalFile(inside.path)))
        ActionUIConfiguration.replaceForTesting(ActionUIConfiguration(resourceFolder = resources.path))
        assertTrue(allows(ActionUICapability.ReadLocalFile(inside.path)))
        assertTrue(allows(ActionUICapability.WebViewScriptFile(inside.path)))
        assertFalse(allows(ActionUICapability.ReadLocalFile("${resources.path}/../elsewhere.png")))
        assertFalse(allows(ActionUICapability.WindowTitle))
        assertFalse(allows(ActionUICapability.PresentModal))
        assertTrue(allows(ActionUICapability.Action("app.save")))
    }

    @Test
    fun `the host's policy has the last word on trust and on each capability`() {
        ActionUIModel.trustPolicy = object : ActionUITrustPolicy {
            override fun trust(source: JSONContentOrigin.Source, parent: JSONContentOrigin?, byDefault: JSONContentOrigin.Trust) =
                if ((source as? JSONContentOrigin.Source.Remote)?.url?.startsWith("https://example.com/") == true) JSONContentOrigin.Trust.TRUSTED else byDefault
            override fun allows(capability: ActionUICapability, origin: JSONContentOrigin) =
                capability != ActionUICapability.Action("app.delete") && DefaultTrustPolicy.allowsByDefault(capability, origin)
        }
        val own = resolvedOrigin(LoadableSource.Remote("https://example.com/v.json", LoadableFormat.JSON), null, 2)
        assertEquals(JSONContentOrigin.Trust.TRUSTED, own?.trust)
        val other = resolvedOrigin(LoadableSource.Remote("https://other.example/v.json", LoadableFormat.JSON), null, 2)
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, other?.trust)
        assertFalse(ActionUIModel.allows(ActionUICapability.Action("app.delete"), JSONContentOrigin.HOST))
        assertTrue(ActionUIModel.allows(ActionUICapability.Action("app.save"), JSONContentOrigin.HOST))
    }

    @Test
    fun `less-trusted content may not use a trusted element's id, and is merged with none of its models`() {
        val window = WindowModel(windowUUID = "", logger = ConsoleLogger())
        window.loadDescription(ActionUIElement(id = 1, type = "VStack", children = listOf(
            ActionUIElement(id = 2, type = "TextField"), ActionUIElement(id = 3, type = "LoadableView"), ActionUIElement(id = 4, type = "LoadableView"))))
        val subRoot = ActionUIElement(id = 10, type = "VStack", children = listOf(ActionUIElement(id = 2, type = "Button")))
        try {
            window.loadSubDescription(subRoot, parentID = 3, origin = remote)
            fail("less-trusted content using a trusted element's id was merged")
        } catch (e: WindowModel.SubViewRefusedException) {
            assertEquals("id conflict: 2 already in the window", e.message)
        }
        assertEquals(null, window.viewModels[10])
        assertEquals("TextField", window.viewModels[2]?.elementType)
        // Two LoadableViews showing one less-trusted document share ids: allowed, the first keeps its models.
        val shared = ActionUIElement(id = 20, type = "Text")
        window.loadSubDescription(shared, parentID = 3, origin = remote)
        window.loadSubDescription(shared, parentID = 4, origin = remote.copy(parentID = 4))
        assertEquals(remote, window.viewModels[20]?.origin)
        // Trusted content with a taken id keeps the old rule: skipped with a warning.
        window.loadSubDescription(ActionUIElement(id = 2, type = "Button"), parentID = 0)
        assertEquals("TextField", window.viewModels[2]?.elementType)
    }

    @Test
    fun `less-trusted content's UriHandler hands on only what the policy allows, trusted content's is the inherited one`() {
        val opened = mutableListOf<String>()
        val inner = object : androidx.compose.ui.platform.UriHandler {
            override fun openUri(uri: String) { opened += uri }
        }
        assertTrue(uriHandlerFor(JSONContentOrigin.HOST, inner, ConsoleLogger()) === inner)
        val guarded = uriHandlerFor(remote, inner, ConsoleLogger())
        for (uri in listOf("tel:123", "file:///sdcard/a.pdf", "intent://scan/#Intent;end", "https://example.com/", "mailto:a@example.com")) {
            guarded.openUri(uri)
        }
        assertEquals(listOf("https://example.com/", "mailto:a@example.com"), opened)
    }

    @Test
    fun `a document larger than 16 MB is not decoded or read`() {
        assertFalse(utf8LongerThan("abc", 3))
        assertTrue(utf8LongerThan("abcd", 3))
        assertTrue("two bytes each", utf8LongerThan("\u00e9\u00e9", 3))
        assertFalse("a surrogate pair is 4 bytes", utf8LongerThan("\uD83D\uDE00", 4))
        val big = "x".repeat(descriptionMaxBytes + 1)
        val result = decodeDescription(big, Json, ConsoleLogger())
        assertTrue(result is DescriptionLoad.Failed && result.message == "Larger than 16 MB")
        val file = Files.createTempFile("actionui-big", ".json").toFile()
        try {
            RandomAccessFile(file, "rw").use { it.setLength(descriptionMaxBytes + 1L) }
            readRegularFileText(file.path)
            fail("a file larger than 16 MB was read")
        } catch (e: IOException) {
            assertTrue(e.message!!.endsWith("is larger than 16 MB"))
        } finally {
            file.delete()
        }
    }
}
