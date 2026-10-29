// ActionUIRemote/JSONRPC.swift
//
// JSON-RPC 2.0 envelope codec for the ActionUI remote binding.
//
// One JSON value per line. A request is {"jsonrpc":"2.0","id":<int|string>,"method":"...","params":{...}};
// a request without "id" is a notification (executed, never answered). A JSON array is a batch.
// Replies are {"jsonrpc":"2.0","id":..,"result":...} or {"jsonrpc":"2.0","id":..,"error":{"code","message","data"}}.
// Params are always an object with named keys; positional params are rejected with -32602.
// See PROTOCOL.md for the normative description.
//
// Values are Swift-native, as Core's ActionUIJSON parses and writes them (Bool, Int, Double,
// String, arrays, string-keyed dictionaries, ActionUIJSONNull for null): FoundationEssentials, which
// ActionUI builds against on Linux, has no JSONSerialization. The socket server is elsewhere.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI

/// Error type for everything that crosses the remote boundary: codec failures, engine failures,
/// and errors thrown by host-registered handlers. `code` follows JSON-RPC 2.0 for the reserved
/// range and uses positive application codes (1001...) for ActionUI conditions.
///
/// `@unchecked Sendable` because `Error` refines `Sendable` and `data` is an arbitrary JSON-ready
/// value; it is only ever read to be encoded.
public struct ActionUIRemoteError: Error, @unchecked Sendable, CustomStringConvertible {
    public let code: Int
    public let message: String
    public let data: Any?

    public init(code: Int, message: String, data: Any? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public var description: String { "[\(code)] \(message)" }

    // JSON-RPC 2.0 reserved codes.
    public static let parseError     = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams  = -32602
    public static let internalError  = -32603

    // ActionUI application codes. Positive on purpose: they read better in logs than the
    // customary -32000...-32099 range and cannot collide with anything reserved.
    public static let unknownWindow         = 1001
    public static let unknownView           = 1002
    public static let engineFailure         = 1003
    public static let hostRefused           = 1004
    public static let mainThreadUnavailable = 1005
    /// The connection presented no valid token to a host that requires one. See PROTOCOL.md
    /// section 10: a host may restrict the bridge to the processes it spawned itself.
    public static let unauthenticated       = 1006

    public static func invalidParams(_ message: String) -> ActionUIRemoteError {
        ActionUIRemoteError(code: invalidParams, message: message)
    }
}

/// One decoded request. `id` is nil for a notification; otherwise it is the number (Int or
/// Double) or String the client sent, preserved so the reply carries it back unchanged. `params`
/// holds Swift-native values (see the file comment).
public struct JSONRPCRequest {
    public let id: Any?
    public let method: String
    public let params: [String: Any]

    public init(id: Any?, method: String, params: [String: Any]) {
        self.id = id
        self.method = method
        self.params = params
    }

    public var isNotification: Bool { id == nil }
}

/// A request object that failed validation, with whatever could still be recovered from it so the
/// server can answer correctly: the id (if one was detectable) and whether the object was a
/// notification. The rule the server applies, per JSON-RPC 2.0: an invalid request (-32600) is
/// always answered, with the id when known and null otherwise (the specification's own example
/// answers `{"jsonrpc":"2.0","method":1}` with a null id); any other rejection of a notification
/// is logged and not answered.
///
/// `@unchecked Sendable` for the same reason as `ActionUIRemoteError`: `Error` refines `Sendable`
/// and `id` is the client's number or String held as `Any?`, only ever read to be encoded.
public struct JSONRPCRejection: Error, @unchecked Sendable {
    public let id: Any?
    public let isNotification: Bool
    public let error: ActionUIRemoteError

    public init(id: Any?, isNotification: Bool, error: ActionUIRemoteError) {
        self.id = id
        self.isNotification = isNotification
        self.error = error
    }

    /// True when the server must send an error reply for this rejection.
    public var wantsReply: Bool {
        return error.code == ActionUIRemoteError.invalidRequest || !isNotification
    }
}

/// What one input line decodes to. A batch keeps per-entry validation results, because the
/// specification requires an individual error reply (with a null id) for each invalid entry
/// rather than a failure of the whole batch.
public enum JSONRPCIncoming {
    case single(Result<JSONRPCRequest, JSONRPCRejection>)
    case batch([Result<JSONRPCRequest, JSONRPCRejection>])
}

public enum JSONRPC {

    /// Upper bound on the number of entries in one batch. A batch executes inside a single
    /// main-thread hop, so an unbounded one is an unbounded stall of the host's UI; anything
    /// larger is rejected with -32600 before any of it runs.
    public static let maxBatchEntries = 4096

