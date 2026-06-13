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
 * provided once per element (through [ProvideTextStyleEnvironment])
 * and read by the control builders:
 *
 *   * `disabled`     -> [LocalActionUIEnabled]      (read by every interactive control)
 *   * `buttonStyle`  -> [LocalActionUIButtonStyle]  (read by `Button`)
 *   * `controlSize`  -> [LocalActionUIControlSize]  (read by `Button`)
 *   * `labelsHidden` -> [LocalActionUILabelsHidden] (read by the labeled controls)
 *
 * **`disabled` combination.** SwiftUI ANDs `isEnabled` down the hierarchy: a
 * `.disabled(false)` cannot re-enable a subtree an ancestor disabled. The
 * provider mirrors that by only ever narrowing - `disabled: true` provides
 * `false`, while `disabled: false` (or absent) leaves the inherited value
 * untouched.
 *
 * **`labelsHidden`** mirrors SwiftUI's `.labelsHidden()`: it hides the built-in
 * labels of the labeled controls in the subtree - `Toggle`, `Picker`,
 * `DatePicker`, `ColorPicker`, `Stepper`, and `LabeledContent` - while leaving
 * their values visible. Like `.labelsHidden()` (which takes no argument and
 * cannot be undone by a descendant), the provider only ever narrows:
 * `labelsHidden: true` provides `true`, `false` (or absent) inherits. Not
 * affected, matching SwiftUI: a `Gauge`'s title (part of its data display) and
 * the text fields' floating label (their `title` doubles as the placeholder,
 * which `.labelsHidden()` does not remove).
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

val LocalActionUILabelsHidden: ProvidableCompositionLocal<Boolean> =
    compositionLocalOf { false }

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

/**
 * Reads the `labelsHidden` flag off [properties], warning on a non-Boolean
 * value (`View.swift` parity). Returns `true` only when the subtree's control
 * labels must be hidden.
 */
internal fun resolveLabelsHidden(properties: JsonObject, logger: ActionUILogger? = null): Boolean {
    val raw = properties["labelsHidden"] ?: return false
    val value = (raw as? JsonPrimitive)?.let { properties.booleanProperty("labelsHidden") }
    if (value == null) {
        logger?.log("Invalid type for labelsHidden: expected Bool, ignoring", LoggerLevel.warning)
        return false
    }
    return value
}
