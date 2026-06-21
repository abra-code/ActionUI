package com.abracode.actionui.Common

import androidx.compose.ui.graphics.Color
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.DateHelper
import com.abracode.actionui.Helpers.DescriptionLoad
import com.abracode.actionui.Helpers.colorToHex
import com.abracode.actionui.Helpers.coordinateToJson
import com.abracode.actionui.Helpers.decodeDescription
import com.abracode.actionui.Helpers.jsonToKotlinValue
import com.abracode.actionui.Helpers.kotlinValueToJson
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.parseCoordinate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
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
 * A composed element listening for incoming URLs: the registration record
 * behind the `openURLActionID` hook (see [ActionUIModel.onOpenURL]).
 */
internal data class OpenURLObserver(
    val actionID: String,
    val windowUUID: String,
    val viewID: Int,
)

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
 * mode), as is the property API (`get/setElementProperty`, runtime property
 * overrides merged at the shared build entry point). Window-level presentation
 * is ported: **dialogs** (`presentAlert` / `presentConfirmationDialog` /
 * `dismissDialog`) and **modals** (`presentModal` / `dismissModal`, sheet /
 * fullScreenCover). **Runtime structural mutation** (`insertElement` /
 * `insertRow` / `removeElement`) is ported too - it mutates the parent's
 * [ViewModel.dynamicSubviews] (snapshot state) so the declaring container
 * recomposes; see [WindowModel] and `Private/Android_Porting_Notes.md`.
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

    /**
     * The `states` key under which a scrollable view holds its pull-to-refresh flag, as a
     * [Boolean]. Snapshot state, so the `PullToRefreshBox` reading it (see List / ScrollView)
     * recomposes when [beginRefresh] sets it true and an end signal sets it false.
     */
    const val REFRESHING_STATE_KEY = "refreshing"

    /**
     * Safety net mirroring Swift's `ActionUIModel.refreshTimeoutSeconds`: a refresh whose
     * client never signals completion ends after this delay so the indicator cannot hang. The
     * renderers drive the timeout from a `LaunchedEffect`. A `var` only so tests can lower it.
     */
    var refreshTimeoutMillis: Long = 60_000

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

    // MARK: - Pull-to-refresh

    /**
     * Entry point for a scrollable view's pull gesture (see List / ScrollView). Marks the view
     * refreshing - flipping the snapshot-backed [REFRESHING_STATE_KEY] so the `PullToRefreshBox`
     * keeps its indicator - captures the view's subtree for the end signal, and fires
     * [onRefreshActionID]. The indicator retracts when the client delivers data to this view or
     * anything inside it (any mutation, see [endRefreshTargeting]) or the renderer's safety
     * timeout fires. Unlike Apple there is no suspension: Compose state drives the indicator.
     */
    fun beginRefresh(windowUUID: String = "", viewID: Int, onRefreshActionID: String) {
        val windowModel = windowModels[windowUUID] ?: return
        val viewModel = windowModel.viewModels[viewID] ?: return
        // Capture the subtree once so a mutation to any descendant ends the refresh.
        viewModel.refreshSubtreeIDs = windowModel.subtreeIDs(viewID) ?: setOf(viewID)
        viewModel.states[REFRESHING_STATE_KEY] = true
        actionHandler(onRefreshActionID, windowUUID = windowUUID, viewID = viewID, viewPartID = 0)
    }

    /**
     * Ends any in-flight refresh whose captured subtree includes [viewID]. Called from the
     * element-mutation APIs so the client's natural response to a refresh (delivering fresh data
     * to the view, or to anything inside it) retracts the indicator with no dedicated API; the
     * renderer's timeout calls it with the refreshing view's own id. Idempotent.
     */
    internal fun endRefreshTargeting(windowUUID: String, viewID: Int) {
        val windowModel = windowModels[windowUUID] ?: return
        for (viewModel in windowModel.viewModels.values) {
            val subtree = viewModel.refreshSubtreeIDs ?: continue
            if (viewID in subtree) {
                viewModel.refreshSubtreeIDs = null
                viewModel.states[REFRESHING_STATE_KEY] = false
            }
        }
    }

    // MARK: - Incoming URL delivery (the `openURLActionID` hook)

    /**
     * The composed elements currently listening for incoming URLs. Each element
     * carrying `openURLActionID` registers an [OpenURLObserver] for exactly its
     * composition lifetime (`Helpers/ActionHookHelper.kt`), mirroring SwiftUI's
     * `.onOpenURL`, whose handlers exist while their view does.
     */
    private val openURLObservers = mutableListOf<OpenURLObserver>()

    internal fun registerOpenURLObserver(observer: OpenURLObserver) {
        openURLObservers.add(observer)
    }

    internal fun unregisterOpenURLObserver(observer: OpenURLObserver) {
        openURLObservers.remove(observer)
    }

    /**
     * Delivers an incoming [url] to every composed element carrying
     * `openURLActionID`, firing each element's actionID with the URL string as
     * `context`. The Android analog of the system invoking SwiftUI's
     * `.onOpenURL`: there the scene receives the URL, here the host Activity
     * does - call this from `onCreate` / `onNewIntent` when a deep-link intent
     * arrives (`intent.data?.toString()`).
     */
    fun onOpenURL(url: String) {
        if (openURLObservers.isEmpty()) {
            logger.log("onOpenURL: no composed element carries openURLActionID; URL dropped: $url", LoggerLevel.debug)
            return
        }
        // Snapshot: a handler may itself recompose elements and mutate the list.
        for (observer in openURLObservers.toList()) {
            actionHandler(
                actionID = observer.actionID,
                windowUUID = observer.windowUUID,
                viewID = observer.viewID,
                viewPartID = 0,
                context = url,
            )
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

    // MARK: - Window-level toast (snackbar)
    //
    // The Android port of the Swift `presentToast` / `dismissToast` surface. Like a
    // dialog these are pure data (a message, a duration, and an optional inline
    // action); they set [WindowModel.windowToast] (Compose snapshot state), which the
    // window's [com.abracode.actionui.Helpers.WindowToastHost] renders as a native
    // bottom Material3 Snackbar. The queue / one-at-a-time behavior is identical to
    // Apple; only the host's placement differs (top banner on Apple, bottom snackbar
    // here) - see [WindowToast].

    /**
     * Presents a transient, auto-dismissing toast over [windowUUID]'s window. If a
     * toast is already visible the new one is queued and shown after the current
     * dismisses (rapid posts coalesce into an ordered sequence). Pass [actionTitle]
     * and [actionID] together to add one inline action button (e.g. "Undo"); supplying
     * only one yields a message-only toast. No-op (with an error log) when no window is
     * registered for [windowUUID]. Mirrors the Swift `presentToast`.
     */
    fun presentToast(
        windowUUID: String = "",
        message: String,
        duration: Double = 4.0,
        actionTitle: String? = null,
        actionID: String? = null,
    ) {
        val windowModel = windowModels[windowUUID]
        if (windowModel == null) {
            logger.log("presentToast: No WindowModel for windowUUID: $windowUUID", LoggerLevel.error)
            return
        }
        val action = if (actionTitle != null && actionID != null) ToastAction(actionTitle, actionID) else null
        val toast = WindowToast(message, duration, action)
        if (windowModel.windowToast == null) {
            windowModel.windowToast = toast
        } else {
            windowModel.toastQueue.add(toast)
        }
        logger.log("presentToast: '$message' for windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /**
     * Dismisses the current toast and promotes the next queued toast if any. The toast
     * host calls this for you when the snackbar auto-dismisses or its inline action is
     * tapped. No-op when no window is registered for [windowUUID]. Mirrors the Swift
     * `dismissToast`.
     */
    fun dismissToast(windowUUID: String = "") {
        val windowModel = windowModels[windowUUID] ?: return
        windowModel.windowToast =
            if (windowModel.toastQueue.isEmpty()) null else windowModel.toastQueue.removeAt(0)
        logger.log("dismissToast: windowUUID: $windowUUID", LoggerLevel.debug)
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
        viewModel.mutationToken += 1
        viewModel.value = value
        endRefreshTargeting(windowUUID, viewID)
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
        viewModel.mutationToken += 1
        viewModel.states[key] = value
        endRefreshTargeting(windowUUID, viewID)
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
        endRefreshTargeting(windowUUID, viewID)
        logger.log("Set state '$key' from string for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    // MARK: - Element Property API

    /**
     * Returns the current value of property [propertyName] on element [viewID]:
     * a runtime override ([setElementProperty]) if one was set, else the
     * authored JSON value, both as plain Kotlin values
     * ([com.abracode.actionui.Helpers.jsonToKotlinValue]). Warns and returns
     * null for an unknown element or an absent property. Mirrors the Swift
     * `getElementProperty`, which reads the one merged `validatedProperties`
     * dictionary.
     */
    fun getElementProperty(windowUUID: String = "", viewID: Int, propertyName: String): Any? {
        val viewModel = viewModel(windowUUID, viewID) ?: return null
        val element = viewModel.propertyOverrides[propertyName]
            ?: viewModel.authoredProperties?.get(propertyName)
        if (element == null) {
            logger.log("Property '$propertyName' not found for viewID: $viewID", LoggerLevel.warning)
            return null
        }
        return jsonToKotlinValue(element)
    }

    /**
     * Sets property [propertyName] on element [viewID] to [value] (a plain
     * Kotlin value - Boolean / Number / String / List / Map - or a
     * [kotlinx.serialization.json.JsonElement]). The write lands in
     * [ViewModel.propertyOverrides]; the shared build entry point
     * (`Helpers/ViewModifierHelper.kt`) merges overrides into the element's
     * properties during composition, so the element recomposes with the new
     * value - the Apple contract, where views read the mutated
     * `validatedProperties`. Warns and does nothing for an unknown element or
     * an unrepresentable value type.
     *
     * The Swift setter re-validates the mutated dictionary; Android has no
     * central validation stage (see the porting notes), so an invalid value is
     * caught where authored values are - warn-and-skip at read time.
     */
    fun setElementProperty(windowUUID: String = "", viewID: Int, propertyName: String, value: Any) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val json = kotlinValueToJson(value)
        if (json == null) {
            logger.log(
                "Unsupported value type ${value::class.simpleName} for property '$propertyName' " +
                    "on viewID: $viewID. Expected Boolean, Number, String, List, or Map.",
                LoggerLevel.warning
            )
            return
        }
        viewModel.mutationToken += 1
        viewModel.propertyOverrides[propertyName] = json
        logger.log("Set property '$propertyName' for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
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
        endRefreshTargeting(windowUUID, viewID)
        logger.log("Set ${rows.size} row(s) for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
    }

    /** Appends [rows] after element [viewID]'s existing rows. Mirrors `appendElementRows`. */
    @Suppress("UNCHECKED_CAST")
    fun appendElementRows(windowUUID: String = "", viewID: Int, rows: List<List<String>>) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val existing = (viewModel.states[ROWS_STATE_KEY] as? List<List<String>>) ?: emptyList()
        viewModel.states[ROWS_STATE_KEY] = existing + rows
        endRefreshTargeting(windowUUID, viewID)
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

    // MARK: - Runtime structural mutations (insertElement / insertRow / removeElement)
    //
    // The Android port of the Swift `ActionUIModel` insertion surface. The model
    // resolves which insertable container the request targets (by the parent's
    // declared [ActionUIViewConstruction.insertableContainers] and the method's
    // shape) and delegates the mutation to [WindowModel], which writes the new
    // container into the parent's [ViewModel.dynamicSubviews] (snapshot state) so
    // the declaring view recomposes. All entry points throw [InsertError] on a
    // bad request, matching Apple.

    /**
     * Inserts [element] into a flat container (`children` / `destinations`) of
     * [parentID] at [position]. [container] may be null when the parent declares
     * exactly one flat container. Returns the inserted element's id. Throws
     * [InsertError] for an unknown window/parent, a non-container parent, an
     * ambiguous/unknown container, an out-of-range position, or an id conflict.
     * Mirrors the Swift `insertElement(windowUUID:parentID:dict:container:position:)`.
     */
    fun insertElement(
        windowUUID: String = "",
        parentID: Int,
        element: ActionUIElement,
        container: String? = null,
        position: InsertPosition = InsertPosition.Append,
    ): Int {
        val windowModel = windowModels[windowUUID] ?: throw InsertError.WindowNotFound(windowUUID)
        val resolved = resolveContainer(parentID, windowModel, container, ContainerShape.FLAT)
        return windowModel.insertElement(element, parentID, resolved, position)
    }

    /**
     * JSON-string convenience over [insertElement]: [jsonString] must encode one
     * element object, decoded through the Android [PlatformFilter] like the
     * document loader. Throws [InsertError.InvalidJSON] / [InsertError.MissingType]
     * on a bad payload. Mirrors the Swift `insertElement(...json:...)` overload.
     */
    fun insertElement(
        windowUUID: String = "",
        parentID: Int,
        jsonString: String,
        container: String? = null,
        position: InsertPosition = InsertPosition.Append,
    ): Int = insertElement(windowUUID, parentID, parseElement(jsonString), container, position)

    /**
     * Inserts a row of [cells] into a `rows` container (`Grid`) of [parentID] at
     * [position] (before/after are rejected - rows have no synthetic id). Returns
     * the inserted cell ids. Mirrors the Swift `insertRow(...cells:...)`.
     */
    fun insertRow(
        windowUUID: String = "",
        parentID: Int,
        cells: List<ActionUIElement>,
        container: String? = null,
        position: InsertPosition = InsertPosition.Append,
    ): List<Int> {
        val windowModel = windowModels[windowUUID] ?: throw InsertError.WindowNotFound(windowUUID)
        val resolved = resolveContainer(parentID, windowModel, container, ContainerShape.ROWS)
        return windowModel.insertRow(cells, parentID, resolved, position)
    }

    /**
     * JSON-string convenience over [insertRow]: [jsonString] must encode a JSON
     * array of cell objects, e.g. `[{"type":"Text",...},{"type":"Button",...}]`.
     * Mirrors the Swift `insertRow(...json:...)` overload.
     */
    fun insertRow(
        windowUUID: String = "",
        parentID: Int,
        jsonString: String,
        container: String? = null,
        position: InsertPosition = InsertPosition.Append,
    ): List<Int> = insertRow(windowUUID, parentID, parseCells(jsonString), container, position)

    /**
     * Removes element [viewID] (and its descendants) from its flat / rows
     * container. Throws [InsertError] for an unknown window, the window root, an
     * unknown view, or a view that is not a removable container member. Mirrors
     * the Swift `removeElement(windowUUID:viewID:)`.
     */
    fun removeElement(windowUUID: String = "", viewID: Int) {
        val windowModel = windowModels[windowUUID] ?: throw InsertError.WindowNotFound(windowUUID)
        windowModel.removeElement(viewID)
    }

    /**
     * Resolves which insertable container of [parentID] a request targets: the
     * [requestedContainer] when given (validated against the parent's declared
     * containers and the method's [expectedShape]), else the parent's unique
     * container of that shape. Mirrors the Swift `resolveContainer`.
     */
    private fun resolveContainer(
        parentID: Int,
        windowModel: WindowModel,
        requestedContainer: String?,
        expectedShape: ContainerShape,
    ): String {
        val parentVM = windowModel.viewModels[parentID] ?: throw InsertError.ParentNotFound(parentID)
        val containers = ActionUIRegistry.getInsertableContainers(parentVM.elementType)
            ?: throw InsertError.NotAContainer(parentVM.elementType)

        if (requestedContainer != null) {
            val shape = containers[requestedContainer]
                ?: throw InsertError.UnknownContainer(requestedContainer, containers.keys.sorted())
            if (shape != expectedShape) {
                val methodName = if (expectedShape == ContainerShape.FLAT) "insertElement" else "insertRow"
                val altMethod = if (expectedShape == ContainerShape.FLAT) "insertRow" else "insertElement"
                throw InsertError.WrongMethod(
                    requestedContainer, shape,
                    "$methodName requires a $expectedShape container - use $altMethod for this container.",
                )
            }
            return requestedContainer
        }

        val matching = containers.filterValues { it == expectedShape }.keys
        if (matching.size == 1) return matching.first()
        throw InsertError.ContainerRequired(matching.sorted())
    }

    /** Decodes one element from a JSON object string, through the Android [PlatformFilter]. */
    private fun parseElement(jsonString: String): ActionUIElement {
        val raw = try {
            json.parseToJsonElement(jsonString)
        } catch (e: Exception) {
            throw InsertError.InvalidJSON(e.message ?: "could not parse JSON")
        }
        val filtered = PlatformFilter.Android.withLogger(logger).filter(raw)
        val element = try {
            json.decodeFromJsonElement(ActionUIElement.serializer(), filtered)
        } catch (e: Exception) {
            throw InsertError.InvalidJSON(e.message ?: "could not decode element")
        }
        if (element.type.isEmpty()) throw InsertError.MissingType
        return element
    }

    /** Decodes an array of cell elements from a JSON array string, platform-filtered. */
    private fun parseCells(jsonString: String): List<ActionUIElement> {
        val raw = try {
            json.parseToJsonElement(jsonString)
        } catch (e: Exception) {
            throw InsertError.InvalidJSON(e.message ?: "could not parse JSON")
        }
        if (raw !is JsonArray) throw InsertError.InvalidJSON("Expected a JSON array of cell objects")
        return raw.map { cell ->
            val filtered = PlatformFilter.Android.withLogger(logger).filter(cell)
            val element = try {
                json.decodeFromJsonElement(ActionUIElement.serializer(), filtered)
            } catch (e: Exception) {
                throw InsertError.InvalidJSON(e.message ?: "could not decode cell")
            }
            if (element.type.isEmpty()) throw InsertError.MissingType
            element
        }
    }

    /**
     * Selects element [viewID]'s row at the 0-based [index] by writing the row's column
     * values to [ViewModel.value] without altering the rows. An index outside the row range
     * clears the selection. Fires no action. Mirrors the Swift `selectElementRow(index:)`.
     * Returns the selected row's values, or null if the index was out of range / not a Table/List.
     */
    fun selectElementRow(windowUUID: String = "", viewID: Int, index: Int): List<String>? {
        val viewModel = viewModel(windowUUID, viewID) ?: return null
        val content = getElementRows(windowUUID, viewID)
        if (index < 0 || index >= content.size) {
            clearElementSelection(windowUUID, viewID)
            return null
        }
        val rowValues = content[index]
        if (viewModel.value != rowValues) {
            viewModel.mutationToken += 1
            viewModel.value = rowValues
        }
        logger.log("Selected row $index for viewID: $viewID, windowUUID: $windowUUID", LoggerLevel.debug)
        return rowValues
    }

    /**
     * Selects the first row whose column value matches [text] (exact, case-sensitive).
     * When [column] is null, matches any column; otherwise matches the given 0-based column
     * only. Fires no action. Mirrors the Swift `selectElementRow(matching:column:)`.
     * Returns the 0-based index of the selected row, or null if no row matched.
     */
    fun selectElementRow(windowUUID: String = "", viewID: Int, text: String, column: Int? = null): Int? {
        val content = getElementRows(windowUUID, viewID)
        val idx = content.indexOfFirst { row ->
            if (column != null) column in row.indices && row[column] == text
            else row.contains(text)
        }
        if (idx < 0) return null
        selectElementRow(windowUUID, viewID, idx)
        return idx
    }

    /** Clears element [viewID]'s selection (sets [ViewModel.value] to an empty list when a
     * non-empty list selection exists). Mirrors the Swift `clearElementSelection`. */
    fun clearElementSelection(windowUUID: String = "", viewID: Int) {
        val viewModel = viewModel(windowUUID, viewID) ?: return
        val selected = viewModel.value as? List<*> ?: return
        if (selected.isNotEmpty()) {
            viewModel.mutationToken += 1
            viewModel.value = emptyList<String>()
        }
    }
}
