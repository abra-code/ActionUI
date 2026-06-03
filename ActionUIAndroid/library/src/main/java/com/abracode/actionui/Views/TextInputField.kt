package com.abracode.actionui.Views

import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Which flavor of text input to render. [Plain] is the analog of Apple's
 * `TextField`; [Secure] of `SecureField` (masked input).
 */
internal enum class TextInputKind { Plain, Secure }

/**
 * Shared renderer for the two single-value text-input elements, the Android
 * counterpart of the work Apple shares through `TextFieldFocusContainer.swift`.
 * [TextField] and [SecureField] are thin builders over this, mirroring how the
 * shape elements share [ShapeView].
 *
 * Both fields map onto a Material3 [OutlinedTextField] - the closest Material
 * analog to the bordered/rounded style SwiftUI uses by default - with:
 *
 *   * `title`  -> floating label (SwiftUI's Form/LabeledContent label).
 *   * `prompt` -> placeholder shown while empty.
 *   * `text`   -> initial value (for [Plain], also falls back to a stringified
 *     `value` so format-authored JSON still shows something - see deferral note).
 *   * `actionID` -> dispatched through [ActionUIModel] on keyboard submit
 *     (the IME "Done" action), matching SwiftUI's `onSubmit`.
 *   * `valueChangeActionID` -> dispatched on every text change, matching the
 *     Apple binding's `set` closure.
 *
 * [Plain] additionally honors `axis: "vertical"` (multi-line, growing) and
 * `lineLimit` (exact `N` or `{min?, max?}`); [Secure] is always single-line and
 * masks input with a [PasswordVisualTransformation].
 *
 * **State.** The current value is held in local [rememberSaveable] state keyed by
 * the element id, so it survives recomposition and configuration changes. Apple's
 * programmatic `getElementValue`/`setElementValue` runtime bridge is not ported
 * yet (Android has no `ViewModel`/state layer - see
 * `Private/Android_Porting_Notes.md` section 6), so the value lives only in the
 * composition for now, the same Phase-1 stance `ProgressView`/`Image` take.
 *
 * **Deferred vs. Apple.** For [Plain], numeric `format`/`fractionLength`/
 * `currencyCode` (Apple's `NumberFormatHelper`) are not ported; such a field
 * renders as plain text and any `value` is shown as its string form. For both,
 * `textContentType` (an iOS autofill hint) has no portable Compose equivalent and
 * is ignored after validation, consistent with the resolver's "unrecognized
 * properties are ignored" rule.
 */
@Composable
internal fun TextInputField(
    element: ActionUIElement,
    modifier: Modifier,
    kind: TextInputKind,
) {
    val props = element.properties
    val logger = LocalActionUILogger.current

    val title = props?.stringProperty("title") ?: ""
    val prompt = props?.stringProperty("prompt")
    val actionID = props?.stringProperty("actionID")
    val valueChangeActionID = props?.stringProperty("valueChangeActionID")

    // Initial value: "text" wins; for plain fields a stringified "value" is the
    // fallback so format-authored JSON still shows its number (formatting itself
    // is deferred). Secure fields only honor "text".
    val initialValue = props?.stringProperty("text")
        ?: (props?.get("value")?.jsonPrimitive?.contentOrNull?.takeIf { kind == TextInputKind.Plain })
        ?: ""

    // textContentType is an iOS autofill hint with no portable Compose mapping;
    // validate the Secure vocabulary (parity with the Apple side) then ignore.
    props?.stringProperty("textContentType")?.let { type ->
        if (kind == TextInputKind.Secure &&
            type !in setOf("password", "newPassword", "oneTimeCode")
        ) {
            logger.log(
                "SecureField textContentType must be 'password', 'newPassword', " +
                    "or 'oneTimeCode'; ignoring '$type'",
                LoggerLevel.warning
            )
        }
    }

    val isVertical = kind == TextInputKind.Plain && props?.let { p ->
        p.stringProperty("axis")?.let { axis ->
            if (axis != "vertical" && axis != "horizontal") {
                logger.log(
                    "TextField axis must be \"vertical\" or \"horizontal\"; ignoring '$axis'",
                    LoggerLevel.warning
                )
            }
            axis == "vertical"
        }
    } == true

    val (minLines, maxLines) =
        if (isVertical) parseLineLimit(props?.get("lineLimit")) else 1 to 1

    var text by rememberSaveable(element.id) { mutableStateOf(initialValue) }

    val keyboardType = if (kind == TextInputKind.Secure) KeyboardType.Password else KeyboardType.Text
    val visualTransformation =
        if (kind == TextInputKind.Secure) PasswordVisualTransformation() else VisualTransformation.None

    val dispatch: (String?) -> Unit = { id ->
        if (id != null) ActionUIModel.actionHandler(id, viewID = element.id, viewPartID = 0)
    }

    OutlinedTextField(
        value = text,
        onValueChange = { new ->
            if (new != text) {
                text = new
                dispatch(valueChangeActionID)
            }
        },
        modifier = modifier,
        label = if (title.isNotEmpty()) ({ M3Text(title) }) else null,
        placeholder = prompt?.let { { M3Text(it) } },
        singleLine = !isVertical,
        minLines = minLines,
        maxLines = maxLines,
        visualTransformation = visualTransformation,
        keyboardOptions = KeyboardOptions(
            keyboardType = keyboardType,
            imeAction = if (isVertical) ImeAction.Default else ImeAction.Done,
        ),
        keyboardActions = KeyboardActions(onDone = { dispatch(actionID) }),
    )
}

/**
 * Resolves a `lineLimit` property into Compose `(minLines, maxLines)`.
 *
 *   * exact `N`        -> `(1, N)`  (cap at N lines, like SwiftUI `.lineLimit(N)`).
 *   * `{min, max}`     -> `(min, max)`.
 *   * `{min}`          -> `(min, MAX_VALUE)` (grows without an upper bound).
 *   * `{max}`          -> `(1, max)`.
 *   * absent / invalid -> `(1, MAX_VALUE)` (the OutlinedTextField default range).
 */
private fun parseLineLimit(element: JsonElement?): Pair<Int, Int> {
    if (element == null) return 1 to Int.MAX_VALUE
    (element as? JsonPrimitive)?.intOrNull?.let { exact -> return 1 to exact }
    (element as? JsonObject)?.let { obj ->
        val min = (obj["min"] as? JsonPrimitive)?.intOrNull ?: 1
        val max = (obj["max"] as? JsonPrimitive)?.intOrNull ?: Int.MAX_VALUE
        return min to max
    }
    return 1 to Int.MAX_VALUE
}
