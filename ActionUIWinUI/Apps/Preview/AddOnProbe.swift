// Apps/Preview/AddOnProbe.swift
/*
 An element built the way an add-on in its own package builds one: only ActionUI's public interface
 (ActionUIWinUIElement, RenderNode) and the shim's C functions. It shows its "text" property in a
 TextBlock, prefixed with "add-on: ", and takes the width it is offered. The preview registers it as
 "AddOnProbe" for Documents/AddOns.json.
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
