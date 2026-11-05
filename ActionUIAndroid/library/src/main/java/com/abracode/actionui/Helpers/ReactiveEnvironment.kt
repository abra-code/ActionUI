package com.abracode.actionui.Helpers

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import com.abracode.actionui.Common.ActionUILogger
import kotlinx.serialization.json.JsonObject

/**
 * The single provider for the environment properties that must react to a host
 * `setElementProperty` write at runtime. It is applied once per element at the
 * shared build entry point (`ViewModifierHelper.BuildViewWithModifiers`) on the
 * host-merged *effective* element (`effectiveElement` / `ViewModel.propertyOverrides`),
 * and in `TemplateHelper` on a row's substituted properties, so a host mutation
 * recomposes the element and its subtree - the Apple contract (views read the
 * mutated `validatedProperties` every render) and web (its runtime applier).
 *
 * **Why one provider, not one per property.** The renderer resolves environment
 * on exactly two axes, and every environment property belongs to one:
 *
 *   * STATIC, provided by the parent off its authored child properties -
 *     [ProvideTextStyleEnvironment] (`font`, `multilineTextAlignment`,
 *     `textSelection`, `buttonStyle`, `controlSize`, `labelsHidden`).
 *   * REACTIVE, provided here off the element's own effective properties - this
 *     provider.
 *
 * So the number of providers is bounded by those two axes, NOT by the property
 * count: a new reactive property is one more entry in the [buildList] below (and
 * its pure resolver), never a new nested wrapper. Everything lands in one
 * [CompositionLocalProvider], so a leaf with several reactive properties pays for
 * one composition group, not one per property.
 *
 * **One composition shape, always.** The provider is emitted for EVERY element,
 * with an empty list when nothing applies. These properties change at runtime, and
 * Compose identifies a composable by its position in the group structure: calling
 * [content] directly for one value and inside a provider for another puts the
 * subtree in a different group, so Compose disposes it and composes it anew. Every
 * `remember` and effect below is lost, and an `AndroidView` releases its view and
 * runs its factory again - a toggle of `hidden` (or `disabled`, `tint`,
 * `foregroundStyle`) on any element destroyed the native views in its subtree.
 * The static [ProvideTextStyleEnvironment] may keep its fast path: its properties
 * are authored, not written at runtime.
 *
 * **Provided locals.**
 *
 *   * `foregroundStyle` -> [LocalContentColor] (read by `Text`)  - OVERRIDES: an
 *     element's own color replaces the inherited one for its subtree, the standard
 *     [CompositionLocalProvider] contract and SwiftUI's inner-wins environment.
 *   * `tint` -> [LocalActionUITint] (read by the controls)       - OVERRIDES.
 *   * `disabled` -> [LocalActionUIEnabled]                       - NARROWS.
 *   * `hidden` -> [LocalActionUIInputEnabled]                    - NARROWS.
 *
 * "Narrows" (`disabled` / `hidden`) means a value is provided ONLY to turn the flag
 * on, so a descendant cannot re-enable what an ancestor removed (SwiftUI AND-down),
 * while an element re-enabling its OWN authored flag inherits the ancestor value;
 * see [disabledLocalOverride] / [inputEnabledLocalOverride] (`ControlEnvironment.kt`),
 * the pure decision functions kept separate so the narrowing rule is unit-testable
 * without composition. The color resolvers ([resolveStyleColor],
 * `TextStyleEnvironment.kt`) are likewise pure.
 */
@Composable
fun ProvideReactiveEnvironment(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
    content: @Composable () -> Unit,
) {
    val foregroundName = properties?.stringProperty("foregroundStyle")
    val tintName = properties?.stringProperty("tint")
    val disabled = disabledLocalOverride(properties, logger)
    val input = inputEnabledLocalOverride(properties)
    // Read only when a color name is actually present to resolve. MaterialTheme.colorScheme
    // is a @ReadOnlyComposable (it emits no group), so this conditional read is legal, keeps
    // the shape stable, and lets a color name (incl. semantic names like "secondary"/"link")
    // map to an adaptive Material role.
    val colorScheme = if (foregroundName != null || tintName != null) MaterialTheme.colorScheme else null
    val provided = buildList {
        colorScheme?.let { scheme ->
            resolveStyleColor(foregroundName, "foregroundStyle", scheme, logger)?.let { add(LocalContentColor provides it) }
            resolveStyleColor(tintName, "tint", scheme, logger)?.let { add(LocalActionUITint provides it) }
        }
        disabled?.let { add(LocalActionUIEnabled provides it) }
        input?.let { add(LocalActionUIInputEnabled provides it) }
    }
    // Always the provider, even with nothing to provide (the class note: one shape).
    CompositionLocalProvider(*provided.toTypedArray()) { content() }
}
