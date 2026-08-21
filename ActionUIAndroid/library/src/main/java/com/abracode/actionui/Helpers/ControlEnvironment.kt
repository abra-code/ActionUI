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
 * read by the control builders:
 *
 *   * `disabled`     -> [LocalActionUIEnabled]      (read by every interactive control)
 *   * `buttonStyle`  -> [LocalActionUIButtonStyle]  (read by `Button`)
 *   * `controlSize`  -> [LocalActionUIControlSize]  (read by `Button`)
 *   * `labelsHidden` -> [LocalActionUILabelsHidden] (read by the labeled controls)
 *
 * `buttonStyle` / `controlSize` / `labelsHidden` are provided once per element from
 * its (static) child properties in [ProvideTextStyleEnvironment]. **`disabled` is
 * different**: it must be RUNTIME-REACTIVE in both directions
 * (`setElementProperty(disabled, true/false)`), matching Apple (which reads
 * `disabled` off the mutated `validatedProperties` every render) and web (whose
 * runtime applier toggles it either way). So `disabled` is resolved and provided
 * by [ProvideReactiveEnvironment] (`ReactiveEnvironment.kt`) at the shared build
 * entry point (`ViewModifierHelper.BuildViewWithModifiers`), on the host-merged
 * *effective* element (`ViewModel.propertyOverrides`) - the same provider and place
 * `hidden`, `foregroundStyle`, and `tint` become reactive - NOT off the parent's
 * static child properties.
 *
 * **`disabled` combination.** SwiftUI ANDs `isEnabled` down the hierarchy: a
 * `.disabled(false)` cannot re-enable a subtree an ancestor disabled.
 * [ProvideReactiveEnvironment] mirrors that by only ever narrowing - it provides
 * `LocalActionUIEnabled = false` only when the element itself resolves
 * `disabled: true`; when `disabled` is `false`/absent it provides nothing, so the
 * subtree inherits the ancestor value. Because each element re-runs this on its
 * own effective properties, re-enabling an OWN authored-disabled element
 * (`disabled: false` -> provides nothing -> inherits the ancestor's enabled
 * value) works, while an ancestor's `false` still ANDs down.
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

/**
 * Whether user input (scroll gestures in particular) may reach this subtree.
 * `true` by default; provided `false` for a `hidden` subtree by
 * [ProvideReactiveEnvironment].
 *
 * A `hidden` element is invisible AND non-interactive on Apple (`.hidden()`,
 * removed from hit-testing) and web (`display:none`, removed from the layout and
 * hit-testing). On Android `hidden` maps to `alpha(0f)` (invisible but still laid
 * out - the reserve-space semantics documented in Missing_Features #30), which
 * leaves the subtree HIT-TESTABLE. In the section-switcher idiom (overlapping
 * bodies in a `ZStack`, all but one `hidden`) that lets an invisible body on top
 * in z-order steal touches from the visible body behind it: its `LazyColumn`
 * claims the vertical drag, so the visible list never scrolls (Missing_Features
 * #34). Scrollable containers (`List` and the lazy stacks/grids, `ScrollView`)
 * read this local and, when `false`, render a bare `Box` with the same modifiers
 * instead of their scroll viewport (`userScrollEnabled = false` is NOT enough -
 * the LazyColumn would still be a hit target blocking the sibling), so a hidden
 * scroll container carries no scrollable/pointer node at all and hit-testing
 * falls through to the visible sibling behind - matching the non-interactive
 * `hidden` of Apple/web while a bounded container still reserves its viewport
 * size. Like [LocalActionUIEnabled] it only ever narrows.
 */
val LocalActionUIInputEnabled: ProvidableCompositionLocal<Boolean> =
    compositionLocalOf { true }

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
 * The runtime-reactive control-environment locals for an element's subtree,
 * resolved from its (effective) [properties]:
 *
 *   * `disabled` -> [LocalActionUIEnabled] (`false` when the element resolves
 *     `disabled: true`; see the class note on the narrowing rule).
 *   * `hidden`   -> [LocalActionUIInputEnabled] (`false` when the element is
 *     `hidden`, so its scrollable containers stop stealing touch from a visible
 *     sibling behind them in a section-switcher ZStack; see the local's note).
 *
 * These are provided by [ProvideReactiveEnvironment] (`ReactiveEnvironment.kt`),
 * the single reactive-environment provider applied at the shared build entry point
 * (`ViewModifierHelper`) on the host-merged effective element and in `TemplateHelper`
 * for template rows, so a `setElementProperty(disabled/hidden, ...)` write reaches
 * them. Both locals only ever NARROW (a value is provided only to turn the flag on),
 * so a descendant cannot re-enable what an ancestor removed, while an element
 * re-enabling its OWN authored flag inherits the ancestor value. The decision funcs
 * below ([disabledLocalOverride] / [inputEnabledLocalOverride]) are pure so the
 * narrowing rule is unit-testable independently of composition.
 */

/**
 * The value [ProvideReactiveEnvironment] provides for [LocalActionUIEnabled] given an element's
 * (effective) [properties], or `null` to inherit the ancestor value. Only ever `false`
 * (the NARROWING rule): `disabled: true` -> `false`; `disabled: false`/absent -> `null`. So a
 * descendant cannot re-enable a subtree a disabled ancestor turned off (SwiftUI AND-down), while
 * an element re-enabling its OWN authored `disabled` (now `false` on the effective element -> `null`)
 * inherits the ancestor's enabled value. Pure, so the reactive-disabled decision is unit-testable.
 */
internal fun disabledLocalOverride(properties: JsonObject?, logger: ActionUILogger? = null): Boolean? {
    if (properties == null) return null
    // `hidden` disables too. A hidden element is invisible and must be inert, and the
    // ONLY route to "inert" that reaches every control is this local - `disabled`
    // already travels it (Views/Button.kt, NavigationLink.kt, DisclosureGroup.kt, the
    // container tap). The alternative, swallowing pointer events in `hiddenSubtree`,
    // also swallows them for whatever is BEHIND the hidden element, which is the bug
    // it was written to fix (see ModifierResolver.hiddenSubtree).
    if (properties.booleanProperty("hidden") == true) return false
    return if (resolveDisabled(properties, logger) == true) false else null
}

/**
 * The value [ProvideReactiveEnvironment] provides for [LocalActionUIInputEnabled], or `null` to
 * inherit. Only ever `false` (narrowing): a `hidden` element removes input (scroll) from its
 * subtree so it stops stealing touch from a visible sibling (see [LocalActionUIInputEnabled]).
 * Its twin [disabledLocalOverride] takes `hidden` down the CONTROL half of the same road.
 */
internal fun inputEnabledLocalOverride(properties: JsonObject?): Boolean? =
    if (properties?.booleanProperty("hidden") == true) false else null

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
