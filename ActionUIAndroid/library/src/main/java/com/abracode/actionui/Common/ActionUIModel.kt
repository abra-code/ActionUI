package com.abracode.actionui.Common

import androidx.compose.ui.graphics.Color
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.DateHelper
import com.abracode.actionui.Helpers.DescriptionLoad
import com.abracode.actionui.Helpers.colorToHex
import com.abracode.actionui.Helpers.coordinateToJson
import com.abracode.actionui.Helpers.decodeDescription
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.parseCoordinate
import kotlinx.serialization.json.Json
import java.time.LocalDate

/**
 * Signature of an ActionUI action handler.
 *
 * Mirror of the Swift closure type `(String, String, Int, Int, Any?) -> Void`
 * used by `ActionUIModel` in `ActionUI/Common/ActionUIModel.swift`. The
 * parameters, in order:
 *
 *   * `actionID`   - the identifier that triggered the handler.
 *   * `windowUUID` - the window the action originated from. The Android port is
 *     currently single-window, so this is the empty string until multi-window
 *     support is ported; the parameter is kept so the contract matches Apple.
 *   * `viewID`     - the `id` of the element that fired the action (0 if none).
 *   * `viewPartID` - sub-element index (e.g. table row/column); 0 for simple controls.
 *   * `context`    - optional payload supplied by the firing element.
 */
typealias ActionUIActionHandler =
    (actionID: String, windowUUID: String, viewID: Int, viewPartID: Int, context: Any?) -> Unit

/**
 * Global registry and dispatcher for ActionUI actions.
 *
 * Mirror of the action-handling surface of the Swift `ActionUIModel` singleton
 * (`ActionUI/Common/ActionUIModel.swift`). Client code registers handlers for
 * specific `actionID`s (or one catch-all default handler); JSON-described
 * controls such as [com.abracode.actionui.Views.Button] invoke
 * [actionHandler] when tapped, which routes to the matching handler or the
 * default.
 *
 * Implemented as a Kotlin `object` (singleton) to match Swift's
 * `ActionUIModel.shared`. Beyond action dispatch, this object owns the
 * per-window [WindowModel] pool ([windowModels]) and the programmatic value /
 * state bridge (`get/setElementValue[FromString]`,
 * `get/setElementState[FromString]`) - the Android port of the corresponding
 * Swift surface. `ActionUI.Render` registers a window via [loadDescription];
 * host code then reads and writes control values out-of-band (typically from an
 * action handler), and because [ViewModel] fields are Compose snapshot state
 * those writes recompose the affected control automatically.
 *
 * The data-driven rows API (`get/set/append/clearElementRows`,
 * `getElementColumnCount`) is ported (it drives `List` / `Section` template
 * mode). Window-level presentation is ported: **dialogs** (`presentAlert` /
 * `presentConfirmationDialog` / `dismissDialog`) and **modals** (`presentModal` /
 * `dismissModal`, sheet / fullScreenCover). Still **not** ported (with the features
 * that drive them): runtime structural mutation (`insertElement` / `removeElement`
 * / `insertRow`) and the property API (`get/setElementProperty`, which awaits a
 * validation stage). See `Private/Android_Porting_Notes.md`.
 *
 * Handlers and the value/state API run on the main thread (Compose `onClick`
 * callbacks and host handlers); this object performs no synchronization of its
 * own.
 */
object ActionUIModel {

    /**
     * The `states` key under which the data-driven containers (`List`, `Section`)
     * hold their rows, as `List<List<String>>`. Matches the Swift
     * `states["content"]` convention so the rows API and the renderers agree.
     */
    const val ROWS_STATE_KEY = "content"

    /** Registered handlers for specific actionIDs. */
    private val actionHandlers = mutableMapOf<String, ActionUIActionHandler>()

    /** Fallback handler invoked for any actionID with no specific handler. */
    private var defaultActionHandler: ActionUIActionHandler? = null

    /**
     * Logger for action-dispatch diagnostics. Defaults to [ConsoleLogger];
     * client code may assign a different [ActionUILogger]. Matches the public
     * `logger` property on the Swift `ActionUIModel`.
     */
    var logger: ActionUILogger = ConsoleLogger()

