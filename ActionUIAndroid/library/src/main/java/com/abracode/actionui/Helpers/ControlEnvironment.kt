package com.abracode.actionui.Helpers

import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Inherited control state and styling - the Android counterpart of SwiftUI's
 * `.disabled`, `.buttonStyle`, and `.controlSize`, which (like the text-styling
 * trio in `TextStyleEnvironment.kt`) are *environment* modifiers: applied to any
 * view, they flow down to every descendant control until overridden.
 *
 * Compose models all three per component - `enabled` is a parameter on each
 * Material control, and button emphasis/size are distinct composables
 * (`Button` / `FilledTonalButton` / `TextButton`) and metrics, not an ambient
 * value. So, exactly as `tint` did, each gets a [ProvidableCompositionLocal]
 * provided once per element (through the [ProvideTextStyleEnvironment] seam)
 * and read by the control builders:
 *
 *   * `disabled`    -> [LocalActionUIEnabled]      (read by every interactive control)
 *   * `buttonStyle` -> [LocalActionUIButtonStyle]  (read by `Button`)
 *   * `controlSize` -> [LocalActionUIControlSize]  (read by `Button`)
 *
 * **`disabled` combination.** SwiftUI ANDs `isEnabled` down the hierarchy: a
 * `.disabled(false)` cannot re-enable a subtree an ancestor disabled. The
 * provider mirrors that by only ever narrowing - `disabled: true` provides
 * `false`, while `disabled: false` (or absent) leaves the inherited value
 * untouched.
 *
 * **Vocabulary** matches `View.swift` validation: `buttonStyle` is one of
 * `automatic` / `plain` / `borderless` / `bordered` / `borderedProminent`,
 * `controlSize` one of `mini` / `small` / `regular` / `large` / `extraLarge`.
 * Unknown values warn-and-skip, like every other modifier.
 */
val LocalActionUIEnabled: ProvidableCompositionLocal<Boolean> =
    compositionLocalOf { true }

val LocalActionUIButtonStyle: ProvidableCompositionLocal<ActionUIButtonStyle?> =
    compositionLocalOf { null }

val LocalActionUIControlSize: ProvidableCompositionLocal<ActionUIControlSize?> =
    compositionLocalOf { null }

/** SwiftUI `ButtonStyle` vocabulary; the Material mapping lives in `Views/Button.kt`. */
enum class ActionUIButtonStyle {
    AUTOMATIC, PLAIN, BORDERLESS, BORDERED, BORDERED_PROMINENT
}

/** SwiftUI `ControlSize` vocabulary; the Material metrics live in `Views/Button.kt`. */
enum class ActionUIControlSize {
    MINI, SMALL, REGULAR, LARGE, EXTRA_LARGE
}

/** Parses a `buttonStyle` value, warning (like `View.swift`) on an unknown name. */
internal fun parseButtonStyle(name: String, logger: ActionUILogger? = null): ActionUIButtonStyle? =
    when (name) {
        "automatic"          -> ActionUIButtonStyle.AUTOMATIC
        "plain"              -> ActionUIButtonStyle.PLAIN
        "borderless"         -> ActionUIButtonStyle.BORDERLESS
        "bordered"           -> ActionUIButtonStyle.BORDERED
        "borderedProminent"  -> ActionUIButtonStyle.BORDERED_PROMINENT
        else -> {
            logger?.log("Invalid buttonStyle '$name', ignoring", LoggerLevel.warning)
            null
        }
    }

/** Parses a `controlSize` value, warning (like `View.swift`) on an unknown name. */
internal fun parseControlSize(name: String, logger: ActionUILogger? = null): ActionUIControlSize? =
    when (name) {
        "mini"       -> ActionUIControlSize.MINI
        "small"      -> ActionUIControlSize.SMALL
        "regular"    -> ActionUIControlSize.REGULAR
        "large"      -> ActionUIControlSize.LARGE
        "extraLarge" -> ActionUIControlSize.EXTRA_LARGE
        else -> {
            logger?.log(
                "Invalid controlSize '$name'; expected one of " +
                    "[mini, small, regular, large, extraLarge], ignoring",
                LoggerLevel.warning
            )
            null
        }
    }

/**
 * Reads the `disabled` flag off [properties], warning on a non-Boolean value
 * (`View.swift` parity). Returns `true` only when the subtree must be disabled.
 */
internal fun resolveDisabled(properties: JsonObject, logger: ActionUILogger? = null): Boolean {
    val raw = properties["disabled"] ?: return false
    val value = (raw as? JsonPrimitive)?.let { properties.booleanProperty("disabled") }
    if (value == null) {
        logger?.log("Invalid type for disabled: expected Bool, ignoring", LoggerLevel.warning)
        return false
    }
    return value
}
