package com.abracode.actionui.Views

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
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
 * Tappable hyperlink that opens a URL. Mirror of the Apple `Link` element
 * (`ActionUI/Views/Link.swift`), which wraps `SwiftUI.Link`.
 *
 * SwiftUI's `Link` opens its destination through the environment's open-URL
 * action (a browser, by default). The Android analog is an
 * `Intent(ACTION_VIEW)`: the link renders as a tappable, tinted, underlined
 * [M3Text] that launches the system handler for the URL.
 *
 * **Supported properties.**
 *   * `title` - link text (defaults to `"Link"`, matching Apple).
 *   * `url` - the destination; missing/blank renders nothing (the Apple element
 *     falls back to an `EmptyView`).
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 *
 * **Tint.** An inherited [LocalActionUITint] colors the link text; otherwise the
 * Material `primary` color is used (the conventional link affordance).
 */
object Link : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val config = resolveLink(element.properties, logger) ?: return
        val context = LocalContext.current
        // SwiftUI `.disabled` (set here or on any ancestor): block the tap and
        // dim the text with Material's standard disabled alpha.
        val enabled = LocalActionUIEnabled.current
        val color = (LocalActionUITint.current ?: MaterialTheme.colorScheme.primary)
            .let { if (enabled) it else it.copy(alpha = 0.38f) }

        M3Text(
            text = config.title,
            color = color,
            textDecoration = TextDecoration.Underline,
            modifier = modifier.clickable(enabled = enabled) {
                try {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(config.url)))
                } catch (e: ActivityNotFoundException) {
                    logger.log("No activity found to open URL '${config.url}'", LoggerLevel.warning)
                }
            },
        )
    }
}

/** Resolved link title + destination URL. */
internal data class LinkConfig(val title: String, val url: String)

/**
 * Resolves the `title`/`url` into a [LinkConfig], mirroring the Apple
 * `Link.buildView`: a missing or blank `url` yields `null` (warn, render
 * nothing); the title defaults to `"Link"`. Pure (logging aside) so it is
 * unit-testable.
 */
internal fun resolveLink(props: JsonObject?, logger: ActionUILogger): LinkConfig? {
    val url = props?.stringProperty("url")?.trim()
    if (url.isNullOrEmpty()) {
        logger.log("Link missing a valid 'url'; rendering nothing", LoggerLevel.warning)
        return null
    }
    return LinkConfig(props?.stringProperty("title") ?: "Link", url)
}
