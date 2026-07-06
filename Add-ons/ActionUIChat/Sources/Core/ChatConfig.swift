// Add-ons/ActionUIChat/Sources/Core/ChatConfig.swift
//
// Parses the `Chat` element's JSON into a typed config, from two document blocks:
//   - `properties` (visual / presentation, modeled after SwiftUI modifiers):
//     appearance, role styling, the composer (`input`), the agentic `surfaces`
//     routing (M3: inline / collapsed / hidden; "panel" parses but renders inline
//     until the M5 side panels), and the host-facing action IDs.
//     `appearance.alignment: "dual"` is parsed-or-noted but only honored in M4.
//   - `config` (NON-VISUAL operational settings): `protocol` selection and the
//     `transport` object (interpreted by the chosen transport). Core stores the
//     config block VERBATIM - no central validation - so `init` (the one consumer)
//     checks these as it reads, warning and falling back rather than crashing.
//     Hosts inject runtime/session-specific values via setElementConfig between
//     loading a document and showing it.
//
// `validate(_:_:)` is the element's `validateProperties` witness (properties only):
// type-check each property, warn-and-drop anything ill-typed, never crash. Unknown
// keys are left untouched (the verifier flags those separately).

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
        let plan: SurfaceMode         // default panel (a pinned region ABOVE the transcript -
                                      // the plan is a status surface, never interleaved as chat;
                                      // "inline" is coerced to panel with a note)
        let diffs: SurfaceMode        // default inline (rendered by the DiffView component inside
                                      // the tool card's detail); hidden drops them; collapsed /
                                      // panel are coerced to inline with a note (the card's fold
                                      // already covers collapsing; a side panel is a later surface)
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
    let entryActionID: String?        // fired per finalized transcript entry (incremental persistence, P0-2)

    // Session transcript seam (P0-2).
    let readOnly: Bool           // history-viewer mode: no composer / menus, no transport start
    let initialContentRaw: Any?  // properties.content verbatim (a preview / testing convenience, NOT the
                                 // production restore path); the store decodes it ONCE at start

    // MARK: - Defaults

    /// Default role styling, applied when `roles` (or a given role) is absent.
    static let defaultRoles: [String: RoleStyle] = [
        "local":  RoleStyle(side: "trailing", label: "You",   tint: "accent"),
        "agent":  RoleStyle(side: "leading",  label: "Agent", tint: "secondary"),
        "remote": RoleStyle(side: "leading",  label: "",      tint: "secondary"),
        "system": RoleStyle(side: "center",   label: "",      tint: "secondary"),
    ]

    // MARK: - Parse

    init(properties: [String: Any], config: [String: Any], logger: any ActionUILogger) {
        // Operational settings come from the element's config block, stored verbatim by
        // core - so all checking happens here, on read.
        protocolName = Self.parseProtocol(config["protocol"], logger)

        if config["transport"] != nil, !(config["transport"] is [String: Any]) {
            logger.log("Chat config.transport must be an object; ignoring", .warning)
        }
        transport = config["transport"] as? [String: Any] ?? [:]
        // Protocol-specific validation of the transport block lives in the transport
        // itself (e.g. ACPChatTransport.init requires a non-empty `command`), so core
        // stays protocol-agnostic: it stores the block verbatim and the registry logs a
        // clear reason if the chosen transport rejects it and the element degrades.

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

        let surfacesRaw = properties["surfaces"] as? [String: Any] ?? [:]
        var planMode = (surfacesRaw["plan"] as? String).flatMap(SurfaceMode.init(rawValue:)) ?? .panel
        if planMode == .inline {
            logger.log("Chat surfaces.plan 'inline' is not a plan presentation (the plan is a pinned status surface); rendering as panel", .verbose)
            planMode = .panel
        }
        var diffsMode = (surfacesRaw["diffs"] as? String).flatMap(SurfaceMode.init(rawValue:)) ?? .inline
        if diffsMode == .collapsed || diffsMode == .panel {
            logger.log("Chat surfaces.diffs '\(diffsMode.rawValue)' renders inline (the tool card's fold covers collapsing; a diff panel is a later surface)", .verbose)
            diffsMode = .inline
        }
        surfaces = Surfaces(
            toolCalls: (surfacesRaw["toolCalls"] as? String).flatMap(SurfaceMode.init(rawValue:)) ?? .inline,
            thoughts: (surfacesRaw["thoughts"] as? String).flatMap(SurfaceMode.init(rawValue:)) ?? .collapsed,
            plan: planMode,
            diffs: diffsMode
        )

        sendActionID = properties["sendActionID"] as? String
        stopActionID = properties["stopActionID"] as? String
        messageActionID = properties["messageActionID"] as? String
        errorActionID = properties["errorActionID"] as? String
        approveToolActionID = properties["approveToolActionID"] as? String
        entryActionID = properties["entryActionID"] as? String

        readOnly = (properties["readOnly"] as? Bool) ?? false
        // A pre-populated transcript in `properties.content` - a preview / testing convenience only.
        // The production restore path is a runtime setElementState("content", ...), which the store
        // observes separately; a static UI document should not carry session data. Kept RAW here so it
        // is not re-decoded on every buildView; the store decodes it once at start.
        initialContentRaw = properties["content"]
    }

    /// Resolves config.protocol to a transport name. Any string is valid: which names
    /// resolve to a transport is a RUNTIME fact (whether the host linked and registered
    /// that transport's module), not something this parse can know, so there is no
    /// hard-coded name list here. The registry decides when the chat starts - a name it
    /// does not know degrades to "local" with a warning (ChatTransportRegistry.make). An
    /// absent or non-string value defaults to "local".
    private static func parseProtocol(_ raw: Any?, _ logger: any ActionUILogger) -> String {
        guard let raw else {
            return "local"
        }
        guard let name = raw as? String else {
            logger.log("Chat config.protocol must be a String; defaulting to 'local'", .warning)
            return "local"
        }
        return name
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

    // Properties only: `protocol` and `transport` live in the element's config block,
    // which core stores verbatim - init() checks those as it reads them.
    static func validate(_ properties: [String: Any], _ logger: any ActionUILogger) -> [String: Any] {
        var validated = properties

        for key in ["appearance", "roles", "input", "surfaces"] where validated[key] != nil {
            if !(validated[key] is [String: Any]) {
                logger.log("Chat \(key) must be an object; ignoring", .warning)
                validated[key] = nil
            }
        }

        if var surfacesRaw = validated["surfaces"] as? [String: Any] {
            for (surface, value) in surfacesRaw {
                guard ["toolCalls", "thoughts", "plan", "diffs"].contains(surface) else {
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

        for key in ["sendActionID", "stopActionID", "messageActionID", "errorActionID", "approveToolActionID", "entryActionID"] {
            if let value = validated[key], !(value is String) {
                logger.log("Chat \(key) must be a String; ignoring", .warning)
                validated[key] = nil
            }
        }

        if let value = validated["readOnly"], !(value is Bool) {
            logger.log("Chat readOnly must be a Bool; ignoring", .warning)
            validated["readOnly"] = nil
        }

        return validated
    }

    // MARK: - Transport-command security guard (P0-3)

    /// Strips a document-origin `transport.command` from a config block. A `transport.command` is an
    /// argv that spawns a subprocess (e.g. the ACP transport); an ActionUI document is data and may
    /// come from anywhere, so spawning a subprocess is a host privilege the document must not reach.
    /// A command is honored ONLY when the host injected the whole `transport` at runtime via
    /// setElementConfig (`transportHostInjected` == true, trusted host code); a command that arrived
    /// from the JSON document is STRIPPED, so the element cannot spawn what a document requested and
    /// the transport degrades to `local`. Pure (takes the origin as a parameter) so it is
    /// unit-testable; `Chat.buildView` supplies the origin.
    static func applyingTransportCommandGuard(_ config: [String: Any], transportHostInjected: Bool,
                                              logger: any ActionUILogger) -> [String: Any] {
        guard !transportHostInjected,
              var transport = config["transport"] as? [String: Any],
              transport["command"] != nil else {
            return config
        }
        logger.log("Chat: a transport.command from the document is rejected (spawning a subprocess is a host privilege, not a document's). To launch a subprocess transport, inject it at runtime via setElementConfig from trusted host code. Degrading to 'local'.", .warning)
        transport["command"] = nil
        var gated = config
        gated["transport"] = transport
        return gated
    }
}
