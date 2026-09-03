// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIC.swift
//  ActionUICAdapter
//
//  Swift implementation of C interface for ActionUI.
//
//  NOTE: C types (ActionUILogLevel, ActionUILoggerCallback, ActionUIActionHandler)
//  are exposed via the framework's umbrella header (ActionUICAdapter.h -> ActionUIC.h)
//  and automatically declared in the generated ActionUICAdapter-Swift.h header
//  (but only when __OBJC__ is defined)
//

import Foundation
import ActionUI
import SwiftUI

#if SWIFT_PACKAGE
import ActionUICAdapterHeaders
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Concurrency Helpers

/// Execute operation on main actor asynchronously (fire-and-forget)
/// Safe to call from any thread
@inline(__always)
private func runOnMainActorAsync(_ operation: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        // Already on main thread - execute directly
        MainActor.assumeIsolated {
            operation()
        }
    } else {
        // On background thread - dispatch asynchronously
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                operation()
            }
        }
    }
}

/// Execute operation on main actor synchronously, returning result
/// Safe to call from any thread (deadlock-protected)
@inline(__always)
private func runOnMainActorSync<T>(_ operation: @MainActor () -> T) -> T {
    // The result may be a non-Sendable bridging value (Any?, a SwiftUI view, a C pointer, ...), so it
    // cannot cross the main-actor boundary directly under Swift 6. Move it back through a
    // nonisolated(unsafe) box: this is sound because both paths are fully synchronous (direct execution
    // or DispatchQueue.main.sync), so there is never concurrent access to `result`.
    nonisolated(unsafe) var result: T!
    if Thread.isMainThread {
        // Already on main thread - execute directly (zero overhead)
        MainActor.assumeIsolated {
            result = operation()
        }
    } else {
        // On background thread - must block and wait
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                result = operation()
            }
        }
    }
    return result
}

// MARK: - String Helpers

/// Heap-copy `str` into a malloc-owned C string. Caller must free with actionUIFreeString.
@inline(__always)
private func actionStrdup(_ str: String) -> UnsafeMutablePointer<CChar>? {
    return str.withCString { strdup($0) }
}

// MARK: - Version Info

@_cdecl("actionUIGetVersion")
public func actionUIGetVersion() -> UnsafeMutablePointer<CChar>? {
    return actionStrdup("1.0.0")
}

// MARK: - Logging

// nonisolated(unsafe): C bridging state set/read across the @_cdecl entry points. This retains the
// adapter's existing single-threaded-caller assumption (no new locking is introduced).
private nonisolated(unsafe) var cLoggerCallback: ActionUILoggerCallback? = nil

private final class CLoggerBridge: ActionUILogger {
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {
        guard let callback = cLoggerCallback else { return }
        
        let cLevel: ActionUILogLevel = switch level {
        case .error: ActionUILogLevelError      // 1
        case .warning: ActionUILogLevelWarning  // 2
        case .info: ActionUILogLevelInfo        // 3
        case .debug: ActionUILogLevelDebug      // 4
        case .verbose: ActionUILogLevelVerbose  // 5
        @unknown default: ActionUILogLevelInfo  // for Swift 6
        }
        
        message.withCString { cString in
            callback(cString, cLevel)
        }
    }
}

@_cdecl("actionUISetLogger")
public func actionUISetLogger(_ callback: ActionUILoggerCallback?) {
    cLoggerCallback = callback
    if callback != nil {
        runOnMainActorAsync {
            ActionUIModel.shared.logger = CLoggerBridge()
        }
    }
}

@_cdecl("actionUILog")
public func actionUILog(_ message: UnsafePointer<CChar>, _ level: ActionUILogLevel) {
    let swiftMessage = String(cString: message)
    let swiftLevel: ActionUI.LoggerLevel = switch level {
    case ActionUILogLevelError: .error       // 1
    case ActionUILogLevelWarning: .warning   // 2
    case ActionUILogLevelInfo: .info         // 3
    case ActionUILogLevelDebug: .debug       // 4
    case ActionUILogLevelVerbose: .verbose   // 5
    default: .info
    }
    
    runOnMainActorAsync {
        ActionUIModel.shared.logger.log(swiftMessage, swiftLevel)
    }
}

// MARK: - Action Handling

// nonisolated(unsafe): see cLoggerCallback. Registered from the @_cdecl entry points, read from the
// bridged action handler (invoked on the main actor).
private nonisolated(unsafe) var actionHandlers: [String: ActionUIActionHandler] = [:]
private nonisolated(unsafe) var defaultActionHandler: ActionUIActionHandler? = nil

private func bridgeActionHandler(actionID: String, windowUUID: String, viewID: Int, viewPartID: Int, context: Any?) {
    let handler = actionHandlers[actionID] ?? defaultActionHandler
    guard let handler = handler else {
        runOnMainActorAsync {
            ActionUIModel.shared.logger.log("No handler registered for action: \(actionID)", .warning)
        }
        return
    }
    
    var contextJSON: String? = nil
    if let context = context {
        contextJSON = safeJSONString(from: context)
    }
    
    actionID.withCString { actionCStr in
        windowUUID.withCString { windowCStr in
            if let contextJSON = contextJSON {
                contextJSON.withCString { contextCStr in
                    handler(actionCStr, windowCStr, Int64(viewID), Int64(viewPartID), contextCStr)
                }
            } else {
                handler(actionCStr, windowCStr, Int64(viewID), Int64(viewPartID), nil)
            }
        }
    }
}

