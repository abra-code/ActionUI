// Add-ons/ActionUIChat/Sources/Core/ChatConfig.swift
//
// The ADD-ON side of the Chat element's `properties` block: parses the host-facing action
// IDs, delegates the visual / behavioral keys to the component's ChatConfiguration, and
// owns `validate(_:_:)` - the element's validateProperties witness (type-check each
// property, warn-and-drop anything ill-typed, never crash; unknown keys are left
// untouched - the verifier flags those separately).
//
// The element's OPERATIONAL settings (`protocol` + `transport`) are NOT here and are NOT
// document-declared: a host injects them at runtime into states["config"] (see ChatStore),
// where the transport is built once the config is viable. Keeping the wire protocol and
// the (subprocess-spawning) transport command out of the document is the security
// boundary - a document is data and must not name what the host executes or connects to.

import Foundation
import ActionUI

struct ChatConfig {

    /// The component's typed configuration, parsed from the same `properties` dictionary.
    /// attachEnabled / emitsEntryEvents derive from the matching action IDs being configured.
    let configuration: ChatConfiguration

    // Host-facing event IDs. The component emits ChatHostEvents; the sink installed by
    // Chat.buildView maps each event to its configured action ID and dispatches through
    // ActionUIModel.actionHandler.
    let sendActionID: String?
    let stopActionID: String?
    let messageActionID: String?
    let errorActionID: String?
    let approveToolActionID: String?  // fired when an agent requests tool permission
    let entryActionID: String?        // fired per finalized transcript entry (incremental persistence, P0-2)
    let resumeCheckpointActionID: String?  // fired at turn boundaries with the resume cursor that pairs with
                                      // entryActionID. The component only OFFERS a checkpoint when
                                      // emitsEntryEvents is true, and that derives from entryActionID below -
                                      // so configuring this alone yields nothing, by the component's contract
                                      // ("a host that is not storing entries is not offered one").
    let attachActionID: String?       // fired by the composer's attach (paperclip) button; the host mediates
                                      // the file picker and hands the file to its transport out of band. The
                                      // button appears only when this is configured. The ONLY new v2 host action ID -
                                      // every other v2 affordance flows as a ChatCommand to the transport.

    init(properties: [String: Any], logger: any ChatLogger) {
        sendActionID = properties["sendActionID"] as? String
        stopActionID = properties["stopActionID"] as? String
        messageActionID = properties["messageActionID"] as? String
        errorActionID = properties["errorActionID"] as? String
        approveToolActionID = properties["approveToolActionID"] as? String
        entryActionID = properties["entryActionID"] as? String
        resumeCheckpointActionID = properties["resumeCheckpointActionID"] as? String
        attachActionID = properties["attachActionID"] as? String

        var configuration = ChatConfiguration(dictionary: properties, logger: logger)
        configuration.attachEnabled = !(attachActionID?.isEmpty ?? true)
        configuration.emitsEntryEvents = !(entryActionID?.isEmpty ?? true)
        self.configuration = configuration
    }

    // MARK: - Validation (the element's validateProperties witness)

    // Properties only. `protocol` and `transport` are not properties (and not document-declared):
    // a host injects them at runtime into states["config"], which ChatStore consumes.
    static func validate(_ properties: [String: Any], _ logger: any ActionUILogger) -> [String: Any] {
        var validated = properties

        for key in ["appearance", "roles", "input", "surfaces", "features"] where validated[key] != nil {
            if !(validated[key] is [String: Any]) {
                logger.log("Chat \(key) must be an object; ignoring", .warning)
                validated[key] = nil
            }
        }

        if var featuresRaw = validated["features"] as? [String: Any] {
            for (feature, value) in featuresRaw {
                guard ["reactions", "editing", "deletion", "replies"].contains(feature) else {
                    logger.log("Chat features.\(feature) is not a recognized feature; ignoring", .warning)
                    featuresRaw[feature] = nil
                    continue
                }
                if !(value is Bool) {
                    logger.log("Chat features.\(feature) must be a Bool; ignoring", .warning)
                    featuresRaw[feature] = nil
                }
            }
            validated["features"] = featuresRaw
        }

        if var surfacesRaw = validated["surfaces"] as? [String: Any] {
            for (surface, value) in surfacesRaw {
                guard ["toolCalls", "thoughts", "plan", "diffs"].contains(surface) else {
                    logger.log("Chat surfaces.\(surface) is not a routable surface in this build; ignoring", .warning)
                    surfacesRaw[surface] = nil
                    continue
                }
                guard let mode = value as? String, ChatConfiguration.SurfaceMode(rawValue: mode) != nil else {
                    logger.log("Chat surfaces.\(surface) must be one of inline / collapsed / hidden / panel; ignoring", .warning)
                    surfacesRaw[surface] = nil
                    continue
                }
                if mode == ChatConfiguration.SurfaceMode.panel.rawValue {
                    logger.log("Chat surfaces.\(surface) 'panel' is not yet honored (M5); rendering inline", .verbose)
                }
            }
            validated["surfaces"] = surfacesRaw
        }

        for key in ["sendActionID", "stopActionID", "messageActionID", "errorActionID", "approveToolActionID", "entryActionID", "resumeCheckpointActionID", "attachActionID"] {
            if let value = validated[key], !(value is String) {
                logger.log("Chat \(key) must be a String; ignoring", .warning)
                validated[key] = nil
            }
        }

        // A checkpoint action ID without an entry action ID is inert, and silently so: the component
        // only OFFERS a resume cursor while emitsEntryEvents is true, and that derives from
        // entryActionID. Say it here, at document validation, where the author is actually looking -
        // otherwise the only signal is a verbose log line at runtime and the symptom is "my handler
        // never fires", which reads as a bug in the element.
        if !((validated["resumeCheckpointActionID"] as? String) ?? "").isEmpty,
           ((validated["entryActionID"] as? String) ?? "").isEmpty {
            logger.log("Chat resumeCheckpointActionID has no effect without entryActionID: a host that is not storing entries is not offered a resume cursor", .warning)
        }

        if let value = validated["readOnly"], !(value is Bool) {
            logger.log("Chat readOnly must be a Bool; ignoring", .warning)
            validated["readOnly"] = nil
        }

        if let value = validated["showFindBar"], !(value is Bool) {
            logger.log("Chat showFindBar must be a Bool; ignoring", .warning)
            validated["showFindBar"] = nil
        }

        return validated
    }
}
