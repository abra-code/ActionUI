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
    if Thread.isMainThread {
        // Already on main thread - execute directly (zero overhead)
        return MainActor.assumeIsolated {
            operation()
        }
    } else {
        // On background thread - must block and wait
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                operation()
            }
        }
    }
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

private var cLoggerCallback: ActionUILoggerCallback? = nil

private class CLoggerBridge: ActionUILogger {
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

private var actionHandlers: [String: ActionUIActionHandler] = [:]
private var defaultActionHandler: ActionUIActionHandler? = nil

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

private var lastError: String? = nil

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

/// Convert any value to a JSON string safely, without risking ObjC exceptions.
/// `JSONSerialization.data(withJSONObject:)` throws an ObjC `NSException`
/// (not a Swift `Error`) when the top-level object is not a valid JSON
/// container (e.g. a bare String or Number).  ObjC exceptions bypass
/// Swift's `do/catch`, crashing the process.
///
/// This helper checks `isValidJSONObject` first and falls back to manual
/// serialization for scalar types that are valid JSON values but cannot be
/// a top-level `withJSONObject` argument.
private func safeJSONString(from value: Any) -> String? {
    // Arrays and dictionaries — the common path.
    if JSONSerialization.isValidJSONObject(value) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [])
            return String(data: data, encoding: .utf8)
        } catch {
            // Should not happen after isValidJSONObject, but handle gracefully.
            setError("Failed to convert value to JSON: \(error)")
            return nil
        }
    }

    // Scalar types that are valid JSON but not valid top-level NSJSONSerialization objects.
    switch value {
    case let s as String:
        // Wrap in an array, serialize, then strip the surrounding brackets.
        if let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
           let arr = String(data: data, encoding: .utf8) {
            // "[\"hello\"]" -> "\"hello\""
            let inner = arr.dropFirst(1).dropLast(1)
            return String(inner)
        }
        return nil
    case let n as NSNumber:
        // CFBoolean is bridged to NSNumber; detect bools by CFBooleanGetTypeID.
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return n.boolValue ? "true" : "false"
        }
        return "\(n)"
    case let b as Bool:
        return b ? "true" : "false"
    case let i as Int:
        return "\(i)"
    case let d as Double:
        return "\(d)"
    default:
        setError("Cannot convert value of type \(type(of: value)) to JSON")
        return nil
    }
}

private func valueToJSON(_ value: Any) -> String? {
    return safeJSONString(from: value)
}

private func jsonToValue(_ json: String) -> Any? {
    guard let data = json.data(using: .utf8) else {
        setError("Invalid UTF-8 in JSON string")
        return nil
    }
    
    do {
        return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    } catch {
        setError("Failed to parse JSON: \(error)")
        return nil
    }
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
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return Unmanaged.passRetained(hostingController.view!).toOpaque()
        #else
        setError("Unsupported platform")
        return nil
        #endif
    }
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

// MARK: - Modal Presentation

/// Parse a JSON array of button descriptors into [DialogButton].
/// Expected JSON format: [{"title":"Delete","role":"destructive","actionID":"delete.confirmed"},...]
/// "role" values: omit or "default" → nil, "cancel" → .cancel, "destructive" → .destructive
/// "actionID" is optional; omit or null for dismiss-only buttons.
private func parseDialogButtons(_ buttonsJSON: String?) -> [ActionUI.DialogButton]? {
    guard let json = buttonsJSON,
          let data = json.data(using: .utf8),
          let array = (try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])) as? [[String: Any]],
          !array.isEmpty else { return nil }

    return array.compactMap { dict -> ActionUI.DialogButton? in
        guard let title = dict["title"] as? String else { return nil }
        let role: SwiftUI.ButtonRole? = switch dict["role"] as? String {
            case "cancel": .cancel
            case "destructive": .destructive
            default: nil
        }
        let actionID = dict["actionID"] as? String
        return ActionUI.DialogButton(title: title, role: role, actionID: actionID)
    }
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

    var success = true
    runOnMainActorSync {
        do {
            try ActionUIModel.shared.presentModal(
                windowUUID: swiftWindowUUID,
                data: data,
                format: swiftFormat,
                style: modalStyle,
                onDismissActionID: swiftDismissID
            )
        } catch {
            setError("actionUIPresentModal: \(error.localizedDescription)")
            success = false
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

// MARK: - Memory Management

@_cdecl("actionUIFreeString")
public func actionUIFreeString(_ str: UnsafeMutablePointer<CChar>) {
    free(str)
}