@_cdecl("actionUIRegisterActionHandler")
public func actionUIRegisterActionHandler(_ actionID: UnsafePointer<CChar>, _ handler: @escaping ActionUIActionHandler) -> CBool {
    let swiftActionID = String(cString: actionID)
    actionHandlers[swiftActionID] = handler
    
    runOnMainActorAsync {
        ActionUIModel.shared.registerActionHandler(for: swiftActionID) { actionID, windowUUID, viewID, viewPartID, context in
            bridgeActionHandler(actionID: actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, context: context)
        }
    }
    
    return true
}

@_cdecl("actionUIUnregisterActionHandler")
public func actionUIUnregisterActionHandler(_ actionID: UnsafePointer<CChar>) -> CBool {
    let swiftActionID = String(cString: actionID)
    actionHandlers.removeValue(forKey: swiftActionID)
    
    runOnMainActorAsync {
        ActionUIModel.shared.unregisterActionHandler(for: swiftActionID)
    }
    
    return true
}

@_cdecl("actionUISetDefaultActionHandler")
public func actionUISetDefaultActionHandler(_ handler: ActionUIActionHandler?) {
    defaultActionHandler = handler
    
    if handler != nil {
        runOnMainActorAsync {
            ActionUIModel.shared.setDefaultActionHandler { actionID, windowUUID, viewID, viewPartID, context in
                bridgeActionHandler(actionID: actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, context: context)
            }
        }
    } else {
        runOnMainActorAsync {
            ActionUIModel.shared.removeDefaultActionHandler()
        }
    }
}

@_cdecl("actionUIRemoveDefaultActionHandler")
public func actionUIRemoveDefaultActionHandler() {
    defaultActionHandler = nil
    runOnMainActorAsync {
        ActionUIModel.shared.removeDefaultActionHandler()
    }
}

// MARK: - Error Handling

// nonisolated(unsafe): see cLoggerCallback. Set via setError/clearError, read via the last-error getter.
private nonisolated(unsafe) var lastError: String? = nil

private func setError(_ message: String) {
    lastError = message
    runOnMainActorAsync {
        ActionUIModel.shared.logger.log("Error: \(message)", .error)
    }
}

private func clearError() {
    lastError = nil
}

@_cdecl("actionUIGetLastError")
public func actionUIGetLastError() -> UnsafeMutablePointer<CChar>? {
    guard let error = lastError else { return nil }
    return actionStrdup(error)
}

@_cdecl("actionUIClearError")
public func actionUIClearError() {
    clearError()
}

// MARK: - JSON Conversion Helpers

// The conversion itself lives in ActionUI core (ActionUIJSON) so that every adapter encodes and
// decodes identically. These wrappers keep the C adapter's contract: nil on failure, with the
// failure text available through actionUIGetLastError().

/// Convert any value to a JSON string safely (see ActionUIJSON.string(from:)).
/// Returns nil and records the error when the value has no JSON representation.
private func safeJSONString(from value: Any) -> String? {
    do {
        return try ActionUIJSON.string(from: value)
    } catch {
        setError(jsonErrorMessage(error))
        return nil
    }
}

private func valueToJSON(_ value: Any) -> String? {
    return safeJSONString(from: value)
}

/// Parse a JSON string, fragments allowed (see ActionUIJSON.value(from:)).
/// Returns nil and records the error when the string is not UTF-8 or not JSON.
private func jsonToValue(_ json: String) -> Any? {
    do {
        return try ActionUIJSON.value(from: json)
    } catch {
        setError(jsonErrorMessage(error))
        return nil
    }
}

private func jsonErrorMessage(_ error: Error) -> String {
    if let jsonError = error as? ActionUIJSONError {
        return jsonError.message
    }
    return "\(error)"
}

// MARK: - Element Value Management (JSON)

@_cdecl("actionUISetElementValueJSON")
public func actionUISetElementValueJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ valueJSON: UnsafePointer<CChar>
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    let swiftValueJSON = String(cString: valueJSON)
    
    guard let value = jsonToValue(swiftValueJSON) else {
        return false
    }
    
    runOnMainActorAsync {
        ActionUIModel.shared.setElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            value: value
        )
    }
    
    return true
}

@_cdecl("actionUIGetElementValueJSON")
public func actionUIGetElementValueJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64
) -> UnsafeMutablePointer<CChar>? {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    
    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID)
        )
    }
    
    guard let value = result else {
        return nil
    }
    
    guard let json = valueToJSON(value) else {
        return nil
    }

    return actionStrdup(json)
}

// MARK: - Element Value Management (String)

@_cdecl("actionUISetElementValueString")
public func actionUISetElementValueString(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ valueString: UnsafePointer<CChar>,
    _ contentType: UnsafePointer<CChar>?
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    let swiftValueString = String(cString: valueString)
    let swiftContentType = contentType.map { String(cString: $0) }
    
    runOnMainActorAsync {
        ActionUIModel.shared.setElementValueFromString(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            value: swiftValueString,
            contentType: swiftContentType
        )
    }
    
    return true
}

