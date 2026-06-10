package com.abracode.actionui.Views

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextDecoration
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject

/**
 * Tappable control that shares an item through the system share sheet. Mirror of
 * the Apple `ShareLink` element (`ActionUI/Views/ShareLink.swift`), which wraps
 * `SwiftUI.ShareLink`.
 *
 * SwiftUI's `ShareLink` presents the share sheet for an item; the Android analog
 * is an `Intent(ACTION_SEND)` launched through a chooser. It renders as a
 * tappable, tinted, underlined `"Share"` [M3Text].
 *
 * **Supported properties.**
 *   * `item` - the shared URL/text; missing/blank renders nothing (the Apple
 *     element falls back to an `EmptyView`).
 *   * `subject` - maps to `Intent.EXTRA_SUBJECT` and the chooser title.
 *   * `message` - has no distinct slot in an Android `ACTION_SEND` (the body is
 *     `EXTRA_TEXT`), so it is prepended to the shared text; see [shareText].
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 */
object ShareLink : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val config = resolveShareConfig(element.properties, logger) ?: return
        val context = LocalContext.current
        // SwiftUI `.disabled` (set here or on any ancestor): block the tap and
        // dim the text with Material's standard disabled alpha.
        val enabled = LocalActionUIEnabled.current
        val color = (LocalActionUITint.current ?: MaterialTheme.colorScheme.primary)
            .let { if (enabled) it else it.copy(alpha = 0.38f) }

        M3Text(
            text = "Share",
            color = color,
            textDecoration = TextDecoration.Underline,
            modifier = modifier.clickable(enabled = enabled) {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, shareText(config))
                    config.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                }
                try {
                    context.startActivity(Intent.createChooser(send, config.subject ?: "Share"))
                } catch (e: ActivityNotFoundException) {
                    logger.log("No activity found to share '${config.item}'", LoggerLevel.warning)
                }
            },
        )
    }
}

/** Resolved share item plus optional subject/message. */
internal data class ShareConfig(val item: String, val subject: String?, val message: String?)

/**
 * Resolves `item`/`subject`/`message` into a [ShareConfig], mirroring the Apple
 * `ShareLink`: a missing or blank `item` yields `null` (warn, render nothing).
 * Pure (logging aside) so it is unit-testable.
 */
internal fun resolveShareConfig(props: JsonObject?, logger: ActionUILogger): ShareConfig? {
    val item = props?.stringProperty("item")?.trim()
    if (item.isNullOrEmpty()) {
        logger.log("ShareLink missing a valid 'item'; rendering nothing", LoggerLevel.warning)
        return null
    }
    return ShareConfig(item, props?.stringProperty("subject"), props?.stringProperty("message"))
}

/**
 * The text put into the share intent. SwiftUI's `message` is a separate preview
 * string, but Android `ACTION_SEND` has only `EXTRA_TEXT`, so a non-empty
 * `message` is prepended to the `item`. Pure and unit-testable.
 */
internal fun shareText(config: ShareConfig): String =
    if (config.message.isNullOrEmpty()) config.item else "${config.message} ${config.item}"