    /** Decoder for modal sub-documents passed to [presentModal] (shared config; see [ActionUIJson]). */
    private val json: Json = ActionUIJson

    /**
     * Registers [handler] for [actionID], replacing any existing handler for
     * that id.
     */
    fun registerActionHandler(actionID: String, handler: ActionUIActionHandler) {
        actionHandlers[actionID] = handler
        logger.log("Registered handler for actionID: $actionID", LoggerLevel.verbose)
    }

    /** Removes the handler registered for [actionID], if any. */
    fun unregisterActionHandler(actionID: String) {
        actionHandlers.remove(actionID)
        logger.log("Unregistered handler for actionID: $actionID", LoggerLevel.verbose)
    }

    /** Sets the catch-all handler used when no specific handler matches. */
    fun setDefaultActionHandler(handler: ActionUIActionHandler) {
        defaultActionHandler = handler
        logger.log("Set default action handler", LoggerLevel.verbose)
    }

    /** Removes the catch-all default handler. */
    fun removeDefaultActionHandler() {
        defaultActionHandler = null
        logger.log("Removed default action handler", LoggerLevel.verbose)
    }

    /**
     * Dispatches [actionID] to its registered handler, falling back to the
     * default handler, and finally warning if neither is set. Mirrors the Swift
     * `actionHandler(_:windowUUID:viewID:viewPartID:context:)` resolution order.
     */
    fun actionHandler(
        actionID: String,
        windowUUID: String = "",
        viewID: Int,
        viewPartID: Int = 0,
        context: Any? = null
    ) {
        val handler = actionHandlers[actionID]
        // Snapshot the mutable property into a local val so it smart-casts to
        // non-null (a `var` member can't) and can't be nulled out by another
        // thread between the check and the call.
        val default = defaultActionHandler
        when {
            handler != null -> {
                logger.log("Executing handler for actionID: $actionID, viewID: $viewID", LoggerLevel.debug)
                handler(actionID, windowUUID, viewID, viewPartID, context)
            }
            default != null -> {
                logger.log("Executing default handler for actionID: $actionID, viewID: $viewID", LoggerLevel.debug)
                default(actionID, windowUUID, viewID, viewPartID, context)
            }
            else -> {
                logger.log(
                    "No handler registered for actionID '$actionID' and no default handler set",
                    LoggerLevel.warning
                )
            }
        }
    }

    // MARK: - Window registry

    /**
     * The per-window [WindowModel] pool, keyed by `windowUUID`. Android is
     * single-window today, so in practice this holds one entry under the empty
     * string (see the [ActionUIActionHandler] note on `windowUUID`).
     */
    internal val windowModels = mutableMapOf<String, WindowModel>()

    /**
     * Adopts [root] as the description for [windowUUID]: builds (or rebuilds) the
     * window's [WindowModel] and [ViewModel] pool and registers it so the value /
     * state API can resolve element ids. Mirrors the Swift
     * `loadDescription(from:windowUUID:)`. `ActionUI.Render` calls this once per
     * document. Returns the populated [WindowModel].
     */
    fun loadDescription(
        root: ActionUIElement,
        windowUUID: String = "",
        logger: ActionUILogger = this.logger,
    ): WindowModel {
        val windowModel = WindowModel(windowUUID, logger)
        windowModel.loadDescription(root)
        windowModels[windowUUID] = windowModel
        return windowModel
    }

    /**
     * Removes [windowUUID]'s [WindowModel] from the pool. Called when a rendered
     * window leaves the composition. The optional [expected] guard avoids
     * evicting a newer window that replaced this one under the same id.
     */
    fun unregisterWindow(windowUUID: String, expected: WindowModel? = null) {
        if (expected != null && windowModels[windowUUID] !== expected) return
        windowModels.remove(windowUUID)
    }

