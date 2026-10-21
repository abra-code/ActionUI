// Core/Common/ActionUIJSON.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
/// The values are Swift-native (Bool, Int, Double, String, ActionUIJSONNull, containers); Apple
/// adapters convert Foundation objects with FoundationBridge before they reach these helpers.
public enum ActionUIJSON {

    // MARK: - Values

    /// Convert a Swift-native value to JSON text: Bool, any integer or floating-point type, String,
    /// ActionUIJSONNull (as `null`), an Optional (nil as `null`), and arrays and string-keyed
    /// dictionaries of them (Core/Helpers/JSONValue.swift). Keys are in no fixed order; "/" is
    /// written as "\/". An inexact double is written in its shortest form (`0.1`).
    ///
    /// Throws for anything else (Date, a color, a coordinate, a Foundation object such as
    /// NSNumber or NSNull, which Apple adapters convert with FoundationBridge first) and for a
    /// non-finite number, which JSON cannot hold.
    public static func string(from value: Any) throws -> String {
        guard let json = JSONValue(any: value) else {
            throw ActionUIJSONError("Cannot convert value of type \(type(of: value)) to JSON")
        }
        do {
            return try json.text()
        } catch {
            throw ActionUIJSONError("Cannot convert \(value) to JSON: JSON has no non-finite numbers")
        }
    }

    /// Parse a JSON string into Swift-native values (fragments allowed: a bare string, number,
    /// bool or null is accepted): Bool, Int for every number that fits one without loss, Double
    /// for the rest, String, [Any], [String: Any], and ActionUIJSONNull for JSON `null`.
    public static func value(from json: String) throws -> Any {
        do {
            return try JSONValue(parsing: Data(json.utf8)).anyValue
        } catch {
            throw ActionUIJSONError("Failed to parse JSON: \(error)")
        }
    }

    // MARK: - Normalization

    /// The value unchanged. Values from `value(from:)` are already Swift-native (Bool, Int,
    /// Double, String), which is what this converted JSONSerialization's NSNumber and NSString to;
    /// kept so code written against the earlier ActionUIJSON still compiles.
    public static func normalized(_ value: Any) -> Any {
        return value
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
            array = (try? JSONValue(parsing: Data(json.utf8)))?.anyValue as? [[String: Any]]
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
            let role: DialogButtonRole? = switch dict["role"] as? String {
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
        if value is ActionUIJSONNull { return .append }

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
            // An integral number of any type (JSONNumber.int), so 2.7 is refused rather than
            // truncated; never a Bool, so `true` is not taken for 1.
            guard type(of: raw) != Bool.self, let i = JSONNumber.int(raw) else { throw failure }
            return i
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