@_cdecl("actionUIGetElementValueString")
public func actionUIGetElementValueString(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ contentType: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    let swiftContentType = contentType.map { String(cString: $0) }

    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementValueAsString(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            contentType: swiftContentType
        )
    }
    
    guard let value = result else {
        return nil
    }

    return actionStrdup(value)
}

// MARK: - Element Column Count

/// Returns the number of data columns for a table/list view element.
/// Reports the maximum column count across all content rows, including hidden columns
/// beyond the visible ones defined in the JSON layout.
/// Returns 0 for non-table elements or if the view is not found.
@_cdecl("actionUIGetElementColumnCount")
public func actionUIGetElementColumnCount(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64
) -> Int64 {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)

    let count = runOnMainActorSync {
        ActionUIModel.shared.getElementColumnCount(windowUUID: swiftWindowUUID, viewID: Int(viewID))
    }

    return Int64(count)
}

// MARK: - Element Rows

/// Returns a JSON string representing all content rows for a table/list view element.
/// Caller must free the returned string with actionUIFreeString.
/// Returns NULL if the view is not a table, not found, or has no rows.
/// JSON format: [["cell1","cell2"],["cell3","cell4"],...]
@_cdecl("actionUIGetElementRowsJSON")
public func actionUIGetElementRowsJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64
) -> UnsafeMutablePointer<CChar>? {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)

    let rows = runOnMainActorSync {
        ActionUIModel.shared.getElementRows(windowUUID: swiftWindowUUID, viewID: Int(viewID))
    }

    guard let rows = rows else {
        return nil
    }

    guard let json = valueToJSON(rows) else {
        return nil
    }

    return actionStrdup(json)
}

/// Clears all content rows from a table/list view element, preserving column definitions.
@_cdecl("actionUIClearElementRows")
public func actionUIClearElementRows(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64
) {
    let swiftWindowUUID = String(cString: windowUUID)

    runOnMainActorAsync {
        ActionUIModel.shared.clearElementRows(windowUUID: swiftWindowUUID, viewID: Int(viewID))
    }
}

/// Replaces all content rows for a table/list view element from a JSON string.
/// Clears the current selection if the selected row is no longer present.
/// JSON format: [["cell1","cell2"],["cell3","cell4"],...]
@_cdecl("actionUISetElementRowsJSON")
public func actionUISetElementRowsJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ rowsJSON: UnsafePointer<CChar>
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftRowsJSON = String(cString: rowsJSON)

    guard let value = jsonToValue(swiftRowsJSON), let rows = value as? [[String]] else {
        setError("Invalid rows JSON: expected array of string arrays")
        return false
    }

    runOnMainActorAsync {
        ActionUIModel.shared.setElementRows(windowUUID: swiftWindowUUID, viewID: Int(viewID), rows: rows)
    }

    return true
}

/// Appends rows to a table/list view element's existing content from a JSON string.
/// JSON format: [["cell1","cell2"],["cell3","cell4"],...]
@_cdecl("actionUIAppendElementRowsJSON")
public func actionUIAppendElementRowsJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ rowsJSON: UnsafePointer<CChar>
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftRowsJSON = String(cString: rowsJSON)

    guard let value = jsonToValue(swiftRowsJSON), let rows = value as? [[String]] else {
        setError("Invalid rows JSON: expected array of string arrays")
        return false
    }

    runOnMainActorAsync {
        ActionUIModel.shared.appendElementRows(windowUUID: swiftWindowUUID, viewID: Int(viewID), rows: rows)
    }

    return true
}

// MARK: - Element Selection

/// Selects a row by its 0-based index in a Table/List view element.
/// An index outside 0..<rowCount clears the selection. Does not fire the element's actionID.
/// Returns true if a row was selected, false if the index was out of range (selection cleared)
/// or the view is not a Table/List.
@_cdecl("actionUISelectElementRowByIndex")
public func actionUISelectElementRowByIndex(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ index: Int64
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)

    let selected = runOnMainActorSync {
        ActionUIModel.shared.selectElementRow(windowUUID: swiftWindowUUID, viewID: Int(viewID), index: Int(index))
    }

    return selected != nil
}

/// Selects the first row whose column value matches `text` (exact, case-sensitive).
/// A negative `column` matches any column; otherwise matches the given 0-based column only.
/// Does not fire the element's actionID.
/// Returns the 0-based index of the selected row, or -1 if no row matched.
@_cdecl("actionUISelectElementRowWithContent")
public func actionUISelectElementRowWithContent(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ text: UnsafePointer<CChar>,
    _ column: Int64
) -> Int64 {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftText = String(cString: text)
    let col: Int? = (column >= 0) ? Int(column) : nil

    let idx = runOnMainActorSync {
        ActionUIModel.shared.selectElementRow(windowUUID: swiftWindowUUID, viewID: Int(viewID), matching: swiftText, column: col)
    }

    return Int64(idx ?? -1)
}

/// Clears the current selection of a Table/List view element.
@_cdecl("actionUIClearElementSelection")
public func actionUIClearElementSelection(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64
) {
    let swiftWindowUUID = String(cString: windowUUID)

    runOnMainActorAsync {
        ActionUIModel.shared.clearElementSelection(windowUUID: swiftWindowUUID, viewID: Int(viewID))
    }
}

// MARK: - Element Properties

