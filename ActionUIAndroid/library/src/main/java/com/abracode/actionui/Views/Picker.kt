package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUILabelsHidden
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Selection control over a list of options. Mirror of the Apple `Picker` element
 * (`ActionUI/Views/Picker.swift`), which wraps `SwiftUI.Picker`. Its **value is
 * the selected option's tag** (a String), so it rides the entry-17 state bridge
 * exactly like the other controls: a host reads the tag with
 * `ActionUIModel.getElementValue(...)` and sets it with
 * `setElementValueFromString(..., "<tag>")`, and the control recomposes.
 *
 * ## Styles - how the SwiftUI `pickerStyle` set maps to Compose
 *
 * | iOS `pickerStyle` | Android rendering |
 * |---|---|
 * | `menu` (default here) | Material3 [ExposedDropdownMenuBox] (a field that opens a dropdown; carries sections + dividers) |
 * | `segmented`           | [SingleChoiceSegmentedButtonRow] of [SegmentedButton]s |
 * | `radioGroup`          | a column (or row) of [RadioButton]s (+ `horizontalRadioGroupLayout`) |
 * | `wheel`               | **no Compose-native drum picker** -> warn and fall back to `menu` |
 *
 * `radioGroup`/`wheel` are single-platform on Apple (macOS / iOS respectively),
 * but `radioGroup` maps to a native Android control so it is supported (Android
 * adapts at runtime); `wheel` has no clean analog and is deferred.
 *
 * ## Options
 *
 * Two JSON shapes, parsed by [parsePickerOptions]:
 *   * `["One","Two"]` - titles only; tags auto-assigned `"1"`, `"2"`, ...
 *   * `[{"title":..,"tag":..}, ...]` - explicit tags, and optionally
 *     `{"section":"Name"}` headers and `{"divider":true}` separators (rendered in
 *     the `menu` style; flattened for segmented/radio).
 *
 * `actionID` is dispatched on every user selection with the new tag as `context`
 * (parity with the Apple binding setter, which fires only on user interaction).
 * State is ViewModel-backed under a [com.abracode.actionui.Common.WindowModel],
 * local [rememberSaveable] otherwise; host binding needs a positive `id`.
 */
object Picker : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? =
        parsePickerOptions(element.properties?.get("options"), logger = null)
            .flatMap { it.items }.firstOrNull()?.tag

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val sections = parsePickerOptions(props?.get("options"), logger)
        val items = sections.flatMap { it.items }
        val initial = items.firstOrNull()?.tag ?: ""
        // SwiftUI `.labelsHidden()` (set here or on any ancestor): no label on
        // any style - menu field label, segmented/radio heading.
        val title = if (LocalActionUILabelsHidden.current) "" else props?.stringProperty("title") ?: ""
        val actionID = props?.stringProperty("actionID")
        val style = resolvePickerStyle(props?.stringProperty("pickerStyle"), logger)

        // Bind to the ViewModel value when a window is in scope; else local state.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localTag by rememberSaveable(element.id) { mutableStateOf(initial) }
        val selectedTag = if (viewModel != null) (viewModel.value as? String) ?: initial else localTag

        val onSelect: (String) -> Unit = { tag ->
            if (tag != selectedTag) {
                if (viewModel != null) viewModel.value = tag else localTag = tag
                if (actionID != null) {
                    ActionUIModel.actionHandler(actionID, viewID = element.id, viewPartID = 0, context = tag)
                }
            }
        }

        when (style) {
            PickerStyle.Menu ->
                PickerMenu(title, sections, selectedTag, onSelect, modifier)
            PickerStyle.Segmented ->
                TitledControl(title, modifier) { PickerSegmented(items, selectedTag, onSelect) }
            PickerStyle.RadioGroup -> {
                val horizontal = props?.booleanProperty("horizontalRadioGroupLayout") ?: false
                TitledControl(title, modifier) { PickerRadioGroup(items, selectedTag, onSelect, horizontal) }
            }
        }
    }
}

/** A single selectable option: [title] is shown, [tag] is the stored value. */
internal data class PickerOption(val title: String, val tag: String)

/** A group of [items] under an optional [title] header (menu style only). */
internal data class PickerSection(val title: String?, val items: List<PickerOption>)

/** The Picker layouts the Android renderer supports. */
internal enum class PickerStyle { Menu, Segmented, RadioGroup }

/**
 * Maps the JSON `pickerStyle` to a [PickerStyle]. `null` defaults to [PickerStyle.Menu]
 * (the most general, compact layout). `"wheel"` (no Compose drum picker) and any
 * unrecognized value warn and fall back to menu - the warn-and-fallback stance
 * used for unsupported Toggle/shape style variants.
 */
internal fun resolvePickerStyle(raw: String?, logger: ActionUILogger): PickerStyle = when (raw) {
    null, "menu" -> PickerStyle.Menu
    "segmented" -> PickerStyle.Segmented
    "radioGroup" -> PickerStyle.RadioGroup
    "wheel" -> {
        logger.log("Picker style 'wheel' has no Compose equivalent on Android; using menu", LoggerLevel.warning)
        PickerStyle.Menu
    }
    else -> {
        logger.log("Picker style '$raw' is not recognized; using menu", LoggerLevel.warning)
        PickerStyle.Menu
    }
}

