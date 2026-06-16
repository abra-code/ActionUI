package com.abracode.actionui.Helpers

import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `scrollContentBackground` - the SwiftUI base property that controls whether a
 * scrollable container (`List`, `Form`, `TextEditor`) draws its *default*
 * background. Mirror of the Apple handling in `View.swift` (validated to
 * `"visible"` / `"hidden"` / `"automatic"`, then applied as
 * `.scrollContentBackground(.visible/.hidden)`).
 *
 * **The platform divergence, made explicit.** On Apple a `List` / `Form` ships a
 * system *grouped* background (`.visible` is the default), and an author writes
 * `.scrollContentBackground(.hidden)` together with a `.background(...)` to swap
 * in a custom one. Compose has no grouped-table-view idiom: a `LazyColumn`
 * (`List`) and a `Column` (`Form`) are **transparent by default**, so the
 * Material default already behaves like Apple's `.hidden` (a base `background`
 * shows through with no extra work). The mapping therefore is:
 *
 *   * [VISIBLE]   - draw an explicit Material container tone
 *     (`colorScheme.surfaceVariant`) behind the scroll content, the Material
 *     analog of iOS's grouped background. As on Apple, a `.visible` background
 *     sits over (hides) a custom `background`.
 *   * [HIDDEN]    - transparent (no container tone). This is already the Android
 *     default, so `"hidden"` is explicit-but-current behavior; a base
 *     `background` shows through.
 *   * [AUTOMATIC] - follows Material, i.e. transparent. (This is where Android
 *     and Apple legitimately differ: Apple's automatic for `List` / `Form` is
 *     the grouped background; Android's is the Material surface. An author who
 *     wants the grouped look on Android asks for it with `"visible"`.)
 *
 * `TextEditor` is the third Apple target but is a no-op here: the Android editor
 * is a Material `OutlinedTextField`, whose container is already transparent
 * (equivalent to a permanent `.hidden`), so there is no default background to
 * toggle. The property is accepted (validated) and has no visible effect there.
 *
 * The mode parse ([resolveScrollContentBackgroundMode]) is pure and unit-tested;
 * the color read needs `MaterialTheme`, so [applyScrollContentBackground] is the
 * `@Composable` call site used by the `List` / `Form` builders.
 */
enum class ScrollContentBackgroundMode { VISIBLE, HIDDEN, AUTOMATIC }

/**
 * Parses `scrollContentBackground` into a [ScrollContentBackgroundMode],
 * defaulting to [ScrollContentBackgroundMode.AUTOMATIC] when absent. A present
 * non-String value, or an unrecognized String, warns and reads as automatic
 * (the `View.swift` validator's warn-and-drop, folded into the read per the
 * Android "validate where you read" rule).
 */
internal fun resolveScrollContentBackgroundMode(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
): ScrollContentBackgroundMode {
    val raw = properties?.get("scrollContentBackground") ?: return ScrollContentBackgroundMode.AUTOMATIC
    val str = (raw as? JsonPrimitive)?.takeIf { it.isString }?.content
    if (str == null) {
        logger?.log(
            "Invalid type for scrollContentBackground: expected String, ignoring",
            LoggerLevel.warning,
        )
        return ScrollContentBackgroundMode.AUTOMATIC
    }
    return when (str) {
        "visible" -> ScrollContentBackgroundMode.VISIBLE
        "hidden" -> ScrollContentBackgroundMode.HIDDEN
        "automatic" -> ScrollContentBackgroundMode.AUTOMATIC
        else -> {
            logger?.log(
                "Invalid scrollContentBackground '$str'; expected 'visible', 'hidden', " +
                    "or 'automatic', ignoring",
                LoggerLevel.warning,
            )
            ScrollContentBackgroundMode.AUTOMATIC
        }
    }
}

/**
 * Appends the `scrollContentBackground` surface to a scrollable container's
 * Modifier: a Material container tone for [ScrollContentBackgroundMode.VISIBLE],
 * nothing for [ScrollContentBackgroundMode.HIDDEN] /
 * [ScrollContentBackgroundMode.AUTOMATIC] (transparent, the Android default).
 * Applied last in the `List` / `Form` builders so a `"visible"` tone sits over
 * any base `background`, matching SwiftUI's default grouped background.
 */
@Composable
internal fun Modifier.applyScrollContentBackground(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
): Modifier =
    when (resolveScrollContentBackgroundMode(properties, logger)) {
        ScrollContentBackgroundMode.VISIBLE -> this.background(MaterialTheme.colorScheme.surfaceVariant)
        ScrollContentBackgroundMode.HIDDEN, ScrollContentBackgroundMode.AUTOMATIC -> this
    }
