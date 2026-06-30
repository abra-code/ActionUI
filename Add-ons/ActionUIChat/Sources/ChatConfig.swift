// Add-ons/ActionUIChat/Sources/ChatConfig.swift
//
// Parses and validates the `Chat` element's JSON `properties` into a typed config.
//
// Two responsibilities, matching the per-element convention used by built-in views:
//   - `validate(_:_:)` is the element's `validateProperties` witness: type-check each
//     property, warn-and-drop anything ill-typed, never crash. Unknown keys are left
//     untouched (the verifier flags those separately).
//   - `init(_:_:)` reads the already-validated properties into a typed value with
//     defaults, for the view / store to consume.
//
// M1 scope: protocol selection, single-alignment appearance, role styling, the
// composer (`input`) config, the opaque `transport` object (validated by the chosen
// transport, not here), and the host-facing action IDs. `appearance.alignment:
// "dual"` and the agentic `surfaces` routing are parsed-or-noted but only honored in
// later milestones (M4 / M5).

import Foundation
import ActionUI

struct ChatConfig {

    /// Transcript layout. `single` (M1 default): every message leading / full-width,
    /// parties distinguished by tint + label. `dual` (M4): incoming leading, outgoing
    /// trailing. M1 renders `single` regardless and notes a `dual` request.
    enum Alignment: String {
        case single
        case dual
    }

    /// Composer submit policy - the Cmd+Return gap, solved inside the element.
    /// `return`: single-line field, Return submits. `modifierReturn`: multiline field,
    /// Return inserts a newline, Cmd+Return submits. `shiftReturnNewline`: treated like
    /// `return` in M1 (Shift+Return newline is a later refinement).
    enum SubmitPolicy: String {
        case `return`
        case modifierReturn = "modifier-return"
        case shiftReturnNewline = "shift-return-newline"
    }

    /// Per-role appearance. `side` drives layout only in `dual` alignment; in `single`
    /// only `label` and `tint` are used.
    struct RoleStyle {
        let side: String      // "leading" | "trailing" | "center"
        let label: String
        let tint: String      // an ActionUI color token, e.g. "accent", "secondary"
    }

    let protocolName: String
    let alignment: Alignment
    let showRoleLabels: Bool
    let theme: String                 // "auto" | "light" | "dark"
    let roles: [String: RoleStyle]

    let inputEnabled: Bool
    let placeholder: String
    let submitOn: SubmitPolicy

    let transport: [String: Any]      // opaque; the chosen transport validates it

    // Host-facing event IDs, dispatched through ActionUIModel.actionHandler.
    let sendActionID: String?
    let stopActionID: String?
    let messageActionID: String?
    let errorActionID: String?

    // MARK: - Defaults

    /// Default role styling, applied when `roles` (or a given role) is absent.
    static let defaultRoles: [String: RoleStyle] = [
        "local":  RoleStyle(side: "trailing", label: "You",   tint: "accent"),
        "agent":  RoleStyle(side: "leading",  label: "Agent", tint: "secondary"),
        "remote": RoleStyle(side: "leading",  label: "",      tint: "secondary"),
        "system": RoleStyle(side: "center",   label: "",      tint: "secondary"),
    ]

    // MARK: - Parse

    init(_ properties: [String: Any], _ logger: any ActionUILogger) {
        protocolName = (properties["protocol"] as? String) ?? "local"

        let appearance = properties["appearance"] as? [String: Any] ?? [:]
        let parsedAlignment = (appearance["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .single
        if parsedAlignment == .dual {
            logger.log("Chat appearance.alignment 'dual' is not yet honored (M4); rendering single-alignment", .verbose)
        }
        alignment = parsedAlignment
        showRoleLabels = (appearance["showRoleLabels"] as? Bool) ?? true
        theme = (appearance["theme"] as? String) ?? "auto"

        roles = Self.parseRoles(properties["roles"] as? [String: Any])

        let input = properties["input"] as? [String: Any] ?? [:]
        inputEnabled = (input["enabled"] as? Bool) ?? true
        placeholder = (input["placeholder"] as? String) ?? "Message"
        submitOn = (input["submitOn"] as? String).flatMap(SubmitPolicy.init(rawValue:)) ?? .return

        transport = properties["transport"] as? [String: Any] ?? [:]

        sendActionID = properties["sendActionID"] as? String
        stopActionID = properties["stopActionID"] as? String
        messageActionID = properties["messageActionID"] as? String
        errorActionID = properties["errorActionID"] as? String
    }

    private static func parseRoles(_ raw: [String: Any]?) -> [String: RoleStyle] {
        var resolved = defaultRoles
        guard let raw else { return resolved }
        for (key, value) in raw {
            guard let entry = value as? [String: Any] else { continue }
            let base = resolved[key] ?? RoleStyle(side: "leading", label: "", tint: "secondary")
            resolved[key] = RoleStyle(
                side: entry["side"] as? String ?? base.side,
                label: entry["label"] as? String ?? base.label,
                tint: entry["tint"] as? String ?? base.tint
            )
        }
        return resolved
    }

    // MARK: - Lookups used by the view

    func style(for role: ChatRole) -> RoleStyle {
        roles[role.rawValue] ?? Self.defaultRoles[role.rawValue]
            ?? RoleStyle(side: "leading", label: "", tint: "secondary")
    }

    // MARK: - Validation (the element's validateProperties witness)

    static func validate(_ properties: [String: Any], _ logger: any ActionUILogger) -> [String: Any] {
        var validated = properties

        if let proto = validated["protocol"] {
            if let name = proto as? String {
                let known = ["local", "acp", "openai-sse", "anthropic-sse", "custom"]
                if !known.contains(name) {
                    logger.log("Chat protocol '\(name)' is not a known transport; ignoring (defaults to 'local')", .warning)
                    validated["protocol"] = nil
                } else if name != "local" {
                    logger.log("Chat protocol '\(name)' is not implemented in this build; the 'local' transport will be used", .warning)
                }
            } else {
                logger.log("Chat protocol must be a String; ignoring", .warning)
                validated["protocol"] = nil
            }
        }

        for key in ["appearance", "roles", "input", "transport"] where validated[key] != nil {
            if !(validated[key] is [String: Any]) {
                logger.log("Chat \(key) must be an object; ignoring", .warning)
                validated[key] = nil
            }
        }

        for key in ["sendActionID", "stopActionID", "messageActionID", "errorActionID"] {
            if let value = validated[key], !(value is String) {
                logger.log("Chat \(key) must be a String; ignoring", .warning)
                validated[key] = nil
            }
        }

        return validated
    }
}
