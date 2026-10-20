// Add-ons/ActionUIChat/Sources/Core/ChatConfig.swift
//
// The ADD-ON side of the Chat element's `properties` block: parses the host-facing action
// IDs and delegates the visual / behavioral keys to the component's ChatConfiguration.
// Both read the raw properties and ignore a value of the wrong type.
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
    let entryActionID: String?        // fired per finalized transcript entry (incremental persistence)
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
}
