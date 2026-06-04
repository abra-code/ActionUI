package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty

/**
 * Standard empty-state placeholder: a title with an optional description. Mirror
 * of the Apple `ContentUnavailableView` element
 * (`ActionUI/Views/ContentUnavailableView.swift`), which wraps
 * `SwiftUI.ContentUnavailableView`.
 *
 * **Value-bearing.** Like Apple, it declares [ActionUIValueType.STRING]: the
 * primary message is the [com.abracode.actionui.Common.ViewModel] value, so a
 * host can update the title (or the search query) at runtime via
 * `ActionUIModel.setElementValue(...)` and it recomposes.
 *
 * **Supported properties.**
 *   * `title` - primary message (defaults to `"No Content"`); overridden by the
 *     runtime value when set.
 *   * `description` - optional secondary text.
 *   * `search` - when `true`, shows the search empty-state message built by
 *     [contentUnavailableSearchText]; `title`/`description` are then ignored.
 *   * `query` - the search term shown in the search message (also settable via
 *     the runtime value).
 *   * `systemImage` - **not rendered on Android** (SF Symbol; gated on the
 *     image/icon-resolution track, B2). Text-first, matching the inventory plan.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 *
 * The content is centered horizontally; vertical centering depends on the height
 * the parent gives it (no greedy fill, the stance the shapes take).
 */
object ContentUnavailableView : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? {
        val props = element.properties
        return if (props?.booleanProperty("search") == true) {
            props.stringProperty("query") ?: ""
        } else {
            props?.stringProperty("title") ?: "No Content"
        }
    }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = element.properties
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val runtimeValue = viewModel?.value as? String

        if (props?.stringProperty("systemImage") != null) {
            logger.log(
                "ContentUnavailableView systemImage is not supported on Android; rendering text only",
                LoggerLevel.debug
            )
        }

        val isSearch = props?.booleanProperty("search") == true
        val title: String
        val description: String?
        if (isSearch) {
            title = contentUnavailableSearchText(runtimeValue ?: props?.stringProperty("query") ?: "")
            description = null
        } else {
            title = runtimeValue ?: props?.stringProperty("title") ?: "No Content"
            description = props?.stringProperty("description")
        }

        Column(
            modifier = modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            M3Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            if (!description.isNullOrEmpty()) {
                M3Text(
                    description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/**
 * The search empty-state message: `"No Results"` when [query] is empty, else
 * `"No Results for \"<query>\""` - the Android text form of SwiftUI's
 * `ContentUnavailableView.search` / `.search(text:)`. Pure and unit-testable.
 */
internal fun contentUnavailableSearchText(query: String): String =
    if (query.isEmpty()) "No Results" else "No Results for \"$query\""