    /// Deepest nesting of arrays and objects the codec reads or writes, counting the request or
    /// reply object itself. ActionUIJSON parses and writes recursively, here on a connection
    /// queue whose thread has a 512 KB stack: measured on macOS 27, about 140 levels of objects
    /// overflowed it in a debug build (about 170 in release) and crashed the host. A deeper line
    /// is rejected with -32600 before it is parsed; a deeper result becomes -32603.
    public static let maxNestingDepth = 100

    // MARK: - Decoding

    /// Decode one line (without its trailing newline) into a request or a batch.
    ///
    /// Throws `ActionUIRemoteError` only when nothing can be recovered from the line and the
    /// server must answer with a null id: `parseError` for malformed JSON, `invalidRequest` for a
    /// well-formed value that is neither an object nor a non-empty array within `maxBatchEntries`,
    /// and for a line nested deeper than `maxNestingDepth`.
    /// A well-formed object that fails validation comes back as a `JSONRPCRejection` carrying the
    /// id and notification flag, so the reply (or the decision not to reply) can be made per object.
    public static func decode(line: Data) throws -> JSONRPCIncoming {
        guard !nestsTooDeep(line) else {
            throw ActionUIRemoteError(code: ActionUIRemoteError.invalidRequest,
                                      message: "Invalid request: nested deeper than \(maxNestingDepth) levels")
        }
        let value: Any
        do {
            // Invalid UTF-8 is a parse error, not text with replacement characters.
            guard let text = String(data: line, encoding: .utf8) else {
                throw ActionUIJSONError("the line is not UTF-8 text")
            }
            value = try ActionUIJSON.value(from: text)
        } catch {
            throw ActionUIRemoteError(code: ActionUIRemoteError.parseError, message: "Parse error: \(error)")
        }

        if let object = value as? [String: Any] {
            return .single(request(from: object))
        }
        if let array = value as? [Any] {
            guard !array.isEmpty else {
                throw ActionUIRemoteError(code: ActionUIRemoteError.invalidRequest, message: "Invalid request: empty batch")
            }
            guard array.count <= maxBatchEntries else {
                throw ActionUIRemoteError(code: ActionUIRemoteError.invalidRequest,
                                          message: "Invalid request: batch of \(array.count) entries exceeds the limit of \(maxBatchEntries)")
            }
            let entries: [Result<JSONRPCRequest, JSONRPCRejection>] = array.map { entry in
                guard let object = entry as? [String: Any] else {
                    return .failure(JSONRPCRejection(id: nil, isNotification: false,
                                                     error: ActionUIRemoteError(code: ActionUIRemoteError.invalidRequest,
                                                                                message: "Invalid request: batch entry is not an object")))
                }
                return request(from: object)
            }
            return .batch(entries)
        }
        throw ActionUIRemoteError(code: ActionUIRemoteError.invalidRequest, message: "Invalid request: expected an object or an array")
    }

    /// Validate one request object per JSON-RPC 2.0 plus this protocol's rule that params are named.
    /// The id is extracted first so that a later failure can still be answered with it.
    static func request(from object: [String: Any]) -> Result<JSONRPCRequest, JSONRPCRejection> {
        // id: absent or null means notification; otherwise a string or a number (not a bool).
        var id: Any? = nil
        var isNotification = true
        if let rawID = object["id"], !(rawID is ActionUIJSONNull) {
            isNotification = false
            let kind = type(of: rawID)
            if kind == Int.self || kind == Double.self {
                id = rawID
            } else if let s = rawID as? String {
                id = s
            } else {
                // The id is undetectable, so the reply carries null, as the specification requires.
                return .failure(JSONRPCRejection(id: nil, isNotification: false,
                                                 error: ActionUIRemoteError(code: ActionUIRemoteError.invalidRequest,
                                                                            message: "Invalid request: \"id\" must be a string or a number")))
            }
        }

        func reject(_ code: Int, _ message: String) -> Result<JSONRPCRequest, JSONRPCRejection> {
            return .failure(JSONRPCRejection(id: id, isNotification: isNotification,
                                             error: ActionUIRemoteError(code: code, message: message)))
        }

        guard let version = object["jsonrpc"] as? String, version == "2.0" else {
            return reject(ActionUIRemoteError.invalidRequest, "Invalid request: \"jsonrpc\" must be \"2.0\"")
        }
        guard let method = object["method"] as? String, !method.isEmpty else {
            return reject(ActionUIRemoteError.invalidRequest, "Invalid request: \"method\" must be a non-empty string")
        }

        var params: [String: Any] = [:]
        if let rawParams = object["params"], !(rawParams is ActionUIJSONNull) {
            guard let named = rawParams as? [String: Any] else {
                return reject(ActionUIRemoteError.invalidParams, "Invalid params: \"params\" must be an object with named keys")
            }
            params = named
        }

        return .success(JSONRPCRequest(id: id, method: method, params: params))
    }

    // MARK: - Encoding

