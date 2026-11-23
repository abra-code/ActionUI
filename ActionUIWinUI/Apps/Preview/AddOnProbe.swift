// Apps/Preview/AddOnProbe.swift
/*
 An element built the way an add-on in its own package builds one: only ActionUI's public interface
 (ActionUIWinUIElement, RenderNode) and the shim's C functions. It shows its "text" property in a
 TextBlock, prefixed with "add-on: ", and takes the width it is offered. The preview registers it as
 "AddOnProbe" for Documents/AddOns.json, and again as "LinkedAddOnProbe" through the linked add-ons
 call below.
*/

import ActionUI
import CWinUI

enum AddOnProbe: ActionUIWinUIElement {
    static var valueType: Any.Type { Void.self }
    static var initialValue: (ViewModel) -> Any? { { _ in nil } }
    static var initialStates: (ViewModel) -> [String: Any] { { _ in [:] } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    static func makeView(_ node: RenderNode) -> OpaquePointer? {
        actionUIWinUITextBlockCreate()
    }

    static func update(_ view: OpaquePointer, _ node: RenderNode) {
        let text = node.properties["text"] as? String ?? ""
        _ = actionUIWinUITextBlockSetText(view, "add-on: \(text)")
    }

    static func expansion(_ node: RenderNode) -> ActionUIExpansion {
        .horizontal
    }
}

/// What a library that links add-ons defines (ActionUIAdwaita/Library on Linux): ActionUI calls it once,
/// before the first UI description loads, for hosts that cannot call an add-on's register(). Here it
/// registers the probe a second time, as "LinkedAddOnProbe", so Documents/AddOns.json shows that the
/// call arrives.
@c public func ActionUILinkedAddOns_register() {
    MainActor.assumeIsolated {
        ActionUIRegistry.shared.register(AddOnProbe.self, as: "LinkedAddOnProbe")
    }
}
