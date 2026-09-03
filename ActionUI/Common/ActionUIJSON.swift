// Common/ActionUIJSON.swift

import SwiftUI

/// Error raised by the ActionUIJSON helpers. `message` carries the exact text the C adapter
/// used to report through actionUIGetLastError(), so adapters that surface a last-error string
/// can forward it unchanged.
public struct ActionUIJSONError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Shared JSON conversion helpers for the language adapters (C, remote, and whatever wraps them).
///
/// Every adapter crosses its boundary with JSON strings: element values, properties, states, rows,
/// action context, dialog buttons, insert positions. Keeping the conversion in one place means the
/// C adapter, the remote server, and the in-process Python and Node modules cannot drift from each
/// other in what they accept or produce.
///
/// Behavior is intentionally identical to the private helpers the C adapter shipped before this
/// type existed: same accepted inputs, same output text, same error messages.
public enum ActionUIJSON {

    // MARK: - Values

    /// Convert any value to a JSON string safely, without risking ObjC exceptions.
    ///
    /// `JSONSerialization.data(withJSONObject:)` throws an ObjC `NSException` (not a Swift
    /// `Error`) when the top-level object is not a valid JSON container (e.g. a bare String or
    /// Number). ObjC exceptions bypass Swift's `do/catch`, crashing the process. This helper
    /// checks `isValidJSONObject` first and falls back to manual serialization for scalar types
    /// that are valid JSON values but cannot be a top-level `withJSONObject` argument.
    ///
    /// Supported: JSON-valid arrays and dictionaries, String, NSNumber (Bool detected via
    /// CFBoolean), Bool, Int, Double. Anything else (Date, Color, coordinates, ...) throws.
    public static func string(from value: Any) throws -> String {
        // Arrays and dictionaries - the common path.
        if JSONSerialization.isValidJSONObject(value) {
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [])
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ActionUIJSONError("Failed to convert value to JSON: output is not UTF-8")
                }
                return text
            } catch let error as ActionUIJSONError {
                throw error
            } catch {
                // Should not happen after isValidJSONObject, but handle gracefully.
                throw ActionUIJSONError("Failed to convert value to JSON: \(error)")
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
            throw ActionUIJSONError("Failed to convert string to JSON")
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
            throw ActionUIJSONError("Cannot convert value of type \(type(of: value)) to JSON")
        }
    }

    /// Parse a JSON string into a Foundation value (fragments allowed: a bare string, number,
    /// bool or null is accepted). JSON `null` comes back as `NSNull`, as JSONSerialization
    /// produces it; callers that want Swift `nil` for it should test `is NSNull`.
    public static func value(from json: String) throws -> Any {
        guard let data = json.data(using: .utf8) else {
            throw ActionUIJSONError("Invalid UTF-8 in JSON string")
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        } catch {
            throw ActionUIJSONError("Failed to parse JSON: \(error)")
        }
    }

    // MARK: - Dialog buttons

    /// Parse dialog button descriptors into `[DialogButton]`.
    ///
    /// Accepts either a JSON string of the form
    /// `[{"title":"Delete","role":"destructive","actionID":"delete.confirmed"},...]`
    /// or an already-decoded `[[String: Any]]` of the same shape.
    /// "role" values: omit or "default" -> nil, "cancel" -> .cancel, "destructive" -> .destructive.
    /// "actionID" is optional; omit or null for dismiss-only buttons.
    /// Returns nil for nil input, unparsable input, a non-array, or an empty array.
    /// Entries without a string "title" are skipped.
    public static func dialogButtons(from value: Any?) -> [DialogButton]? {
        let array: [[String: Any]]?
        switch value {
        case let json as String:
            guard let data = json.data(using: .utf8) else { return nil }
            array = (try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])) as? [[String: Any]]
        case let decoded as [[String: Any]]:
            array = decoded
        case let anyArray as [Any]:
            // Per-element, keeping the valid subset: this matches the WebKit JS adapter's copy of
            // this parser, which takes a JS array and must not lose every button over one bad entry.
            array = anyArray.compactMap { $0 as? [String: Any] }
        default:
            array = nil
        }
        guard let array, !array.isEmpty else { return nil }

        return array.compactMap { dict -> DialogButton? in
            guard let title = dict["title"] as? String else { return nil }
            let role: ButtonRole? = switch dict["role"] as? String {
                case "cancel": .cancel
                case "destructive": .destructive
                default: nil
            }
            let actionID = dict["actionID"] as? String
            return DialogButton(title: title, role: role, actionID: actionID)
        }
    }

    // MARK: - Insert position

    /// Parse the JSON object form of an insert position:
    /// `{"kind":"append"}`, `{"kind":"prepend"}`, `{"kind":"at","index":n}`,
    /// `{"kind":"before","siblingID":n}`, `{"kind":"after","siblingID":n}`.
    /// A bare string "append" or "prepend" is accepted as shorthand. `nil` means append.
    /// Throws `ActionUIJSONError` for an unknown kind, a missing or non-integer parameter,
    /// or any other shape.
    public static func insertPosition(from value: Any?) throws -> InsertPosition {
        guard let value else { return .append }
        if value is NSNull { return .append }

        let kind: String
        let dict: [String: Any]
        switch value {
        case let s as String:
            kind = s
            dict = [:]
        case let d as [String: Any]:
            guard let k = d["kind"] as? String else {
                throw ActionUIJSONError("Insert position object is missing a string \"kind\"")
            }
            kind = k
            dict = d
        default:
            throw ActionUIJSONError("Insert position must be an object with a \"kind\" or a string")
        }

        func integer(_ key: String) throws -> Int {
            let failure = ActionUIJSONError("Insert position \"\(kind)\" requires an integer \"\(key)\"")
            guard let raw = dict[key] else { throw failure }
            // A JSON-decoded number is an NSNumber, and so is a JSON bool on Darwin (CFBoolean):
            // reject the bool here, before any `as? Int` bridging could turn `true` into 1, and
            // require an exact integer so 2.7 is refused rather than truncated.
            if let n = raw as? NSNumber {
                guard CFGetTypeID(n) != CFBooleanGetTypeID(), let i = Int(exactly: n) else { throw failure }
                return i
            }
            if let i = raw as? Int {
                return i
            }
            throw failure
        }

        switch kind {
        case "append":  return .append
        case "prepend": return .prepend
        case "at":      return .at(try integer("index"))
        case "before":  return .before(siblingID: try integer("siblingID"))
        case "after":   return .after(siblingID: try integer("siblingID"))
        default:
            throw ActionUIJSONError("Unknown insert position kind \"\(kind)\" (expected append, prepend, at, before, after)")
        }
    }

    // MARK: - Modal style

    /// Map a modal style name to `ModalStyle`. `nil` and "sheet" mean `.sheet`;
    /// "fullScreenCover" means `.fullScreenCover`; anything else throws.
    public static func modalStyle(from name: String?) throws -> ModalStyle {
        switch name {
        case nil, "sheet":         return .sheet
        case "fullScreenCover":    return .fullScreenCover
        case .some(let other):
            throw ActionUIJSONError("Unknown modal style \"\(other)\" (expected sheet or fullScreenCover)")
        }
    }
}
