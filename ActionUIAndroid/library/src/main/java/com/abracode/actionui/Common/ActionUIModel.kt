package com.abracode.actionui.Common

/**
 * Signature of an ActionUI action handler.
 *
 * Mirror of the Swift closure type `(String, String, Int, Int, Any?) -> Void`
 * used by `ActionUIModel` in `ActionUI/Common/ActionUIModel.swift`. The
 * parameters, in order:
 *
 *   * `actionID`   — the identifier that triggered the handler.
 *   * `windowUUID` — the window the action originated from. The Android port is
 *     currently single-window, so this is the empty string until multi-window
 *     support is ported; the parameter is kept so the contract matches Apple.
 *   * `viewID`     — the `id` of the element that fired the action (0 if none).
 *   * `viewPartID` — sub-element index (e.g. table row/column); 0 for simple controls.
 *   * `context`    — optional payload supplied by the firing element.
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
 * `ActionUIModel.shared`. The window/view state-management portions of the
 * Swift model (`windowModels`, `setElementValue`, structural insert/remove,
 * modal/dialog presentation) are **not** ported yet — the Android renderer is
 * still stateless. Only the action-dispatch contract is mirrored here so client
 * code can wire up button handlers identically to the Apple side.
 *
 * Handlers fire from Compose `onClick` callbacks on the main thread; this
 * object performs no synchronization of its own.
 */
object ActionUIModel {

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
}