    /// Encode a success reply. `result` must be JSON-ready (Swift-native scalars and containers,
    /// as ActionUIJSON writes them; on macOS Foundation values a host handler returns are
    /// converted first); nil encodes as null. A result that cannot be encoded is turned into an
    /// internal-error reply so the client always gets a well-formed answer.
    public static func encodeResult(id: Any?, result: Any?) -> Data {
        // Checked before anything walks the values recursively (see maxNestingDepth); the reply
        // object is the first level.
        guard nests(result, within: maxNestingDepth - 1) else {
            return encodeError(id: id, error: ActionUIRemoteError(code: ActionUIRemoteError.internalError,
                                                                  message: "Internal error: result nested deeper than \(maxNestingDepth - 1) levels"))
        }
        if nests(id, within: maxNestingDepth - 1) {
            let envelope: [String: Any] = [
                "jsonrpc": "2.0",
                "id": native(id) ?? ActionUIJSONNull(),
                "result": native(result) ?? ActionUIJSONNull(),
            ]
            if let text = try? ActionUIJSON.string(from: envelope) {
                return Data(text.utf8)
            }
        }
        let typeName = result.map { String(describing: type(of: $0)) } ?? "nil"
        return encodeError(id: id, error: ActionUIRemoteError(code: ActionUIRemoteError.internalError,
                                                              message: "Internal error: result of type \(typeName) is not JSON-encodable"))
    }

    /// Encode an error reply. `error.data` is included only when it is JSON-ready, and an id that
    /// is not JSON-ready is replaced by null, so an error reply is always well-formed.
    public static func encodeError(id: Any?, error: ActionUIRemoteError) -> Data {
        var errorObject: [String: Any] = [
            "code": error.code,
            "message": error.message,
        ]
        // The reply and error objects are the first two levels.
        if nests(error.data, within: maxNestingDepth - 2), let data = native(error.data), isEncodable(data) {
            errorObject["data"] = data
        }
        var safeID: Any = ActionUIJSONNull()
        if nests(id, within: maxNestingDepth - 1), let id = native(id), isEncodable(id) {
            safeID = id
        }
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": safeID,
            "error": errorObject,
        ]
        if let text = try? ActionUIJSON.string(from: envelope) {
            return Data(text.utf8)
        }
        // Reached only if `message` itself is not encodable (it is a String, so it never is).
        let fallback = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}"
        return Data(fallback.utf8)
    }

    private static func isEncodable(_ value: Any) -> Bool {
        return (try? ActionUIJSON.string(from: value)) != nil
    }

    /// Whether `value`'s arrays and objects (Swift or Foundation) nest no deeper than `limit`
    /// levels; a scalar or nil is 0. It stops descending past the limit, so its own recursion
    /// stays within it.
    private static func nests(_ value: Any?, within limit: Int) -> Bool {
        guard let value, !(value is String) else { return true }
        if let items = value as? [Any] {
            return limit > 0 && items.allSatisfy { nests($0, within: limit - 1) }
        }
        if let object = value as? [String: Any] {
            return limit > 0 && object.values.allSatisfy { nests($0, within: limit - 1) }
        }
        return true
    }

    /// Whether `line` nests arrays and objects deeper than `maxNestingDepth`, by a scan of its
    /// bytes in which brackets inside strings do not count. Malformed text is left to the parser.
    private static func nestsTooDeep(_ line: Data) -> Bool {
        return line.withUnsafeBytes { bytes in
            var depth = 0
            var inString = false
            var escaped = false
            for byte in bytes {
                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        escaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        inString = false
                    }
                    continue
                }
                switch byte {
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "["), UInt8(ascii: "{"):
                    depth += 1
                    if depth > maxNestingDepth {
                        return true
                    }
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    depth -= 1
                default:
                    break
                }
            }
            return false
        }
    }

    /// A value to encode, Swift-native: on macOS a host handler's result, or an id or error data a
    /// caller of these public functions passes, may be a Foundation object (NSNumber, NSString,
    /// NSNull), which ActionUIJSON does not write.
    private static func native(_ value: Any?) -> Any? {
        #if os(macOS)
        return value.map(FoundationBridge.native)
        #else
        return value
        #endif
    }

    /// Join already-encoded reply objects into one batch reply array. Callers omit replies for
    /// notifications before calling this; an empty list means "nothing to send" and returns nil,
    /// as the specification says a batch of only notifications gets no response at all.
    public static func encodeBatch(_ replies: [Data]) -> Data? {
        guard !replies.isEmpty else { return nil }
        var out = Data("[".utf8)
        for (index, reply) in replies.enumerated() {
            if index > 0 { out.append(UInt8(ascii: ",")) }
            out.append(reply)
        }
        out.append(UInt8(ascii: "]"))
        return out
    }
}