/// Gets a structural property value for a view element, returned as a JSON string.
/// Caller must free the returned string with actionUIFreeString.
/// Returns NULL if not found.
@_cdecl("actionUIGetElementPropertyJSON")
public func actionUIGetElementPropertyJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ propertyName: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>? {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftPropertyName = String(cString: propertyName)

    let value = runOnMainActorSync {
        ActionUIModel.shared.getElementProperty(windowUUID: swiftWindowUUID, viewID: Int(viewID), propertyName: swiftPropertyName)
    }

    guard let value = value else {
        return nil
    }

    guard let json = valueToJSON(value) else {
        return nil
    }

    return actionStrdup(json)
}

/// Sets a structural property value for a view element from a JSON string.
/// The value is re-validated through the element's validateProperties function.
@_cdecl("actionUISetElementPropertyJSON")
public func actionUISetElementPropertyJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ propertyName: UnsafePointer<CChar>,
    _ valueJSON: UnsafePointer<CChar>
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftPropertyName = String(cString: propertyName)
    let swiftValueJSON = String(cString: valueJSON)

    guard let value = jsonToValue(swiftValueJSON) else {
        return false
    }

    runOnMainActorAsync {
        ActionUIModel.shared.setElementProperty(windowUUID: swiftWindowUUID, viewID: Int(viewID), propertyName: swiftPropertyName, value: value)
    }

    return true
}

// MARK: - Element State Management

/// Returns the current value for a single state key of a view element, as a JSON string.
/// Caller must free the returned string with actionUIFreeString.
/// Returns NULL if the view or key is not found.
@_cdecl("actionUIGetElementStateJSON")
public func actionUIGetElementStateJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ key: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>? {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftKey = String(cString: key)

    let value = runOnMainActorSync {
        ActionUIModel.shared.getElementState(windowUUID: swiftWindowUUID, viewID: Int(viewID), key: swiftKey)
    }

    guard let value = value else {
        return nil
    }

    guard let json = valueToJSON(value) else {
        return nil
    }

    return actionStrdup(json)
}

/// Returns the string representation of a single state value for a view element.
/// Caller must free the returned string with actionUIFreeString.
/// Returns NULL if the view or key is not found.
@_cdecl("actionUIGetElementStateString")
public func actionUIGetElementStateString(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ key: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>? {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftKey = String(cString: key)

    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementStateAsString(windowUUID: swiftWindowUUID, viewID: Int(viewID), key: swiftKey)
    }

    guard let value = result else {
        return nil
    }

    return actionStrdup(value)
}

/// Sets a single state key to a new value parsed from a JSON string.
/// Rejects the update (with an error log) if the new value's type differs from the existing value's type.
@_cdecl("actionUISetElementStateJSON")
public func actionUISetElementStateJSON(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ key: UnsafePointer<CChar>,
    _ valueJSON: UnsafePointer<CChar>
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftKey = String(cString: key)
    let swiftValueJSON = String(cString: valueJSON)

    guard let value = jsonToValue(swiftValueJSON) else {
        return false
    }

    runOnMainActorAsync {
        ActionUIModel.shared.setElementState(windowUUID: swiftWindowUUID, viewID: Int(viewID), key: swiftKey, value: value)
    }

    return true
}

/// Sets a single state key by parsing a string into the type of the existing value.
/// If the key does not yet exist the string is stored as-is.
@_cdecl("actionUISetElementStateFromString")
public func actionUISetElementStateFromString(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ key: UnsafePointer<CChar>,
    _ value: UnsafePointer<CChar>
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftKey = String(cString: key)
    let swiftValue = String(cString: value)

    runOnMainActorAsync {
        ActionUIModel.shared.setElementStateFromString(windowUUID: swiftWindowUUID, viewID: Int(viewID), key: swiftKey, value: swiftValue)
    }

    return true
}

// MARK: - Element Info

/// Returns a JSON string mapping positive view IDs to their view type strings.
/// Caller must free the returned string with actionUIFreeString.
/// Returns NULL if no window found or no elements with positive IDs.
/// JSON format: {"2":"TextField","3":"SecureField","4":"Picker",...}
@_cdecl("actionUIGetElementInfoJSON")
public func actionUIGetElementInfoJSON(
    _ windowUUID: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>? {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)

    let info = runOnMainActorSync {
        ActionUIModel.shared.getElementInfo(windowUUID: swiftWindowUUID)
    }

    if info.isEmpty {
        return nil
    }

    // Convert [Int: String] to [String: String] for JSON serialization
    let stringKeyedInfo = Dictionary(uniqueKeysWithValues: info.map { (String($0.key), $0.value) })
    guard let json = valueToJSON(stringKeyedInfo) else {
        return nil
    }

    return actionStrdup(json)
}

// MARK: - Type-specific Setters

@_cdecl("actionUISetIntValue")
public func actionUISetIntValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ value: Int64
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    runOnMainActorAsync {
        ActionUIModel.shared.setElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            value: Int(value)
        )
    }
    return true
}

@_cdecl("actionUISetDoubleValue")
public func actionUISetDoubleValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ value: Double
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    runOnMainActorAsync {
        ActionUIModel.shared.setElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            value: value
        )
    }
    return true
}

@_cdecl("actionUISetBoolValue")
public func actionUISetBoolValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ value: CBool,
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    runOnMainActorAsync {
        ActionUIModel.shared.setElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            value: value
        )
    }
    return true
}

