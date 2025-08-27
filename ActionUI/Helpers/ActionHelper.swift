// Sources/ActionHelper.swift
import Foundation

struct ActionHelper {
    /// Dispatches an action handler asynchronously, ensuring it runs on the main thread after a background hop if called from the main thread.
    static func dispatchActionAsync(
        _ actionID: String,
        windowUUID: String,
        viewID: Int,
        viewPartID: Int,
        logger: any ActionUILogger
    ) {
        if Thread.isMainThread {
            Task.detached {
                // Run on background thread, then dispatch to main actor
                await Task { @MainActor in
                    logger.log("Executing async handler for actionID: \(actionID), viewID: \(viewID)", .debug)
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
                }.value
            }
        } else {
            Task { @MainActor in
                logger.log("Executing async handler for actionID: \(actionID), viewID: \(viewID)", .debug)
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
            }
        }
    }
}
