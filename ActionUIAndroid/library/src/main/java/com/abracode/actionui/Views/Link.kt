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
 *   * `url` - the destination, read as Apple's `URL(string:)` reads it ([linkDestination]):
 *     missing or refused renders nothing (the Apple element falls back to an `EmptyView`); without
 *     a scheme ("example.com") the link is shown and a tap opens nothing, as on Apple.
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
                if (!config.opens) {
                    if (reportedRelativeURLs.add(config.url)) {
                        logger.log("Link URL '${config.url}' has no scheme; there is nothing to open", LoggerLevel.warning)
                    }
                    return@clickable
                }
                try {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(config.url)))
                } catch (e: ActivityNotFoundException) {
                    logger.log("No activity found to open URL '${config.url}'", LoggerLevel.warning)
                } catch (e: RuntimeException) {
                    // A file: URL throws FileUriExposedException for apps targeting Android 7 and
                    // later, and a protected activity SecurityException: nothing opens, as on Apple
                    // when no app takes the URL.
                    logger.log("Could not open URL '${config.url}': ${e.javaClass.simpleName}", LoggerLevel.warning)
                }
            },
        )
    }
}

/** Resolved link title + destination URL; [opens] is false for a URL without a scheme. */
internal data class LinkConfig(val title: String, val url: String, val opens: Boolean)

/** URLs without a scheme tapped so far, each logged once. Read and written on the main thread. */
private val reportedRelativeURLs = mutableSetOf<String>()

/**
 * Resolves the `title`/`url` into a [LinkConfig], mirroring the Apple
 * `Link.buildView`: a missing `url`, or one [linkDestination] refuses, yields
 * `null` (warn, render nothing); the title defaults to `"Link"`. Pure (logging
 * aside) so it is unit-testable.
 */
internal fun resolveLink(props: JsonObject?, logger: ActionUILogger): LinkConfig? {
    val url = props?.stringProperty("url")
    val destination = url?.let { linkDestination(it) } ?: LinkDestination.NONE
    if (url == null || destination == LinkDestination.NONE) {
        logger.log("Link missing a valid 'url'; rendering nothing", LoggerLevel.warning)
        return null
    }
    return LinkConfig(props?.stringProperty("title") ?: "Link", url, destination == LinkDestination.ABSOLUTE)
}

/** Where a link goes, as Apple's Link goes ([linkDestination]). */
internal enum class LinkDestination {
    /** Refused: nothing is shown. */
    NONE,
    /** No scheme ("example.com", "docs/page"): shown, and a tap opens nothing. */
    RELATIVE,
    /** A scheme: handed to the system. */
    ABSOLUTE,
}

/**
 * The destination of [text] as Apple's `URL(string:)` reads it (Link.destination in Core):
 * refused when empty, when the text before a first `:` is no scheme (" https://...", "1abc:x"),
 * or when the host or port after `//` is invalid (a space, `<`, a bad `%` escape, an unclosed `[`,
 * a port that is not digits); every other character is percent-encoded there, so accepted.
 * FormatParity/link-url-cases.json, recorded from Foundation, holds the cases every platform checks.
 */
internal fun linkDestination(text: String): LinkDestination {
    if (text.isEmpty()) return LinkDestination.NONE
    var rest = text
    var hasScheme = false
    val end = text.indexOfFirst { it == ':' || it == '/' || it == '?' || it == '#' }
    if (end >= 0 && text[end] == ':') {
        val prefix = text.substring(0, end)
        when {
            isScheme(prefix) -> {
                hasScheme = prefix.isNotEmpty()
                rest = text.substring(end + 1)
            }
            // Foundation reads these as a relative path ("a@b:x"), not as a bad scheme.
            prefix.any { it == '@' || it == '[' || it == ']' } -> Unit
            else -> return LinkDestination.NONE
        }
    }
    if (rest.startsWith("//")) {
        val authority = rest.substring(2).takeWhile { it != '/' && it != '?' && it != '#' }
        if (!isHostAndPort(authority.substringAfterLast('@'))) return LinkDestination.NONE
    }
    return if (hasScheme) LinkDestination.ABSOLUTE else LinkDestination.RELATIVE
}

/** Empty (":foo", which Foundation accepts with an empty scheme), or a letter, then letters, digits, `+ - .`. */
private fun isScheme(text: String): Boolean =
    text.isEmpty() || (isAsciiLetter(text[0]) && text.all { isAsciiLetter(it) || it in '0'..'9' || it in "+-." })

private fun isAsciiLetter(c: Char): Boolean = c in 'a'..'z' || c in 'A'..'Z'

private fun isHostAndPort(text: String): Boolean {
    if (text.startsWith("[")) {
        val close = text.indexOf(']')
        if (close < 0) return false
        // Inside "[...]", up to a "%" (the zone, "[::1%en0]", which takes anything), only ASCII
        // letters, digits and "-._~!$&'()*+,;=:" ("[::1]", "[v1.x]").
        val address = text.substring(1, close).substringBefore('%')
        if (!address.all { isAsciiLetter(it) || it in '0'..'9' || it in "-._~!\$&'()*+,;=:" }) return false
        val after = text.substring(close + 1)
        return after.isEmpty() || (after[0] == ':' && after.substring(1).all { it in '0'..'9' })
    }
    val colon = text.indexOf(':')
    if (colon >= 0 && !text.substring(colon + 1).all { it in '0'..'9' }) return false
    return isHost(if (colon < 0) text else text.substring(0, colon))
}

/**
 * No space, control character or character a host refuses, `%` only as an escape. A non-ASCII
 * character is part of an international domain name, refused only as a space (U+3000).
 */
private fun isHost(text: String): Boolean {
    var index = 0
    while (index < text.length) {
        val c = text[index]
        if (c.code >= 0x80) {
            if (Character.isSpaceChar(c)) return false
        } else if (c.code <= 0x20 || c.code == 0x7f || c in "\"<>[\\]^`{|}") {
            return false
        } else if (c == '%') {
            if (index + 2 >= text.length || !isHexDigit(text[index + 1]) || !isHexDigit(text[index + 2])) return false
            index += 3
            continue
        }
        index += 1
    }
    return true
}

private fun isHexDigit(c: Char): Boolean = c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F'