@_cdecl("actionUISetStringValue")
public func actionUISetStringValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ value: UnsafePointer<CChar>
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    let swiftValue = String(cString: value)
    runOnMainActorAsync {
        ActionUIModel.shared.setElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID),
            value: swiftValue
        )
    }
    return true
}

// MARK: - Type-specific Getters

@_cdecl("actionUIGetIntValue")
public func actionUIGetIntValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ outValue: UnsafeMutablePointer<Int64>
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    
    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID)
        )
    }
    
    guard let value = result else {
        return false
    }
    
    if let intValue = value as? Int {
        outValue.pointee = Int64(intValue)
        return true
    } else if let doubleValue = value as? Double {
        outValue.pointee = Int64(doubleValue)
        return true
    }
    
    setError("Value is not an integer")
    return false
}

@_cdecl("actionUIGetDoubleValue")
public func actionUIGetDoubleValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ outValue: UnsafeMutablePointer<Double>
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    
    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID)
        )
    }
    
    guard let value = result else {
        return false
    }
    
    if let doubleValue = value as? Double {
        outValue.pointee = doubleValue
        return true
    } else if let intValue = value as? Int {
        outValue.pointee = Double(intValue)
        return true
    }
    
    setError("Value is not a number")
    return false
}

@_cdecl("actionUIGetBoolValue")
public func actionUIGetBoolValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64,
    _ outValue: UnsafeMutablePointer<CBool>
) -> CBool {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    
    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID)
        )
    }
    
    guard let value = result else {
        return false
    }
    
    if let boolValue = value as? Bool {
        outValue.pointee = boolValue
        return true
    }
    
    setError("Value is not a boolean")
    return false
}

@_cdecl("actionUIGetStringValue")
public func actionUIGetStringValue(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID: Int64,
    _ viewPartID: Int64
) -> UnsafeMutablePointer<CChar>? {
    clearError()
    
    let swiftWindowUUID = String(cString: windowUUID)
    
    let result = runOnMainActorSync {
        ActionUIModel.shared.getElementValue(
            windowUUID: swiftWindowUUID,
            viewID: Int(viewID),
            viewPartID: Int(viewPartID)
        )
    }
    
    guard let value = result else {
        return nil
    }
    
    if let stringValue = value as? String {
        return actionStrdup(stringValue)
    }
    
    setError("Value is not a string")
    return nil
}

// MARK: - UI Loading


@_cdecl("actionUILoadHostingControllerFromURL")
public func actionUILoadHostingControllerFromURL(
    _ urlString: UnsafePointer<CChar>,
    _ windowUUID: UnsafePointer<CChar>,
    _ isContentView: CBool
) -> UnsafeMutableRawPointer? {
    clearError()
    
    let swiftURLString = String(cString: urlString)
    let swiftWindowUUID = String(cString: windowUUID)
    
    guard let url = URL(string: swiftURLString) else {
        setError("Invalid URL: \(swiftURLString)")
        return nil
    }
    
    
    return runOnMainActorSync {
        let logger = ActionUIModel.shared.logger
        var view: any SwiftUI.View

        if url.scheme == "file" {
            view = ActionUI.FileLoadableView(fileURL: url, windowUUID: swiftWindowUUID, isContentView: isContentView, logger: logger)
        } else {
            view = ActionUI.RemoteLoadableView(url: url, windowUUID: swiftWindowUUID, isContentView: isContentView, logger: logger)
        }
        
        #if canImport(AppKit)
        let hostingController = NSHostingController(rootView: AnyView(view))
        hostingController.view.autoresizingMask = [.width, .height]
        return Unmanaged.passRetained(hostingController).toOpaque()
        #elseif canImport(UIKit)
        let hostingController = UIHostingController(rootView: AnyView(view))
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return Unmanaged.passRetained(hostingController.view!).toOpaque()
        #else
        setError("Unsupported platform")
        return nil
        #endif
    }
}

// MARK: - Content Size Limits

/// Returns the size limits of a loaded window's root element content (macOS only):
/// the minimum is what the SwiftUI content reports for a zero size proposal, the
/// maximum for an infinite one. Flexible axes report a very large maximum; content
/// with a fixed root frame reports min == max, which lets a client make its window
/// non-user-resizable. Measures the bare root element, bypassing the window-level
/// modal/toast wrapper, which always expands to fill. Call after
/// actionUILoadHostingControllerFromURL has loaded the document.
/// Out parameters may be NULL to skip a component. Returns false (with an error set)
/// when the window is unknown or on non-macOS platforms.
@_cdecl("actionUIGetContentSizeLimits")
public func actionUIGetContentSizeLimits(
    _ windowUUID: UnsafePointer<CChar>,
    _ outMinWidth: UnsafeMutablePointer<Double>?,
    _ outMinHeight: UnsafeMutablePointer<Double>?,
    _ outMaxWidth: UnsafeMutablePointer<Double>?,
    _ outMaxHeight: UnsafeMutablePointer<Double>?
) -> CBool {
    clearError()

    #if canImport(AppKit)
    let swiftWindowUUID = String(cString: windowUUID)

    let limits = runOnMainActorSync {
        ActionUIModel.shared.contentSizeLimits(windowUUID: swiftWindowUUID)
    }
    guard let limits else {
        setError("Unknown windowUUID or no root element loaded: \(swiftWindowUUID)")
        return false
    }
    outMinWidth?.pointee = Double(limits.minSize.width)
    outMinHeight?.pointee = Double(limits.minSize.height)
    outMaxWidth?.pointee = Double(limits.maxSize.width)
    outMaxHeight?.pointee = Double(limits.maxSize.height)
    return true
    #else
    setError("Content size limits are only available on macOS")
    return false
    #endif
}

