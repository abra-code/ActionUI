// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurface+Adwaita.swift
/*
 The HostSurface element on Linux, the counterpart of HostSurface.swift (the sample JSON and the properties are
 there): the same JSON over a frame sink, HostSurfaceView+Adwaita.swift. "kind" "native" (the default) and "sink"
 are the frame sink; "gl" is not available yet and draws a placeholder, as an unknown kind does.

 Size: the ideal size (idealWidth, idealHeight; 320 x 240 by default) is the natural size, and the element grows
 to what it is offered, as the SwiftUI element takes the proposed size. frame and padding work as usual.

 "hidden" is applied by the element itself (handledBaseModifiers), so it can suspend the surface; like ActionUI's
 own hidden it keeps the element's space. "disabled" makes the widget insensitive, as for any element.
*/

#if os(Linux)

import ActionUI
import CAdwaita

struct HostSurface: ActionUIAdwaitaElement {
    // Display-only element: no observable runtime value.
    static var valueType: Any.Type { Void.self }
    static var initialValue: (ViewModel) -> Any? { { model in model.value } }
    static var initialStates: (ViewModel) -> [String: Any] { { model in model.states } }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    static var insertableContainers: [String: ContainerShape]? { nil }

    // The element suspends its surface while hidden, so it applies hidden itself.
    static var handledBaseModifiers: Set<String> { ["hidden"] }

    static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        let made = HostSurfaceWidget.make(windowUUID: node.windowUUID, viewID: node.element.id, model: node.model,
                                          logger: ActionUIModel.shared.logger)
        node.state = made.view
        return OpaquePointer(made.widget)
    }

    static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        guard let view = node.state as? HostSurfaceView else { return }
        view.update(HostSurfaceProperties(node.properties, logger: ActionUIModel.shared.logger))
    }
}

#endif
