package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.DatePicker as M3DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text as M3Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.abracode.actionui.Helpers.DateHelper
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUILabelsHidden
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Date selection. Mirror of the Apple `DatePicker` element
 * (`ActionUI/Views/DatePicker.swift`), which wraps `SwiftUI.DatePicker` with
 * `displayedComponents: .date`. The first [ActionUIValueType.DATE]-valued control
 * on the value bridge (B6): its value is a [java.time.LocalDate], so a host reads
 * it with `ActionUIModel.getElementValueAsString` (ISO `yyyy-MM-dd`) and writes it
 * with `setElementValueFromString(..., "2024-07-16")`, and the control recomposes.
 *
 * Property mapping:
 *   * `title` - leading label (defaults to `"Date"`, matching Apple).
 *   * `selectedDate` - initial date as an ISO 8601 string (defaults to today);
 *     seeded into the element's `ViewModel` at populate time.
 *   * `displayStyle` - `"automatic"`/`"compact"` (default) render a tap-to-open
 *     [DatePickerDialog] field; `"graphical"` renders an inline calendar. The
 *     macOS-only `"stepperField"`/`"field"` warn-and-downgrade to compact (the
 *     same stance Apple's own renderer takes off macOS).
 *   * `range` - `{ "start": ISO, "end": ISO }`; constrains the selectable dates.
 *   * `valueChangeActionID` - dispatched through [ActionUIModel] on every user
 *     change, with the new date's ISO string as `context` (parity with Apple,
 *     which fires only on interaction, not on programmatic value changes).
 *
 * **State.** Bound to the element's `ViewModel` (via [LocalWindowModel] by id)
 * when a window is in scope; otherwise a local fallback. Host binding requires a
 * positive element `id`. Same dual-path binding the other controls use.
 *
 * **Deferred vs. Apple.** The `"graphical"` inline calendar embeds Material3's
 * own scrollers; inside a self-scrolling host it can hit Compose's nested
 * same-axis scroll limitation, so the safe default is the dialog field. The date
 * value is date-only (no time component), matching Apple's `.date`-only picker.
 */
object DatePicker : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.DATE

    override fun initialValue(element: ActionUIElement): Any? {
        val raw = element.properties?.stringProperty("selectedDate")
        return raw?.let { DateHelper.parseDate(it) } ?: LocalDate.now()
    }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = element.properties

        // SwiftUI `.labelsHidden()` (set here or on any ancestor).
        val title = if (LocalActionUILabelsHidden.current) "" else props?.stringProperty("title") ?: "Date"
        val actionID = props?.stringProperty("valueChangeActionID")
        val style = resolveDateStyle(props?.stringProperty("displayStyle"), logger)
        val bounds = parseDateBounds(props, logger)

        val initial = (initialValue(element) as? LocalDate) ?: LocalDate.now()
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localDate by remember(element.id) { mutableStateOf(initial) }
        val current: LocalDate = (viewModel?.value as? LocalDate) ?: localDate

        val onPick: (LocalDate) -> Unit = { picked ->
            if (picked != current && (bounds == null || bounds.contains(picked))) {
                if (viewModel != null) viewModel.value = picked else localDate = picked
                actionID?.let {
                    ActionUIModel.actionHandler(
                        it, viewID = element.id, viewPartID = 0, context = DateHelper.formatDate(picked),
                    )
                }
            }
        }

        when (style) {
            DatePickerStyle.Graphical -> GraphicalDatePicker(modifier, title, current, bounds, onPick)
            DatePickerStyle.Compact -> CompactDatePicker(modifier, title, current, bounds, onPick)
        }
    }
}

/** The DatePicker presentations the Android renderer supports. */
internal enum class DatePickerStyle { Compact, Graphical }

/**
 * Maps the JSON `displayStyle` to a [DatePickerStyle]. `null`/`"automatic"`/
 * `"compact"` -> [DatePickerStyle.Compact]; `"graphical"` -> inline calendar. The
 * macOS-only `"stepperField"`/`"field"` warn-and-downgrade to compact (parity with
 * Apple's own iOS/visionOS downgrade); any other value warns and falls back to
 * compact. Pure (logging aside) so it is unit-testable.
 */