/*
@_cdecl("actionUILoadViewFromJSON")
public func actionUILoadViewFromJSON(
    _ jsonString: UnsafePointer<CChar>,
    _ windowUUID: UnsafePointer<CChar>,
    _ isContentView: CBool
) -> UnsafeMutableRawPointer? {
    clearError()
    
    let swiftJSONString = String(cString: jsonString)
    let swiftWindowUUID = String(cString: windowUUID)
    
    guard let data = swiftJSONString.data(using: .utf8) else {
        setError("Invalid UTF-8 in JSON string")
        return nil
    }
    
    return runOnMainActorSync {
        do {
            let element = try JSONDecoder().decode(ActionUI.ActionUIElement.self, from: data)
            
            _ = ActionUIModel.shared.loadDescription(element, windowUUID: swiftWindowUUID, format: .json, isRootReplacement: isContentView)
            
            let view = ActionUI.ActionUIView(element: element, windowUUID: swiftWindowUUID, model: ActionUIModel.shared)
            
            #if canImport(AppKit)
            let hostingController = NSHostingController(rootView: AnyView(view))
            hostingController.view.autoresizingMask = [.width, .height]
            return Unmanaged.passRetained(hostingController).toOpaque()
            #elseif canImport(UIKit)
            let hostingController = UIHostingController(rootView: view)
            return Unmanaged.passRetained(hostingController.view!).toOpaque()
            #else
            setError("Unsupported platform")
            return nil
            #endif
        } catch {
            setError("Failed to decode JSON: \(error)")
            return nil
        }
    }
}
*/

// MARK: - Runtime Structural Mutations

/// Converts a C ActionUIInsertPosition + param to Swift ActionUI.InsertPosition.
@inline(__always)
private func swiftInsertPosition(_ position: ActionUIInsertPosition, param: Int) -> ActionUI.InsertPosition {
    switch position {
    case ActionUIInsertPositionPrepend: return .prepend
    case ActionUIInsertPositionAt:      return .at(param)
    case ActionUIInsertPositionBefore:  return .before(siblingID: param)
    case ActionUIInsertPositionAfter:   return .after(siblingID: param)
    default:                            return .append
    }
}

/// Inserts a new element into a flat container identified by parentID.
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - parentID: The id of the container element that accepts insertions.
///   - json: Null-terminated UTF-8 JSON string encoding one element object
///     (e.g. `{"id":5,"type":"Text","properties":{"text":"hello"}}`).
///   - container: Optional null-terminated UTF-8 container name (e.g. `"children"`). Pass NULL to
///     auto-derive when the container has exactly one flat container.
///   - position: Insert position type (`ActionUIInsertPosition`).
///   - positionParam: Index for `ActionUIInsertPositionAt`; siblingID for
///     `ActionUIInsertPositionBefore`/`After`; ignored for Append/Prepend.
/// - Returns: The inserted element's id on success; `-1` on failure.
///   Call `actionUIGetLastError()` for details on failure.
@_cdecl("actionUIInsertElement")
public func actionUIInsertElement(
    _ windowUUID:     UnsafePointer<CChar>,
    _ parentID:       Int64,
    _ json:           UnsafePointer<CChar>,
    _ container:           UnsafePointer<CChar>?,
    _ position:       ActionUIInsertPosition,
    _ positionParam:  Int64
) -> Int64 {
    clearError()
    let swiftWindowUUID = String(cString: windowUUID)
    let swiftJSON       = String(cString: json)
    let swiftContainer       = container.map { String(cString: $0) }
    let swiftPosition   = swiftInsertPosition(position, param: Int(positionParam))

    return runOnMainActorSync {
        do {
            let id = try ActionUIModel.shared.insertElement(
                windowUUID: swiftWindowUUID,
                parentID: Int(parentID),
                json: swiftJSON,
                container: swiftContainer,
                position: swiftPosition
            )
            return Int64(id)
        } catch {
            setError("actionUIInsertElement: \(error)")
            return -1
        }
    }
}

