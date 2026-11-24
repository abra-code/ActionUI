// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurface+WinUI.swift
/*
 The HostSurface element on Windows, the counterpart of HostSurface.swift (the sample JSON and the properties are
 there): the same JSON over a frame sink, HostSurfaceView+WinUI.swift. "kind" "sink" is the frame sink, and so is
 "native" (the default) for now, as on Linux; "gl" (Linux) and an unknown kind draw a placeholder, as does content
 the trust policy does not let show the host's surface (.hostSurface; less-trusted content by default).

 Size: the ideal size (idealWidth, idealHeight; 320 x 240 by default) is the natural size, and the element grows to
 what it is offered, as the SwiftUI element takes the proposed size. frame and padding work as usual.

 "hidden" is applied by the element itself (handledBaseModifiers), so it can suspend the surface; like ActionUI's
 own hidden it keeps the element's space.
*/

#if os(Windows)

import ActionUI
import CWinUI

struct HostSurface: ActionUIWinUIElement {
    // Display-only element: no observable runtime value.
    static var valueType: Any.Type { Void.self }
    static var initialValue: (ViewModel) -> Any? { { model in model.value } }
    static var initialStates: (ViewModel) -> [String: Any] { { model in model.states } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    // The element suspends its surface while hidden, so it applies hidden itself.
    static var handledBaseModifiers: Set<String> { ["hidden"] }

    static func makeView(_ node: RenderNode) -> OpaquePointer? {
        guard let view = HostSurfaceView(windowUUID: node.windowUUID, viewID: node.element.id, model: node.model,
                                         logger: ActionUIModel.shared.logger) else {
            return nil
        }
        // Content the trust policy does not let show the host's surface (less-trusted content, by default) gets
        // the placeholder, and the client never hears of the element.
        let name = HostSurfaceProperties(node.properties, logger: ActionUIModel.shared.logger).surfaceName
        view.isRefused = !node.allowsLoggingOnce(.hostSurface(name), what: "showing host surface '\(name)'")
        node.state = view
        // The node takes over a reference of its own; the view keeps its own.
        return actionUIWinUIRetain(view.panel.pointer)
    }

    static func update(_ view: OpaquePointer, _ node: RenderNode) {
        guard let surface = node.state as? HostSurfaceView else { return }
        surface.isDisabled = node.isDisabled
        surface.update(HostSurfaceProperties(node.properties, logger: ActionUIModel.shared.logger))
    }

    /// It takes the size it is offered, both ways.
    static func expansion(_ node: RenderNode) -> ActionUIExpansion {
        .both
    }

    static func compression(_ node: RenderNode) -> ActionUIExpansion {
        .both
    }
}

#endif