internal fun resolveDateStyle(raw: String?, logger: ActionUILogger): DatePickerStyle = when (raw) {
    null, "automatic", "compact" -> DatePickerStyle.Compact
    "graphical" -> DatePickerStyle.Graphical
    "stepperField", "field" -> {
        logger.log("DatePicker displayStyle '$raw' is macOS-only; using compact on Android", LoggerLevel.warning)
        DatePickerStyle.Compact
    }
    else -> {
        logger.log("DatePicker displayStyle '$raw' is not recognized; using compact", LoggerLevel.warning)
        DatePickerStyle.Compact
    }
}

/** An inclusive selectable date range. */
internal data class DateBounds(val start: LocalDate, val end: LocalDate) {
    fun contains(date: LocalDate): Boolean = date >= start && date <= end
}

/**
 * Parses the `range` object (`{ "start": ISO, "end": ISO }`) into [DateBounds], or
 * `null` when absent or invalid (missing endpoint, unparseable, or start after
 * end). Warns on a malformed-but-present range, matching Apple's validator.
 */
internal fun parseDateBounds(props: JsonObject?, logger: ActionUILogger): DateBounds? {
    val range = props?.get("range") as? JsonObject ?: return null
    val startStr = range.stringProperty("start")
    val endStr = range.stringProperty("end")
    if (startStr == null || endStr == null) {
        logger.log("DatePicker range requires 'start' and 'end'; ignoring range", LoggerLevel.warning)
        return null
    }
    val start = DateHelper.parseDate(startStr)
    val end = DateHelper.parseDate(endStr)
    if (start == null || end == null || start > end) {
        logger.log("DatePicker range '$startStr'..'$endStr' is invalid; ignoring range", LoggerLevel.warning)
        return null
    }
    return DateBounds(start, end)
}

/** Tap-to-open dialog field: shows the current date, opens a [DatePickerDialog] on click. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CompactDatePicker(
    modifier: Modifier,
    title: String,
    current: LocalDate,
    bounds: DateBounds?,
    onPick: (LocalDate) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }

    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        if (title.isNotEmpty()) {
            M3Text(title)
            Spacer(Modifier.width(8.dp))
        }
        // SwiftUI `.disabled` (set here or on any ancestor) -> M3 `enabled`.
        OutlinedButton(onClick = { showDialog = true }, enabled = LocalActionUIEnabled.current) {
            M3Text(DateHelper.formatDate(current))
        }
    }

    if (showDialog) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = current.toUtcStartOfDayMillis(),
            yearRange = bounds?.let { it.start.year..it.end.year } ?: DatePickerDefaults.YearRange,
            selectableDates = bounds?.let { selectableDatesFor(it) } ?: DatePickerDefaults.AllDates,
        )
        DatePickerDialog(
            onDismissRequest = { showDialog = false },
            confirmButton = {
                TextButton(onClick = {
                    showDialog = false
                    state.selectedDateMillis?.let { onPick(it.toUtcLocalDate()) }
                }) { M3Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showDialog = false }) { M3Text("Cancel") }
            },
        ) {
            M3DatePicker(state = state)
        }
    }
}

/** Inline calendar. Pushes selection changes back through [onPick]. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GraphicalDatePicker(
    modifier: Modifier,
    title: String,
    current: LocalDate,
    bounds: DateBounds?,
    onPick: (LocalDate) -> Unit,
) {
    val state = rememberDatePickerState(
        initialSelectedDateMillis = current.toUtcStartOfDayMillis(),
        yearRange = bounds?.let { it.start.year..it.end.year } ?: DatePickerDefaults.YearRange,
        selectableDates = bounds?.let { selectableDatesFor(it) } ?: DatePickerDefaults.AllDates,
    )
    LaunchedEffect(state.selectedDateMillis) {
        state.selectedDateMillis?.let { onPick(it.toUtcLocalDate()) }
    }
    Column(modifier = modifier) {
        if (title.isNotEmpty()) M3Text(title)
        M3DatePicker(state = state, title = null, headline = null, showModeToggle = false)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
private fun selectableDatesFor(bounds: DateBounds): SelectableDates = object : SelectableDates {
    override fun isSelectableDate(utcTimeMillis: Long): Boolean = bounds.contains(utcTimeMillis.toUtcLocalDate())
    override fun isSelectableYear(year: Int): Boolean = year in bounds.start.year..bounds.end.year
}

/** Material3's DatePicker works in UTC start-of-day millis; convert at the boundary. */
private fun LocalDate.toUtcStartOfDayMillis(): Long =
    this.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

private fun Long.toUtcLocalDate(): LocalDate =
    Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()