/// Inserts a new row of cells into a Grid-style `rows` container identified by parentID.
/// Rows have no addressable identity — position must be Append, Prepend, or At;
/// Before/After will fail and return NULL.
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - parentID: The id of the Grid element.
///   - json: Null-terminated UTF-8 JSON string encoding an array of cell objects
///     (e.g. `[{"id":5,"type":"Text","properties":{"text":"R0C0"}},...]`).
///   - container: Optional null-terminated UTF-8 container name. Pass NULL to auto-derive.
///   - position: Insert position type. Before/After are invalid for row containers.
///   - positionParam: Row index for `ActionUIInsertPositionAt`; ignored otherwise.
/// - Returns: Heap-allocated null-terminated JSON array of inserted cell ids (e.g. `[5,6]`).
///   Caller must free with `actionUIFreeString`. Returns NULL on failure.
@_cdecl("actionUIInsertRow")
public func actionUIInsertRow(
    _ windowUUID:     UnsafePointer<CChar>,
    _ parentID:       Int64,
    _ json:           UnsafePointer<CChar>,
    _ container:           UnsafePointer<CChar>?,
    _ position:       ActionUIInsertPosition,
    _ positionParam:  Int64
) -> UnsafeMutablePointer<CChar>? {
    clearError()
    let swiftWindowUUID = String(cString: windowUUID)
    let swiftJSON       = String(cString: json)
    let swiftContainer       = container.map { String(cString: $0) }
    let swiftPosition   = swiftInsertPosition(position, param: Int(positionParam))

    return runOnMainActorSync {
        do {
            let ids = try ActionUIModel.shared.insertRow(
                windowUUID: swiftWindowUUID,
                parentID: Int(parentID),
                json: swiftJSON,
                container: swiftContainer,
                position: swiftPosition
            )
            guard let data = try? JSONSerialization.data(withJSONObject: ids),
                  let str = String(data: data, encoding: .utf8) else {
                setError("actionUIInsertRow: failed to serialize inserted ids")
                return nil
            }
            return actionStrdup(str)
        } catch {
            setError("actionUIInsertRow: \(error)")
            return nil
        }
    }
}

/// Removes the element with viewID from its parent container.
/// Refuses to remove the window's root element. Cascade-removes ViewModels for all descendants.
///
/// Note on Grid rows: only individual cells (which carry ids) are addressable.
/// A whole row has no synthetic id — remove each cell individually, or rebuild the parent.
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - viewID: The id of the element to remove.
/// - Returns: `true` on success; `false` on failure. Call `actionUIGetLastError()` for details.
@_cdecl("actionUIRemoveElement")
public func actionUIRemoveElement(
    _ windowUUID: UnsafePointer<CChar>,
    _ viewID:     Int64
) -> CBool {
    clearError()
    let swiftWindowUUID = String(cString: windowUUID)

    return runOnMainActorSync {
        do {
            try ActionUIModel.shared.removeElement(windowUUID: swiftWindowUUID, viewID: Int(viewID))
            return true
        } catch {
            setError("actionUIRemoveElement: \(error)")
            return false
        }
    }
}

// MARK: - Modal Presentation

/// Parse a JSON array of button descriptors into [DialogButton].
/// Expected JSON format: [{"title":"Delete","role":"destructive","actionID":"delete.confirmed"},...]
/// "role" values: omit or "default" -> nil, "cancel" -> .cancel, "destructive" -> .destructive
/// "actionID" is optional; omit or null for dismiss-only buttons.
/// Shared with the other adapters through ActionUIJSON.dialogButtons(from:).
private func parseDialogButtons(_ buttonsJSON: String?) -> [ActionUI.DialogButton]? {
    return ActionUIJSON.dialogButtons(from: buttonsJSON)
}

/// Presents a window-level modal sheet or full-screen cover loaded from a JSON/plist string.
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - jsonString: Null-terminated UTF-8 string containing the JSON or plist UI description.
///   - format: Null-terminated UTF-8 format string: "json" or "plist".
///   - style: `ActionUIModalStyleSheet` (0) or `ActionUIModalStyleFullScreenCover` (1).
///   - onDismissActionID: Optional null-terminated UTF-8 actionID fired on dismiss; pass NULL for none.
/// - Returns: `true` on success; `false` on failure — call `actionUIGetLastError()` for details.
@_cdecl("actionUIPresentModal")
public func actionUIPresentModal(
    _ windowUUID: UnsafePointer<CChar>,
    _ jsonString: UnsafePointer<CChar>,
    _ format: UnsafePointer<CChar>,
    _ style: ActionUIModalStyle,
    _ onDismissActionID: UnsafePointer<CChar>?
) -> CBool {
    clearError()

    let swiftWindowUUID   = String(cString: windowUUID)
    let swiftJSONString   = String(cString: jsonString)
    let swiftFormat       = String(cString: format)
    let swiftDismissID    = onDismissActionID.map { String(cString: $0) }
    let modalStyle: ActionUI.ModalStyle = style == ActionUIModalStyleFullScreenCover ? .fullScreenCover : .sheet

    guard let data = swiftJSONString.data(using: .utf8) else {
        setError("actionUIPresentModal: invalid UTF-8 in JSON string")
        return false
    }

    let success = runOnMainActorSync {
        do {
            try ActionUIModel.shared.presentModal(
                windowUUID: swiftWindowUUID,
                data: data,
                format: swiftFormat,
                style: modalStyle,
                onDismissActionID: swiftDismissID
            )
            return true
        } catch {
            setError("actionUIPresentModal: \(error.localizedDescription)")
            return false
        }
    }
    return success
}

/// Dismisses the active window-level modal for the given window.
/// Also fires the `onDismissActionID` if one was registered on present.
/// - Parameter windowUUID: Null-terminated UTF-8 window identifier.
@_cdecl("actionUIDismissModal")
public func actionUIDismissModal(_ windowUUID: UnsafePointer<CChar>) {
    let swiftWindowUUID = String(cString: windowUUID)
    runOnMainActorAsync {
        ActionUIModel.shared.dismissModal(windowUUID: swiftWindowUUID)
    }
}

