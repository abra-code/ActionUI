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
// Scope: protocol selection, single-alignment appearance, role styling, the
// composer (`input`) config, the opaque `transport` object (validated by the chosen
// transport, not here), the agentic `surfaces` routing (M3: inline / collapsed /
// hidden; "panel" parses but renders inline until the M5 side panels), and the
// host-facing action IDs. `appearance.alignment: "dual"` is parsed-or-noted but
// only honored in M4.

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

    /// How an agentic surface presents. `inline`: in the transcript, expanded.
    /// `collapsed`: in the transcript, folded behind a disclosure. `hidden`: dropped.
    /// `panel` (a side region) is an M5 presentation; it parses today and renders inline.
    enum SurfaceMode: String {
        case inline
        case collapsed
        case hidden
        case panel
    }

    /// Routing for the agentic stream (design doc section 8). Only transports that
    /// emit these events are affected; a plain chat transport never produces them.
    struct Surfaces {
        let toolCalls: SurfaceMode    // default inline
        let thoughts: SurfaceMode     // default collapsed
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

    let surfaces: Surfaces

    // Host-facing event IDs, dispatched through ActionUIModel.actionHandler.
    let sendActionID: String?
    let stopActionID: String?
    let messageActionID: String?
    let errorActionID: String?
    let approveToolActionID: String?  // fired when an agent requests tool permission

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

        let surfacesRaw = properties["surfaces"] as? [String: Any] ?? [:]
        surfaces = Surfaces(
            toolCalls: (surfacesRaw["toolCalls"] as? String).flatMap(SurfaceMode.init(rawValue:)) ?? .inline,
            thoughts: (surfacesRaw["thoughts"] as? String).flatMap(SurfaceMode.init(rawValue:)) ?? .collapsed
        )

        sendActionID = properties["sendActionID"] as? String
        stopActionID = properties["stopActionID"] as? String
        messageActionID = properties["messageActionID"] as? String
        errorActionID = properties["errorActionID"] as? String
        approveToolActionID = properties["approveToolActionID"] as? String
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
#if os(macOS)
                let implemented = ["local", "acp"]
#else
                let implemented = ["local"]
#endif
                if !known.contains(name) {
                    logger.log("Chat protocol '\(name)' is not a known transport; ignoring (defaults to 'local')", .warning)
                    validated["protocol"] = nil
                } else if !implemented.contains(name) {
                    logger.log("Chat protocol '\(name)' is not implemented in this build; the 'local' transport will be used", .warning)
                }
            } else {
                logger.log("Chat protocol must be a String; ignoring", .warning)
                validated["protocol"] = nil
            }
        }

        if let transport = validated["transport"] as? [String: Any],
           (validated["protocol"] as? String) == "acp" {
            if let command = transport["command"] {
                if !(command is [String]) || (command as? [String])?.isEmpty != false {
                    logger.log("Chat transport.command must be a non-empty array of strings for protocol \"acp\"", .warning)
                }
            } else {
                logger.log("Chat protocol \"acp\" requires transport.command (the agent argv, e.g. [\"claude-code-acp\"])", .warning)
            }
        }

        for key in ["appearance", "roles", "input", "transport", "surfaces"] where validated[key] != nil {
            if !(validated[key] is [String: Any]) {
                logger.log("Chat \(key) must be an object; ignoring", .warning)
                validated[key] = nil
            }
        }

        if var surfacesRaw = validated["surfaces"] as? [String: Any] {
            for (surface, value) in surfacesRaw {
                guard ["toolCalls", "thoughts"].contains(surface) else {
                    logger.log("Chat surfaces.\(surface) is not a routable surface in this build; ignoring", .warning)
                    surfacesRaw[surface] = nil
                    continue
                }
                guard let mode = value as? String, SurfaceMode(rawValue: mode) != nil else {
                    logger.log("Chat surfaces.\(surface) must be one of inline / collapsed / hidden / panel; ignoring", .warning)
                    surfacesRaw[surface] = nil
                    continue
                }
                if mode == SurfaceMode.panel.rawValue {
                    logger.log("Chat surfaces.\(surface) 'panel' is not yet honored (M5); rendering inline", .verbose)
                }
            }
            validated["surfaces"] = surfacesRaw
        }

        for key in ["sendActionID", "stopActionID", "messageActionID", "errorActionID", "approveToolActionID"] {
            if let value = validated[key], !(value is String) {
                logger.log("Chat \(key) must be a String; ignoring", .warning)
                validated[key] = nil
            }
        }

        return validated
    }
}
