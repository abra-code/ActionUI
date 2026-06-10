package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for the window-level modal model surface
 * (`ActionUIModel.presentModal` / `dismissModal`): decoding + merging the modal's
 * view models into the window pool, the resulting [WindowModel.windowModal] state,
 * id-conflict skipping, and pool cleanup + `onDismissActionID` on dismiss. The
 * sheet / cover rendering lives in the Composable `WindowModalHost` and is exercised
 * by the demo app.
 */
class ActionUIModelModalTest {

    private val json = Json { ignoreUnknownKeys = true }
    private val logger = ConsoleLogger()

    private val modalJson =
        """{"type":"VStack","id":50,"children":[{"type":"Text","id":51,"properties":{"text":"Hi"}}]}"""

    private fun registerWindow(uuid: String) {
        // The root carries an id so it registers in the pool (id-less elements
        // do not) - the dismiss/collision tests below assert it survives.
        val root = json.decodeFromString(ActionUIElement.serializer(), """{"type":"VStack","id":1}""")
        ActionUIModel.loadDescription(root, uuid, logger)
    }

    @Before fun setUp() = ActionUIModel.windowModels.clear()

    @After fun tearDown() {
        ActionUIModel.windowModels.clear()
        ActionUIModel.unregisterActionHandler("modal.dismissed")
    }

    @Test
    fun `presentModal merges the modal view models and sets the modal`() {
        registerWindow("w")
        ActionUIModel.presentModal("w", modalJson, ModalStyle.SHEET)

        val window = ActionUIModel.windowModels.getValue("w")
        assertEquals(ModalStyle.SHEET, window.windowModal?.style)
        assertEquals(setOf(50, 51), window.windowModal?.loadedViewIDs)
        assertTrue(window.viewModels.containsKey(50))
        assertTrue(window.viewModels.containsKey(51))
    }

    @Test
    fun `dismissModal removes the modal view models and clears it`() {
        registerWindow("w")
        ActionUIModel.presentModal("w", modalJson, ModalStyle.SHEET)
        ActionUIModel.dismissModal("w")

        val window = ActionUIModel.windowModels.getValue("w")
        assertNull(window.windowModal)
        assertFalse(window.viewModels.containsKey(50))
        assertFalse(window.viewModels.containsKey(51))
        assertTrue("window root must survive a modal dismiss", window.viewModels.containsKey(1))
    }

    @Test
    fun `dismissModal fires onDismissActionID`() {
        registerWindow("w")
        var fired = false
        ActionUIModel.registerActionHandler("modal.dismissed") { _, _, _, _, _ -> fired = true }
        ActionUIModel.presentModal("w", modalJson, ModalStyle.FULL_SCREEN_COVER, onDismissActionID = "modal.dismissed")
        ActionUIModel.dismissModal("w")

        assertTrue(fired)
    }

    @Test
    fun `presentModal skips ids that collide with the existing pool`() {
        registerWindow("w")
        // The window root is id 1; a modal also using id 1 must not overwrite or
        // (on dismiss) evict it.
        val colliding = """{"type":"VStack","id":1,"children":[{"type":"Text","id":60}]}"""
        ActionUIModel.presentModal("w", colliding, ModalStyle.SHEET)

        val window = ActionUIModel.windowModels.getValue("w")
        assertEquals(setOf(60), window.windowModal?.loadedViewIDs)
        ActionUIModel.dismissModal("w")
        assertTrue("colliding root id must be preserved", window.viewModels.containsKey(1))
    }

    @Test
    fun `presentModal on an unknown window is a no-op`() {
        ActionUIModel.presentModal("missing", modalJson, ModalStyle.SHEET)
        assertNull(ActionUIModel.windowModels["missing"])
    }

    @Test
    fun `presentModal with malformed json does not set a modal`() {
        registerWindow("w")
        ActionUIModel.presentModal("w", "not json {", ModalStyle.SHEET)
        assertNull(ActionUIModel.windowModels.getValue("w").windowModal)
    }
}