/// Presents a window-level alert dialog.
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - title: Null-terminated UTF-8 alert title.
///   - message: Optional null-terminated UTF-8 alert message; pass NULL to omit.
///   - buttonsJSON: Optional null-terminated UTF-8 JSON array of button descriptors; pass NULL for a single default OK button.
///     Format: `[{"title":"Delete","role":"destructive","actionID":"delete.confirmed"},{"title":"Cancel","role":"cancel"}]`
/// - Returns: `true` on success.
@_cdecl("actionUIPresentAlert")
public func actionUIPresentAlert(
    _ windowUUID: UnsafePointer<CChar>,
    _ title: UnsafePointer<CChar>,
    _ message: UnsafePointer<CChar>?,
    _ buttonsJSON: UnsafePointer<CChar>?
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftTitle      = String(cString: title)
    let swiftMessage    = message.map { String(cString: $0) }
    let swiftButtons    = parseDialogButtons(buttonsJSON.map { String(cString: $0) })

    runOnMainActorAsync {
        if let swiftButtons {
            ActionUIModel.shared.presentAlert(windowUUID: swiftWindowUUID, title: swiftTitle, message: swiftMessage, buttons: swiftButtons)
        } else {
            ActionUIModel.shared.presentAlert(windowUUID: swiftWindowUUID, title: swiftTitle, message: swiftMessage)
        }
    }
    return true
}

/// Presents a window-level confirmation dialog (action sheet style on iOS).
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - title: Null-terminated UTF-8 dialog title.
///   - message: Optional null-terminated UTF-8 dialog message; pass NULL to omit.
///   - buttonsJSON: Null-terminated UTF-8 JSON array of button descriptors.
///     Format: `[{"title":"Save","actionID":"doc.save"},{"title":"Don't Save","role":"destructive","actionID":"doc.discard"},{"title":"Cancel","role":"cancel"}]`
/// - Returns: `true` on success.
@_cdecl("actionUIPresentConfirmationDialog")
public func actionUIPresentConfirmationDialog(
    _ windowUUID: UnsafePointer<CChar>,
    _ title: UnsafePointer<CChar>,
    _ message: UnsafePointer<CChar>?,
    _ buttonsJSON: UnsafePointer<CChar>
) -> CBool {
    clearError()

    let swiftWindowUUID = String(cString: windowUUID)
    let swiftTitle      = String(cString: title)
    let swiftMessage    = message.map { String(cString: $0) }
    let swiftButtons    = parseDialogButtons(String(cString: buttonsJSON)) ?? []

    runOnMainActorAsync {
        ActionUIModel.shared.presentConfirmationDialog(windowUUID: swiftWindowUUID, title: swiftTitle, message: swiftMessage, buttons: swiftButtons)
    }
    return true
}

/// Dismisses the active window-level alert or confirmation dialog for the given window.
/// Normally SwiftUI dismisses dialogs automatically when a button is tapped.
/// - Parameter windowUUID: Null-terminated UTF-8 window identifier.
@_cdecl("actionUIDismissDialog")
public func actionUIDismissDialog(_ windowUUID: UnsafePointer<CChar>) {
    let swiftWindowUUID = String(cString: windowUUID)
    runOnMainActorAsync {
        ActionUIModel.shared.dismissDialog(windowUUID: swiftWindowUUID)
    }
}

/// Presents a transient, auto-dismissing toast (snackbar) pinned above the window content.
/// If a toast is already visible the new one is queued and shown after it dismisses.
/// - Parameters:
///   - windowUUID: Null-terminated UTF-8 window identifier.
///   - message: Null-terminated UTF-8 toast text.
///   - duration: Seconds before auto-dismiss; pass 4.0 for the default.
///   - actionTitle: Optional null-terminated UTF-8 inline action button title (e.g. "Undo"); pass NULL to omit. Supply together with actionID.
///   - actionID: Optional null-terminated UTF-8 actionID fired when the inline action button is tapped; pass NULL to omit.
/// - Returns: `true` on success.
@_cdecl("actionUIPresentToast")
public func actionUIPresentToast(
    _ windowUUID: UnsafePointer<CChar>,
    _ message: UnsafePointer<CChar>,
    _ duration: Double,
    _ actionTitle: UnsafePointer<CChar>?,
    _ actionID: UnsafePointer<CChar>?
) -> CBool {
    clearError()

    let swiftWindowUUID  = String(cString: windowUUID)
    let swiftMessage     = String(cString: message)
    let swiftActionTitle = actionTitle.map { String(cString: $0) }
    let swiftActionID    = actionID.map { String(cString: $0) }

    runOnMainActorAsync {
        ActionUIModel.shared.presentToast(windowUUID: swiftWindowUUID, message: swiftMessage, duration: duration, actionTitle: swiftActionTitle, actionID: swiftActionID)
    }
    return true
}

/// Dismisses the current toast for the given window, showing the next queued toast if any.
/// The auto-dismiss timer and the inline action button call this for you.
/// - Parameter windowUUID: Null-terminated UTF-8 window identifier.
@_cdecl("actionUIDismissToast")
public func actionUIDismissToast(_ windowUUID: UnsafePointer<CChar>) {
    let swiftWindowUUID = String(cString: windowUUID)
    runOnMainActorAsync {
        ActionUIModel.shared.dismissToast(windowUUID: swiftWindowUUID)
    }
}

// MARK: - Memory Management

@_cdecl("actionUIFreeString")
public func actionUIFreeString(_ str: UnsafeMutablePointer<CChar>) {
    free(str)
}
