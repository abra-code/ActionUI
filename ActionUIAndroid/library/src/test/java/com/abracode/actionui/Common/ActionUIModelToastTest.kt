package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for the window-level toast model surface (`ActionUIModel.presentToast`
 * / `dismissToast` and the resulting [WindowModel.windowToast] / [WindowModel.toastQueue]
 * state). The show / auto-dismiss / action-tap wiring lives in the Composable
 * `WindowToastHost` and is exercised by the demo app; here we cover the model
 * transitions and the queue, which is the ported logic. Mirrors
 * [ActionUIModelDialogTest].
 */
class ActionUIModelToastTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val logger = ConsoleLogger()

    private fun registerWindow(uuid: String) {
        val root = json.decodeFromString(ActionUIElement.serializer(), """{"type":"VStack"}""")
        ActionUIModel.loadDescription(root, uuid, logger)
    }

    // ActionUIModel is a singleton; keep the shared window pool clean around each test.
    @Before fun setUp() = ActionUIModel.windowModels.clear()
    @After fun tearDown() = ActionUIModel.windowModels.clear()

    @Test
    fun `presentToast sets the window toast with the default duration`() {
        registerWindow("w")
        ActionUIModel.presentToast(windowUUID = "w", message = "Saved")

        val toast = ActionUIModel.windowModels["w"]?.windowToast
        assertNotNull(toast)
        assertEquals("Saved", toast?.message)
        assertEquals(4.0, toast?.duration ?: 0.0, 0.0)
        assertNull("No inline action when title/id omitted", toast?.action)
    }

    @Test
    fun `presentToast with title and id adds an inline action`() {
        registerWindow("w")
        ActionUIModel.presentToast(
            windowUUID = "w",
            message = "Logged",
            duration = 5.0,
            actionTitle = "Undo",
            actionID = "task.undo",
        )

        val toast = ActionUIModel.windowModels["w"]?.windowToast
        assertEquals(5.0, toast?.duration ?: 0.0, 0.0)
        assertEquals("Undo", toast?.action?.title)
        assertEquals("task.undo", toast?.action?.actionID)
    }

    @Test
    fun `presentToast requires both title and id for an inline action`() {
        registerWindow("w")
        ActionUIModel.presentToast(windowUUID = "w", message = "x", actionTitle = "Undo")
        assertNull(ActionUIModel.windowModels["w"]?.windowToast?.action)
    }

    @Test
    fun `presentToast queues while one is already visible`() {
        registerWindow("w")
        ActionUIModel.presentToast(windowUUID = "w", message = "first")
        ActionUIModel.presentToast(windowUUID = "w", message = "second")
        ActionUIModel.presentToast(windowUUID = "w", message = "third")

        val model = ActionUIModel.windowModels["w"]
        assertEquals("first", model?.windowToast?.message)
        assertEquals(2, model?.toastQueue?.size)
        assertEquals("second", model?.toastQueue?.first()?.message)
    }

    @Test
    fun `dismissToast promotes the next queued toast`() {
        registerWindow("w")
        ActionUIModel.presentToast(windowUUID = "w", message = "first")
        ActionUIModel.presentToast(windowUUID = "w", message = "second")

        ActionUIModel.dismissToast("w")

        val model = ActionUIModel.windowModels["w"]
        assertEquals("second", model?.windowToast?.message)
        assertEquals(0, model?.toastQueue?.size)
    }

    @Test
    fun `dismissToast clears the toast when the queue is empty`() {
        registerWindow("w")
        ActionUIModel.presentToast(windowUUID = "w", message = "only")
        ActionUIModel.dismissToast("w")

        assertNull(ActionUIModel.windowModels["w"]?.windowToast)
    }

    @Test
    fun `presentToast on an unknown window is a no-op`() {
        ActionUIModel.presentToast(windowUUID = "missing", message = "x")
        assertNull(ActionUIModel.windowModels["missing"])
    }
}
