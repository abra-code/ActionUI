package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text as M3Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyOuterProperties
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The `searchable` property modifier - the Android mirror of Apple's
 * `SearchableModifierView` (`ActionUI/Helpers/SearchableHelper.swift`). Declaring
 *
 *     "searchable": { "actionID": "<required>", "prompt": "<optional>" }
 *
 * on a `List` / `NavigationStack` surfaces a search field whose query is emitted
 * to `actionID` on every change (the query string as the action context), so the
 * host filters its data and re-pushes rows. Routed from
 * [BuildViewWithModifiers]: an element carrying a valid `searchable` is wrapped
 * in a [Column] with the field above its content (the rest of the modifier chain
 * continues through [BuildViewWithDecorations] underneath).
 *
 * **Placement is the platform idiom, not a port.** SwiftUI's `.searchable` floats
 * the field into the nearest navigation bar; Android's idiom for searching a list
 * is an inline field pinned at the top of that list, so that is where it goes -
 * directly above the element it is declared on. The essential contract (a search
 * field that emits the query on each change) is identical either way.
 *
 * **Native.** The field is a Material3 filled [TextField] dressed as the Material
 * search field: the first-party [SearchBarDefaults.inputFieldShape] (the stadium
 * pill), a tonal `surfaceContainerHigh` container with no underline, a leading
 * magnifier (`search`) and, while the query is non-empty, a trailing clear button
 * (`close`). The glyphs come from the bundled Material Symbols Rounded font via
 * [ChromeSymbolIcon] - the same icon language every other ActionUI icon uses, so
 * the chrome matches the content (rather than the visually distinct classic
 * Material Icons set). It is deliberately *not* the Material3 `SearchBar`: that
 * component expands on focus into a separate full-screen / docked surface for
 * search suggestions, whereas `searchable` filters the very list below it (Apple's
 * `.searchable` semantics) - so a persistent inline filter field is the right
 * Material idiom here, wearing the SearchBar's own shape and colors.
 *
 * The query is locally owned ([rememberSaveable], keyed by the element id), like
 * the Apple wrapper's `@State`; it is not bridged to the host value API (the host
 * drives off the emitted `actionID`, matching Apple).
 */
@Composable
internal fun ActionUIViewConstruction.BuildViewWithSearchable(
    element: ActionUIElement,
    config: SearchableConfig,
    modifier: Modifier,
    animator: ElementAnimator?,
) {
    val logger = LocalActionUILogger.current
    // The Column is the layout unit facing the parent: the parent data and the
    // outer property half (transforms / offset / opacity) land on it, so the
    // field and the content move together. The element below takes the inner half
    // through BuildViewWithDecorations (it applies it), with a bare Modifier here.
    Column(modifier.applyOuterProperties(element.properties, logger, animator)) {
        SearchField(config, element.id)
        BuildViewWithDecorations(element, Modifier, animator)
    }
}

/** The Material3 search field for [BuildViewWithSearchable]; emits the query on each change. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchField(config: SearchableConfig, elementID: Int) {
    var query by rememberSaveable(elementID) { mutableStateOf("") }
    // Apple fires onChange(of: query) only on an actual change; guard to match.
    // The clear button routes through the same path so it emits the empty query.
    val update: (String) -> Unit = { new ->
        if (new != query) {
            query = new
            ActionUIModel.actionHandler(config.actionID, viewID = elementID, viewPartID = 0, context = new)
        }
    }
    // A filled TextField wearing the Material search field's own shape (a stadium
    // pill, from SearchBarDefaults) and a tonal container with the indicator line
    // suppressed - the persistent search-field look, without the SearchBar's
    // expand-to-overlay behavior (see the KDoc for why that does not fit here).
    val container = MaterialTheme.colorScheme.surfaceContainerHigh
    // A hidden or disabled searchable element must not keep a live, focusable field
    // sitting over whatever is behind it (Helpers/ControlEnvironment.kt narrows this
    // local for both `disabled` and `hidden`).
    val fieldEnabled = LocalActionUIEnabled.current
    TextField(
        value = query,
        onValueChange = update,
        enabled = fieldEnabled,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        singleLine = true,
        placeholder = config.prompt?.let { { M3Text(it) } },
        leadingIcon = { ChromeSymbolIcon("search", contentDescription = null) },
        trailingIcon = if (query.isNotEmpty()) {
            {
                IconButton(onClick = { update("") }, enabled = fieldEnabled) {
                    ChromeSymbolIcon("close", contentDescription = "Clear search")
                }
            }
        } else {
            null
        },
        shape = SearchBarDefaults.inputFieldShape,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = container,
            unfocusedContainerColor = container,
            disabledContainerColor = container,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
    )
}

/** A validated `searchable` declaration: a required [actionID] and an optional [prompt]. */
internal data class SearchableConfig(val actionID: String, val prompt: String?)

/**
 * Reads and validates the `searchable` property, the read-time mirror of Apple's
 * `validateProperties` searchable block (`View.swift`): a dictionary with a
 * non-empty String `actionID` (else the whole modifier is dropped with a warning)
 * and an optional String `prompt` (a present non-String prompt is dropped with a
 * warning, the rest kept). Returns null when absent or invalid, so the caller
 * falls through to the plain pipeline. Pure, so it is unit-testable.
 */
internal fun resolveSearchable(properties: JsonObject?, logger: ActionUILogger?): SearchableConfig? {
    val raw = properties?.get("searchable") ?: return null
    val obj = raw as? JsonObject ?: run {
        logger?.log(
            "Invalid type for searchable: expected dictionary, got ${raw::class.simpleName}, ignoring",
            LoggerLevel.warning,
        )
        return null
    }
    val actionID = (obj["actionID"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    if (actionID.isNullOrEmpty()) {
        logger?.log(
            "Invalid searchable: requires a non-empty String 'actionID', ignoring",
            LoggerLevel.warning,
        )
        return null
    }
    val promptElement = obj["prompt"]
    val prompt = when {
        promptElement == null || promptElement is JsonNull -> null
        promptElement is JsonPrimitive && promptElement.isString -> promptElement.content
        else -> {
            logger?.log("Invalid searchable.prompt: expected String, dropping prompt", LoggerLevel.warning)
            null
        }
    }
    return SearchableConfig(actionID, prompt)
}
