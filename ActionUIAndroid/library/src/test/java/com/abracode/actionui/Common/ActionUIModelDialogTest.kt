package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for the window-level dialog model surface
 * (`ActionUIModel.presentAlert` / `presentConfirmationDialog` / `dismissDialog`
 * and the resulting [WindowModel.windowDialog] state). The button-tap -> action ->
 * dismiss wiring lives in the Composable `WindowDialogHost` and is exercised by the
 * demo app; here we cover the model transitions, which is the ported logic.
 */
class ActionUIModelDialogTest {

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
    fun `presentAlert sets an alert dialog with the default OK button`() {
        registerWindow("w")
        ActionUIModel.presentAlert(windowUUID = "w", title = "Hi", message = "There")

        val dialog = ActionUIModel.windowModels["w"]?.windowDialog
        assertEquals(DialogStyle.ALERT, dialog?.style)
        assertEquals("Hi", dialog?.title)
        assertEquals("There", dialog?.message)
        assertEquals(1, dialog?.buttons?.size)
        assertEquals(DialogButtonRole.CANCEL, dialog?.buttons?.first()?.role)
    }

    @Test
    fun `presentConfirmationDialog sets a confirmation dialog with the given buttons`() {
        registerWindow("w")
        ActionUIModel.presentConfirmationDialog(
            windowUUID = "w",
            title = "Pick",
            buttons = listOf(DialogButton("A", actionID = "a"), DialogButton("B")),
        )

        val dialog = ActionUIModel.windowModels["w"]?.windowDialog
        assertEquals(DialogStyle.CONFIRMATION_DIALOG, dialog?.style)
        assertEquals(2, dialog?.buttons?.size)
        assertEquals("a", dialog?.buttons?.first()?.actionID)
    }

    @Test
    fun `dismissDialog clears the active dialog`() {
        registerWindow("w")
        ActionUIModel.presentAlert(windowUUID = "w", title = "Hi")
        ActionUIModel.dismissDialog("w")

        assertNull(ActionUIModel.windowModels["w"]?.windowDialog)
    }

    @Test
    fun `present on an unknown window is a no-op`() {
        // No window registered for "missing": present must not create one or crash.
        ActionUIModel.presentAlert(windowUUID = "missing", title = "Hi")
        assertNull(ActionUIModel.windowModels["missing"])
    }
}