    // MARK: - Window-level dialogs (alert / confirmationDialog)
    //
    // The Android port of the Swift `presentAlert` / `presentConfirmationDialog` /
    // `dismissDialog` surface. These set [WindowModel.windowDialog] (Compose
    // snapshot state), which the window's [com.abracode.actionui.Helpers.WindowDialogHost]
    // observes and renders as a Material3 AlertDialog. The host fires each button's
    // actionID (if any) and then dismisses. The sheet / fullScreenCover modal half
    // (`presentModal` / `dismissModal`) is not ported yet.

    /**
     * Presents a system alert over [windowUUID]'s window. Defaults to a single
     * dismissing "OK" button. No-op (with an error log) when no window is
     * registered for [windowUUID]. Mirrors the Swift `presentAlert`.
     */
    fun presentAlert(
        windowUUID: String = "",
        title: String,
        message: String? = null,
        buttons: List<DialogButton> = listOf(DialogButton("OK", DialogButtonRole.CANCEL)),
    ) {
        val windowModel = windowModels[windowUUID]
        if (windowModel == null) {
            logger.log("presentAlert: No WindowModel for windowUUID: $windowUUID", LoggerLevel.error)
            return
        }
        windowModel.windowDialog = WindowDialog(DialogStyle.ALERT, title, message, buttons)
        logger.log("presentAlert: '$title' for windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /**
     * Presents a confirmation dialog (iOS action sheet) over [windowUUID]'s window.
     * No-op (with an error log) when no window is registered for [windowUUID].
     * Mirrors the Swift `presentConfirmationDialog`.
     */
    fun presentConfirmationDialog(
        windowUUID: String = "",
        title: String,
        message: String? = null,
        buttons: List<DialogButton>,
    ) {
        val windowModel = windowModels[windowUUID]
        if (windowModel == null) {
            logger.log("presentConfirmationDialog: No WindowModel for windowUUID: $windowUUID", LoggerLevel.error)
            return
        }
        windowModel.windowDialog = WindowDialog(DialogStyle.CONFIRMATION_DIALOG, title, message, buttons)
        logger.log("presentConfirmationDialog: '$title' for windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /**
     * Dismisses the active alert / confirmation dialog without firing any action.
     * The dialog host normally calls this for you after a button tap (and on a
     * scrim / back dismiss). Mirrors the Swift `dismissDialog`.
     */
    fun dismissDialog(windowUUID: String = "") {
        val windowModel = windowModels[windowUUID] ?: return
        windowModel.windowDialog = null
        logger.log("dismissDialog: windowUUID: $windowUUID", LoggerLevel.debug)
    }

    // MARK: - Window-level modals (sheet / fullScreenCover)
    //
    // The Android port of the Swift `presentModal` / `dismissModal` surface. Unlike
    // a dialog (pure data), a modal loads a JSON sub-document, merges its ViewModels
    // into the window pool, and removes exactly those on dismiss. These set
    // [WindowModel.windowModal] (Compose snapshot state), which the window's
    // [com.abracode.actionui.Helpers.WindowModalHost] renders as a ModalBottomSheet
    // (sheet) or a full-screen Dialog (fullScreenCover).

    /**
     * Loads [jsonString] as a sub-document and presents it as a [style] modal over
     * [windowUUID]'s window. The modal's [ViewModel]s are registered in the window
     * pool (so the value / state API reaches its controls) and removed on dismiss;
     * [onDismissActionID] fires once when it closes. No-op (with an error log) when
     * no window is registered or the document fails to decode. Mirrors the Swift
     * `presentModal`.
     */
    fun presentModal(
        windowUUID: String = "",
        jsonString: String,
        style: ModalStyle,
        onDismissActionID: String? = null,
    ) {
        val windowModel = windowModels[windowUUID]
        if (windowModel == null) {
            logger.log("presentModal: No WindowModel for windowUUID: $windowUUID", LoggerLevel.error)
            return
        }
        val element = when (val loaded = decodeDescription(jsonString, json, logger)) {
            is DescriptionLoad.Loaded -> loaded.element
            else -> {
                logger.log("presentModal: could not decode modal description for windowUUID: $windowUUID", LoggerLevel.error)
                return
            }
        }
        val loadedViewIDs = windowModel.loadModalDescription(element)
        windowModel.windowModal = WindowModal(element, style, onDismissActionID, loadedViewIDs)
        logger.log("presentModal: presenting $style for windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /**
     * Dismisses the active sheet / fullScreenCover: removes the [ViewModel]s the
     * modal added to the window pool, clears it, and fires its `onDismissActionID`
     * (if any). The modal host calls this on a button action or a scrim / back
     * dismiss. Mirrors the Swift `dismissModal`.
     */
    fun dismissModal(windowUUID: String = "") {
        val windowModel = windowModels[windowUUID] ?: return
        val modal = windowModel.windowModal ?: return
        windowModel.viewModels.keys.removeAll(modal.loadedViewIDs)
        windowModel.windowModal = null
        modal.onDismissActionID?.let {
            actionHandler(actionID = it, windowUUID = windowUUID, viewID = 0, viewPartID = 0, context = null)
        }
        logger.log("dismissModal: windowUUID: $windowUUID", LoggerLevel.debug)
    }

    // MARK: - Element Value API

    /** Resolves a [ViewModel], logging a warning and returning null if absent. */
    private fun viewModel(windowUUID: String, viewID: Int): ViewModel? {
        val viewModel = windowModels[windowUUID]?.viewModels?.get(viewID)
        if (viewModel == null) {
            logger.log("No ViewModel found for windowUUID: $windowUUID, viewID: $viewID", LoggerLevel.warning)
        }
        return viewModel
    }

    /**
     * Returns the current value of the element [viewID] in [windowUUID], or null
     * if the element is unknown. [viewPartID] is accepted for parity with the
     * Apple multi-column (Table/List) path, which is not ported; for the scalar
     * controls that exist today the value is returned directly.
     */
    fun getElementValue(windowUUID: String = "", viewID: Int, viewPartID: Int = 0): Any? =
        viewModel(windowUUID, viewID)?.value

    /**
     * Sets the value of element [viewID] in [windowUUID]. Because [ViewModel.value]
     * is Compose snapshot state, a bound control recomposes to reflect the new
     * value. The Apple `[[String]]` / `[String]` Table/List content branches are
     * deferred with those elements; this is the scalar path.
     */
    fun setElementValue(windowUUID: String = "", viewID: Int, viewPartID: Int = 0, value: Any) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        viewModel.value = value
        logger.log("Set value for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /**
     * Returns the element's value as a string for scripting, formatted by the
     * element's declared [ActionUIValueType]. String values are returned directly;
     * other types use their canonical string form (a [ActionUIValueType.DATE] as
     * ISO `yyyy-MM-dd`, a [ActionUIValueType.COLOR] as `#RRGGBB`/`#RRGGBBAA`, a
     * [ActionUIValueType.STRING_LIST] tab-joined, a [ActionUIValueType.COORDINATE]
     * as `{"latitude": N, "longitude": N}` JSON); null value yields null. Mirrors
     * the Swift `getElementValueAsString` (the `[[String]]` Table join is
     * deferred with that value type).
     */
    fun getElementValueAsString(windowUUID: String = "", viewID: Int, viewPartID: Int = 0): String? {
        val viewModel = viewModel(windowUUID, viewID) ?: return null
        val value = viewModel.value ?: return null
        val valueType = ActionUIRegistry.lookup(viewModel.elementType)?.valueType ?: ActionUIValueType.NONE
        return when {
            value is String -> value
            valueType == ActionUIValueType.BOOLEAN && value is Boolean -> value.toString()
            valueType == ActionUIValueType.INT && value is Int -> value.toString()
            valueType == ActionUIValueType.DOUBLE && value is Double -> value.toString()
            valueType == ActionUIValueType.DATE && value is LocalDate -> DateHelper.formatDate(value)
            valueType == ActionUIValueType.COLOR && value is Color -> colorToHex(value)
            valueType == ActionUIValueType.STRING_LIST && value is List<*> ->
                value.joinToString("\t") { it?.toString() ?: "" }
            valueType == ActionUIValueType.COORDINATE && value is ActionUICoordinate ->
                coordinateToJson(value)
            else -> value.toString()
        }
    }

    /**
     * Parses [value] into the element's declared [ActionUIValueType] and delegates
     * to [setElementValue]. Warns and does nothing on a malformed string, on a
     * [ActionUIValueType.NONE] (valueless) element, or on an unknown element.
     * Mirrors the Swift `setElementValueFromString`.
     */
    fun setElementValueFromString(windowUUID: String = "", viewID: Int, viewPartID: Int = 0, value: String) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val valueType = ActionUIRegistry.lookup(viewModel.elementType)?.valueType ?: ActionUIValueType.NONE
        val converted: Any = when (valueType) {
            ActionUIValueType.STRING -> value
            ActionUIValueType.BOOLEAN -> when (value.lowercase()) {
                "true" -> true
                "false" -> false
                else -> {
                    logger.log("Invalid string for Boolean value: $value for viewID: $viewID", LoggerLevel.warning)
                    return
                }
            }
            ActionUIValueType.INT -> value.toIntOrNull() ?: run {
                logger.log("Invalid string for Int value: $value for viewID: $viewID", LoggerLevel.warning)
                return
            }
            ActionUIValueType.DOUBLE -> value.toDoubleOrNull() ?: run {
                logger.log("Invalid string for Double value: $value for viewID: $viewID", LoggerLevel.warning)
                return
            }
            ActionUIValueType.DATE -> DateHelper.parseDate(value) ?: run {
                logger.log("Invalid ISO 8601 date string: $value for viewID: $viewID", LoggerLevel.warning)
                return
            }
            ActionUIValueType.COLOR -> parseColor(value) ?: run {
                logger.log("Invalid color string: $value for viewID: $viewID", LoggerLevel.warning)
                return
            }
            // Tab-separated, matching Apple's `[String]` parse (empty fields dropped).
            ActionUIValueType.STRING_LIST -> value.split("\t").filter { it.isNotEmpty() }
            ActionUIValueType.COORDINATE -> parseCoordinate(value) ?: run {
                logger.log("Invalid coordinate JSON string: $value for viewID: $viewID", LoggerLevel.warning)
                return
            }
            ActionUIValueType.NONE -> {
                logger.log(
                    "Element of type ${viewModel.elementType} has no value and does not support " +
                        "setElementValueFromString (viewID: $viewID)",
                    LoggerLevel.warning
                )
                return
            }
        }
        setElementValue(windowUUID = windowUUID, viewID = viewID, viewPartID = viewPartID, value = converted)
    }

    // MARK: - Element State API

    /** Returns the value for state [key] on [viewID], or null if absent. */
    fun getElementState(windowUUID: String = "", viewID: Int, key: String): Any? {
        val viewModel = viewModel(windowUUID, viewID) ?: return null
        val value = viewModel.states[key]
        if (value == null) {
            logger.log("State key '$key' not found for viewID: $viewID", LoggerLevel.warning)
        }
        return value
    }

    /** Returns the string form of state [key] on [viewID], or null if absent. */
    fun getElementStateAsString(windowUUID: String = "", viewID: Int, key: String): String? {
        val viewModel = viewModel(windowUUID, viewID) ?: return null
        val value = viewModel.states[key]
        if (value == null) {
            logger.log("State key '$key' not found for viewID: $viewID", LoggerLevel.warning)
            return null
        }
        return when (value) {
            is Boolean -> value.toString()
            is Double -> value.toString()
            is Float -> value.toString()
            is Int -> value.toString()
            is String -> value
            else -> value.toString()
        }
    }

    /**
     * Sets state [key] on [viewID] to [value]. Rejects a change that would alter
     * the type of an existing key (logs an error) so [setElementStateFromString]'s
     * type-guided parsing stays sound. Mirrors the Swift `setElementState`.
     */
    fun setElementState(windowUUID: String = "", viewID: Int, key: String, value: Any) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val existing = viewModel.states[key]
        if (existing != null && existing::class != value::class) {
            logger.log(
                "Type mismatch for state key '$key' on viewID: $viewID; expected " +
                    "${existing::class.simpleName}, got ${value::class.simpleName}",
                LoggerLevel.error
            )
            return
        }
        viewModel.states[key] = value
        logger.log("Set state '$key' for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /**
     * Parses [value] into the type of the existing state [key] and stores it. If
     * the key does not exist yet the string is stored as-is. Mirrors the Swift
     * `setElementStateFromString`; the Apple new-key JSON type inference
     * (`looksLikeJSONFragment` / `normalizedJSONValue`) is deferred - new keys
     * land as plain strings until a typed setter establishes their type.
     */
    fun setElementStateFromString(windowUUID: String = "", viewID: Int, key: String, value: String) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val converted: Any = when (val existing = viewModel.states[key]) {
            null -> value // New key: store as-is (JSON type inference deferred).
            is Boolean -> when (value.lowercase()) {
                "true" -> true
                "false" -> false
                else -> {
                    logger.log("Invalid string for Boolean state key '$key': $value", LoggerLevel.warning)
                    return
                }
            }
            is Double -> value.toDoubleOrNull() ?: run {
                logger.log("Invalid string for Double state key '$key': $value", LoggerLevel.warning)
                return
            }
            is Float -> value.toFloatOrNull() ?: run {
                logger.log("Invalid string for Float state key '$key': $value", LoggerLevel.warning)
                return
            }
            is Int -> value.toIntOrNull() ?: run {
                logger.log("Invalid string for Int state key '$key': $value", LoggerLevel.warning)
                return
            }
            is String -> value
            else -> {
                logger.log(
                    "Unsupported state type ${existing::class.simpleName} for key '$key' on viewID: $viewID",
                    LoggerLevel.warning
                )
                return
            }
        }
        viewModel.states[key] = converted
        logger.log("Set state '$key' from string for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    // MARK: - Element Rows API (data-driven List / Section)

    /**
     * Reads element [viewID]'s rows from `states[`[ROWS_STATE_KEY]`]` as
     * `List<List<String>>`, or an empty list when unset or of an unexpected
     * shape. Mirrors the Swift `getElementRows`. The rows back `List` / `Section`
     * template (and `List` homogeneous) mode; because [ViewModel.states] is
     * Compose snapshot state, a renderer reading these rows recomposes when they
     * change.
     */
    @Suppress("UNCHECKED_CAST")
    fun getElementRows(windowUUID: String = "", viewID: Int): List<List<String>> {
        val viewModel = viewModel(windowUUID, viewID) ?: return emptyList()
        return (viewModel.states[ROWS_STATE_KEY] as? List<List<String>>) ?: emptyList()
    }

    /**
     * Replaces element [viewID]'s rows. Writes straight to the snapshot-state map
     * (not via [setElementState], whose type guard is for scalar state), so a
     * bound `List` / `Section` recomposes. Mirrors the Swift `setElementRows`.
     */
    fun setElementRows(windowUUID: String = "", viewID: Int, rows: List<List<String>>) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        viewModel.states[ROWS_STATE_KEY] = rows
        logger.log("Set ${rows.size} row(s) for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /** Appends [rows] after element [viewID]'s existing rows. Mirrors `appendElementRows`. */
    @Suppress("UNCHECKED_CAST")
    fun appendElementRows(windowUUID: String = "", viewID: Int, rows: List<List<String>>) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val existing = (viewModel.states[ROWS_STATE_KEY] as? List<List<String>>) ?: emptyList()
        viewModel.states[ROWS_STATE_KEY] = existing + rows
        logger.log("Appended ${rows.size} row(s) for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /** Clears element [viewID]'s rows (sets them to empty). Mirrors `clearElementRows`. */
    fun clearElementRows(windowUUID: String = "", viewID: Int) {
        setElementRows(windowUUID, viewID, emptyList())
    }

    /**
     * Returns the widest row's column count for element [viewID] (0 when empty).
     * Mirrors the Swift `getElementColumnCount`; templates reference columns
     * 1-based (`$1`..`$N`).
     */
    fun getElementColumnCount(windowUUID: String = "", viewID: Int): Int =
        getElementRows(windowUUID, viewID).maxOfOrNull { it.size } ?: 0
}
