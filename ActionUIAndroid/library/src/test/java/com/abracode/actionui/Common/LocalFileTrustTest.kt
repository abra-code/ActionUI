package com.abracode.actionui.Common

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which local files content may read: trusted content any, less-trusted content only inside the resource folders. */
class LocalFileTrustTest {

    private val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, 3)
    private val folder: File = Files.createTempDirectory("actionui-files").toFile()

    @After
    fun tearDown() {
        folder.deleteRecursively()
        ActionUIConfiguration.replaceForTesting()
        ActionUIModel.trustPolicy = DefaultTrustPolicy
    }

    @Test
    fun `trusted content reads any file without asking the policy`() {
        ActionUIModel.trustPolicy = object : ActionUITrustPolicy {
            override fun allows(capability: ActionUICapability, origin: JSONContentOrigin) = false
        }
        assertTrue(ActionUIModel.readsLocalFile("/sdcard/DCIM/photo.jpg", JSONContentOrigin.HOST))
        assertFalse(ActionUIModel.readsLocalFile("/sdcard/DCIM/photo.jpg", remote))
    }

    @Test
    fun `less-trusted content reads only inside the resource folders`() {
        val inside = File(folder, "pic.png").apply { writeText("x") }
        assertFalse(ActionUIModel.readsLocalFile(inside.path, remote))
        ActionUIConfiguration.replaceForTesting(ActionUIConfiguration(resourceFolder = folder.path))
        assertTrue(ActionUIModel.readsLocalFile(inside.path, remote))
        assertFalse(ActionUIModel.readsLocalFile("/sdcard/DCIM/photo.jpg", remote))
    }
}
