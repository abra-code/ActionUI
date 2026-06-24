package com.abracode.actionui.Views

import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a run of text - the Android mirror of the Apple `Text` element
 * (`ActionUI/Views/Text.swift`), which wraps `SwiftUI.Text`.
 *
 * **Value-bearing.** Like Apple, `Text` declares [ActionUIValueType.STRING]: its
 * displayed content is the element's
 * [com.abracode.actionui.Common.ViewModel] value, so a host can replace the text
 * at runtime via `ActionUIModel.setElementValue(id, "...")` /
 * `setElementValueFromString(...)` and the leaf recomposes (the value is Compose
 * snapshot state). When no runtime value is set the static `text` property is
 * shown, so existing static usage is unchanged.
 *
 * **Content precedence** (mirrors Apple's `buildView` / `initialValue`):
 *   1. the runtime [com.abracode.actionui.Common.ViewModel] value (a host write),
 *   2. else the `markdown` property if present (rendered as plain text on
 *      Android - the Compose `Text` markdown gap is unrelated to the value
 *      bridge and unchanged here; the string is still the canonical content so
 *      it is the seed and the fallback, matching Apple's seeding order),
 *   3. else the `text` property (defaults to the empty string).
 *
 * The seeded initial value follows the same order, so a host that reads the
 * value before any write gets the authored content (Apple parity:
 * `initialValue` returns `model.value` or the `markdown`/`text` property).
 *
 * Inherited `font` / `foregroundStyle` and the universal modifiers arrive on
 * [modifier] / the ambient text style via the shared pipeline.
 */
object Text : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? = resolveStaticText(element.properties)

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        // ViewModel-backed when a window is in scope (a host write recomposes
        // this leaf); else the static property. The id-less / no-window path
        // (LocalWindowModel null or no matching ViewModel) falls back to the
        // authored content, so static usage is unaffected.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val runtimeValue = viewModel?.value as? String
        val text = runtimeValue ?: resolveStaticText(element.properties)
        M3Text(text = text, modifier = modifier)
    }
}

/**
 * The authored text content for a `Text` element, before any runtime value:
 * the `markdown` property if present (Apple lets it take precedence over `text`),
 * else the `text` property, else the empty string. Pure, so it is unit-testable
 * and shared by [Text.initialValue] and the builder's fallback.
 */
internal fun resolveStaticText(
    props: kotlinx.serialization.json.JsonObject?,
): String =
    props?.stringProperty("markdown")
        ?: props?.stringProperty("text")
        ?: ""
