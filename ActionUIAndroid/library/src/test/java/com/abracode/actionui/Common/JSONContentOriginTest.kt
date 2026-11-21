package com.abracode.actionui.Common

import com.abracode.actionui.Helpers.LoadableFormat
import com.abracode.actionui.Helpers.LoadableSource
import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Where content came from: classification of a LoadableView's source, and its record on the view models. */
class JSONContentOriginTest {

    private val folders = mutableListOf<File>()

    private fun folder(): File = Files.createTempDirectory("actionui-origin").toFile().also { folders += it }

    @After
    fun tearDown() {
        folders.forEach { it.deleteRecursively() }
        ActionUIModel.resourceFolders = emptyList()
        ActionUIModel.windowModels.remove("origin-test")
    }

    private fun file(path: String) = LoadableSource.FilePath(path, LoadableFormat.JSON)

    @Test
    fun `an asset is a trusted resource, a remote address is less trusted`() {
        val asset = classifyOrigin(LoadableSource.BundleName("Sub", LoadableFormat.JSON), null, 3, emptyList())
        assertEquals(JSONContentOrigin(JSONContentOrigin.Source.Resource("Sub.json"), JSONContentOrigin.Trust.TRUSTED, 3), asset)
        val remote = classifyOrigin(LoadableSource.Remote("https://example.com/v.json", LoadableFormat.JSON), null, null, emptyList())
        assertEquals(JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, null), remote)
        assertNull(classifyOrigin(LoadableSource.None, null, null, emptyList()))
    }

    @Test
    fun `a file is a resource only inside a resource folder, by its canonical path`() {
        val resources = folder()
        val elsewhere = folder()
        val inside = File(resources, "a.json").apply { writeText("{}") }
        val outside = File(elsewhere, "b.json").apply { writeText("{}") }
        val folders = listOf(resources.path)

        val own = classifyOrigin(file(inside.path), null, null, folders)
        assertEquals(JSONContentOrigin.Source.Resource(inside.canonicalPath), own?.source)
        assertEquals(JSONContentOrigin.Trust.TRUSTED, own?.trust)
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, classifyOrigin(file(outside.path), null, null, folders)?.trust)
        // ".." out of the folder, and a symbolic link in it to a file elsewhere, are not inside.
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, classifyOrigin(file("${resources.path}/../${elsewhere.name}/b.json"), null, null, folders)?.trust)
        val link = File(resources, "link.json")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertEquals(JSONContentOrigin.Source.File(outside.canonicalPath), classifyOrigin(file(link.path), null, null, folders)?.source)
        // The folder itself is not a file inside it.
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, classifyOrigin(file(resources.path), null, null, folders)?.trust)
    }

    @Test
    fun `content inside less-trusted content is less trusted, whatever its own source`() {
        val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, null)
        val asset = classifyOrigin(LoadableSource.BundleName("Sub", LoadableFormat.JSON), remote, 5, emptyList())
        assertEquals(JSONContentOrigin.Source.Resource("Sub.json"), asset?.source)
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, asset?.trust)
        assertEquals(5, asset?.parentID)
    }

    @Test
    fun `each load records its origin on the view models it makes`() {
        val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, 2)
        val window = ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "VStack", children = listOf(ActionUIElement(id = 2, type = "LoadableView"))),
            windowUUID = "origin-test",
        )
        window.loadSubDescription(
            ActionUIElement(id = 10, type = "VStack", children = listOf(ActionUIElement(id = 11, type = "Text"))),
            parentID = 2,
            origin = remote,
        )
        assertEquals(JSONContentOrigin.HOST, ActionUIModel.origin("origin-test", 1))
        assertEquals(remote, ActionUIModel.origin("origin-test", 11))
        assertNull(window.viewModels[1]?.origin)
        assertNull("no such element", ActionUIModel.origin("origin-test", 99))
        assertNull("no such window", ActionUIModel.origin("no-such-window", 1))
    }
}
