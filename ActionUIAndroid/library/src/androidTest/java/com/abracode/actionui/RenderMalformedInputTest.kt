package com.abracode.actionui

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * ActionUI.Render and RenderAsset show "Failed to load view: ..." for text that does not
 * parse or decode and for an asset that does not exist, as RenderSource does. Before, both
 * threw during composition, which stopped the app.
 */
@RunWith(AndroidJUnit4::class)
class RenderMalformedInputTest {
    @get:Rule
    val rule = createComposeRule()

    private val window = "render-malformed-${System.nanoTime()}"

    @Test
    fun textThatIsNotJSONShowsAnError() {
        rule.setContent { ActionUI.Render("not json", windowUUID = window) }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: Failed to parse description").assertExists()
    }

    @Test
    fun jsonThatIsNotAnElementShowsAnError() {
        rule.setContent { ActionUI.Render("""[1, 2, 3]""", windowUUID = window) }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view", substring = true).assertExists()
    }

    @Test
    fun aMissingAssetShowsAnError() {
        rule.setContent { ActionUI.RenderAsset("no-such-document.json", windowUUID = window) }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: Resource 'no-such-document.json' not found").assertExists()
    }

    @Test
    fun validJSONStillRenders() {
        rule.setContent {
            ActionUI.Render("""{ "type": "Text", "id": 1, "properties": { "text": "Rendered" } }""", windowUUID = window)
        }
        rule.waitForIdle()
        rule.onNodeWithText("Rendered").assertExists()
    }
}