/**
 * Parses the `options` JSON into sections, mirroring the Apple
 * `Picker.extractSections`:
 *   * an array of string primitives -> one ungrouped section, tags `"1".."n"`.
 *   * an array of objects -> items `{title, tag}` (both required and non-empty,
 *     else warn-and-skip), split into sections by `{section:"Name"}` headers and
 *     `{divider:true}` separators (a divider starts a new untitled section).
 *
 * [logger] is nullable so the initial-value path can parse without emitting
 * warnings (the visible render path passes a real logger). Returns an empty list
 * for a missing or non-array `options`.
 */
internal fun parsePickerOptions(element: JsonElement?, logger: ActionUILogger?): List<PickerSection> {
    val array = element as? JsonArray ?: run {
        if (element != null) {
            logger?.log("Picker 'options' must be an array of strings or {title, tag} objects", LoggerLevel.warning)
        }
        return emptyList()
    }

    // Format 1: simple array of strings -> single ungrouped section.
    if (array.isNotEmpty() && array.all { it is JsonPrimitive && it.isString }) {
        val items = array.mapIndexed { index, el ->
            PickerOption(title = (el as JsonPrimitive).content, tag = (index + 1).toString())
        }
        return listOf(PickerSection(title = null, items = items))
    }

    // Format 2: array of objects, possibly with section/divider entries.
    val sections = mutableListOf<PickerSection>()
    var currentTitle: String? = null
    var currentItems = mutableListOf<PickerOption>()
    var hasSections = false

    fun flush() {
        // Avoid creating an empty leading section (matches the Apple flush guard).
        if (currentItems.isNotEmpty() || sections.isNotEmpty()) {
            sections.add(PickerSection(currentTitle, currentItems))
            currentItems = mutableListOf()
        }
    }

    array.forEachIndexed { index, el ->
        val obj = el as? JsonObject
        if (obj == null) {
            logger?.log("Picker options[$index] is not an object; skipping", LoggerLevel.warning)
            return@forEachIndexed
        }
        if (obj.booleanProperty("divider") == true) {
            hasSections = true
            flush()
            currentTitle = null
            return@forEachIndexed
        }
        val section = obj.stringProperty("section")
        if (section != null) {
            hasSections = true
            flush()
            currentTitle = section
            return@forEachIndexed
        }
        val title = obj.stringProperty("title")
        if (title.isNullOrEmpty()) {
            logger?.log("Picker options[$index] missing valid 'title'; skipping", LoggerLevel.warning)
            return@forEachIndexed
        }
        val tag = obj.stringProperty("tag")
        if (tag.isNullOrEmpty()) {
            logger?.log("Picker options[$index] missing valid 'tag'; skipping", LoggerLevel.warning)
            return@forEachIndexed
        }
        currentItems.add(PickerOption(title, tag))
    }

    return if (hasSections) {
        sections.add(PickerSection(currentTitle, currentItems))
        sections
    } else {
        listOf(PickerSection(title = null, items = currentItems))
    }
}

/** Wraps a control with an optional leading [title] header (segmented / radio). */
@Composable
private fun TitledControl(title: String, modifier: Modifier, content: @Composable () -> Unit) {
    Column(modifier) {
        if (title.isNotEmpty()) {
            M3Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(bottom = 4.dp),
            )
        }
        content()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickerMenu(
    title: String,
    sections: List<PickerSection>,
    selectedTag: String,
    onSelect: (String) -> Unit,
    modifier: Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedTitle = sections.flatMap { it.items }.firstOrNull { it.tag == selectedTag }?.title ?: ""

    // SwiftUI `.disabled` (set here or on any ancestor): gray the anchor field
    // and refuse to open the menu.
    val enabled = LocalActionUIEnabled.current
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { if (enabled) expanded = it },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = selectedTitle,
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = if (title.isNotEmpty()) ({ M3Text(title) }) else null,
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            sections.forEachIndexed { sectionIndex, section ->
                if (sectionIndex > 0) HorizontalDivider()
                if (!section.title.isNullOrEmpty()) {
                    M3Text(
                        section.title,
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                section.items.forEach { item ->
                    DropdownMenuItem(
                        text = { M3Text(item.title) },
                        onClick = {
                            onSelect(item.tag)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickerSegmented(
    items: List<PickerOption>,
    selectedTag: String,
    onSelect: (String) -> Unit,
) {
    val enabled = LocalActionUIEnabled.current
    SingleChoiceSegmentedButtonRow {
        items.forEachIndexed { index, item ->
            SegmentedButton(
                selected = item.tag == selectedTag,
                onClick = { onSelect(item.tag) },
                enabled = enabled,
                shape = SegmentedButtonDefaults.itemShape(index = index, count = items.size),
            ) {
                M3Text(item.title)
            }
        }
    }
}

@Composable
private fun PickerRadioGroup(
    items: List<PickerOption>,
    selectedTag: String,
    onSelect: (String) -> Unit,
    horizontal: Boolean,
) {
    val enabled = LocalActionUIEnabled.current
    val options: @Composable () -> Unit = {
        items.forEach { item ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .selectable(
                        selected = item.tag == selectedTag,
                        enabled = enabled,
                        onClick = { onSelect(item.tag) }
                    )
                    .padding(end = 12.dp),
            ) {
                RadioButton(
                    selected = item.tag == selectedTag,
                    onClick = { onSelect(item.tag) },
                    enabled = enabled,
                )
                M3Text(item.title)
            }
        }
    }
    if (horizontal) Row { options() } else Column { options() }
}
