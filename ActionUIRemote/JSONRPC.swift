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
// This file is pure Foundation and platform independent; the socket server is elsewhere.

import Foundation

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

    public static func invalidParams(_ message: String) -> ActionUIRemoteError {
        ActionUIRemoteError(code: invalidParams, message: message)
    }
}

/// One decoded request. `id` is nil for a notification; otherwise it is the NSNumber or String
/// the client sent, preserved verbatim so the reply carries it back unchanged.
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
/// and `id` is the client's NSNumber or String held as `Any?`, only ever read to be encoded.
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

    // MARK: - Decoding

    /// Decode one line (without its trailing newline) into a request or a batch.
    ///
    /// Throws `ActionUIRemoteError` only when nothing can be recovered from the line and the
    /// server must answer with a null id: `parseError` for malformed JSON, `invalidRequest` for a
    /// well-formed value that is neither an object nor a non-empty array within `maxBatchEntries`.
    /// A well-formed object that fails validation comes back as a `JSONRPCRejection` carrying the
    /// id and notification flag, so the reply (or the decision not to reply) can be made per object.
    public static func decode(line: Data) throws -> JSONRPCIncoming {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: line, options: [.allowFragments])
        } catch {
            throw ActionUIRemoteError(code: ActionUIRemoteError.parseError, message: "Parse error: \(error.localizedDescription)")
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
        if let rawID = object["id"], !(rawID is NSNull) {
            isNotification = false
            if let n = rawID as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                id = n
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
        if let rawParams = object["params"], !(rawParams is NSNull) {
            guard let named = rawParams as? [String: Any] else {
                return reject(ActionUIRemoteError.invalidParams, "Invalid params: \"params\" must be an object with named keys")
            }
            params = named
        }

        return .success(JSONRPCRequest(id: id, method: method, params: params))
    }

    // MARK: - Encoding

    /// Encode a success reply. `result` must be JSON-ready (Foundation containers and scalars,
    /// as produced by ActionUIJSON); nil encodes as null. A result that JSONSerialization cannot
    /// encode is turned into an internal-error reply so the client always gets a well-formed answer.
    public static func encodeResult(id: Any?, result: Any?) -> Data {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result ?? NSNull(),
        ]
        if JSONSerialization.isValidJSONObject(envelope),
           let data = try? JSONSerialization.data(withJSONObject: envelope, options: []) {
            return data
        }
        let typeName = result.map { String(describing: type(of: $0)) } ?? "nil"
        return encodeError(id: id, error: ActionUIRemoteError(code: ActionUIRemoteError.internalError,
                                                              message: "Internal error: result of type \(typeName) is not JSON-encodable"))
    }

    /// Encode an error reply. `error.data` is included only when it is JSON-ready, and an id that
    /// is not JSON-ready is replaced by null, so this can never raise the ObjC exception that
    /// JSONSerialization throws for an invalid object (which Swift cannot catch).
    public static func encodeError(id: Any?, error: ActionUIRemoteError) -> Data {
        var errorObject: [String: Any] = [
            "code": error.code,
            "message": error.message,
        ]
        if let data = error.data, JSONSerialization.isValidJSONObject(["d": data]) {
            errorObject["data"] = data
        }
        var safeID: Any = NSNull()
        if let id, JSONSerialization.isValidJSONObject(["i": id]) {
            safeID = id
        }
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": safeID,
            "error": errorObject,
        ]
        if JSONSerialization.isValidJSONObject(envelope),
           let data = try? JSONSerialization.data(withJSONObject: envelope, options: []) {
            return data
        }
        // Reached only if `message` itself is not encodable (it is a String, so it never is).
        let fallback = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}"
        return Data(fallback.utf8)
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
