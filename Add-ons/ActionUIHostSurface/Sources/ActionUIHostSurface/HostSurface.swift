// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurface.swift
/*
 Sample JSON for HostSurface:
 {
   "type": "HostSurface",
   "id": 5,                       // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "surfaceName": "viewport",   // Required: String; binds the element to the client registered under this
                                  //           name (actionUIHostSurfaceSetDelegate). Fixed at load.
     "kind": "native",            // Optional: "native" (default): a CAMetalLayer on macOS and iOS, a frame sink
                                  //           on Linux ("sink" there too). "gl": a GL area (Linux). Kinds a
                                  //           platform lacks ("sink" and "gl" on Apple) draw a placeholder.
                                  //           Fixed at load.
     "continuous": false,         // Optional: Bool, default false; a frame callback at every display refresh
                                  //           while the surface is on screen. Otherwise one per requestFrame.
     "preferredFrameRate": 0,     // Optional: Number, default 0 (the display rate); frames per second hint
     "focusable": true,           // Optional: Bool, default true; a click or tap gives the surface keyboard
                                  //           focus. It never takes focus unasked; Tab moves focus on.
     "opaque": true,              // Optional: Bool, default true; false lets content behind the element show
                                  //           through transparent pixels the client draws
     "idealWidth": 320,           // Optional: Number, default 320; natural width in points
     "idealHeight": 240           // Optional: Number, default 240; natural height in points
   }
 }

 A rectangle in the layout whose pixels a client program draws with its own renderer (Metal, wgpu,
 MoltenVK, ANGLE). ActionUI lays it out like any other leaf; the client gets the CAMetalLayer, the
 size in points and pixels, the scale, frame ticks and input through the C interface in
 include/ActionUIHostSurface.h, or the Swift API (ActionUIHostSurface.setDelegate).

 Size: the element takes the size its parent proposes; where a dimension is unspecified it uses the
 ideal size. frame and padding work as usual.

 States: "size", [width, height] in points, updated when the surface size changes.

 No observable value (valueType Void).

 Baseline View properties (padding, hidden, frame, opacity, cornerRadius, disabled, accessibilityLabel,
 etc.) are inherited from base View. "hidden" is applied by the element itself, on the native view, so
 hiding never destroys the client's surface; a hidden surface is suspended and takes no input.
 "disabled" stops input and gives up keyboard focus.
 */

import SwiftUI
import ActionUI

struct HostSurface: ActionUIViewConstruction {

    static var valueType: Any.Type = Void.self

    // The registry would apply hidden as a conditional .hidden() modifier, which changes the view's
    // identity: SwiftUI rebuilds the representable and the client's surface would be destroyed.
    static var handledBaseModifiers: Set<String> { ["hidden"] }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = HostSurfaceProperties(properties, logger: logger)
        if case .unsupported = props.kind {
            return HostSurfacePlaceholder(surfaceName: props.surfaceName, hidden: props.hidden)
                .frame(idealWidth: props.idealWidth, idealHeight: props.idealHeight)
        }
        return HostSurfaceRepresentable(windowUUID: windowUUID, viewID: element.id, properties: props,
                                        model: model, logger: logger)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
    }

    // Baseline View modifiers (frame, padding, background, ...) are applied by the registry.
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var insertableContainers: [String: ContainerShape]? = nil
}

/// Drawn for a kind this platform lacks: a gray rectangle with the surface name.
private struct HostSurfacePlaceholder: SwiftUI.View {
    let surfaceName: String
    let hidden: Bool

    var body: some SwiftUI.View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.25))
            SwiftUI.Text(surfaceName.isEmpty ? "HostSurface" : surfaceName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
    }
}

/// SwiftUI's view of the element: a thin container. The surface view (the CAMetalLayer the client draws
/// into) is owned by the registry, one per (window, element), and the newest container adopts it. A
/// modifier change that rebuilds the representable (SwiftUI makes the new container before it dismantles
/// the old one) therefore moves the same surface instead of destroying and recreating it.
@MainActor
final class HostSurfaceContainer: HostSurfacePlatformView {
    let surface: HostSurfaceView
    private(set) var isDismantled = false

    /// How many containers were made, so a test can tell that SwiftUI rebuilt the element.
    static var madeCount = 0

    init(surface: HostSurfaceView) {
        self.surface = surface
        Self.madeCount += 1
        super.init(frame: .zero)
        adopt()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HostSurfaceContainer is not loaded from a nib")
    }

    #if os(macOS)
    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutSurface()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSurface()
    }
    #endif

    /// The surface fills the container, down to zero (a collapsed layout suspends it).
    private func layoutSurface() {
        guard surface.superview === self else {
            return
        }
        surface.frame = bounds
    }

    /// Moves the surface view into this container. Moving a view keeps its layer, so the client's
    /// swapchain on it stays valid. A new container starts at zero size until SwiftUI lays it out; the
    /// surface keeps its size until then, so a rebuild does not look like a collapse.
    func adopt() {
        surface.container = self
        if surface.superview !== self {
            surface.isMoving = true
            surface.removeFromSuperview()
            addSubview(surface)
            surface.isMoving = false
        }
        if bounds.isEmpty {
            surface.frame.origin = .zero
        } else {
            surface.frame = bounds
        }
        surface.refresh()
    }

    /// SwiftUI dropped this container. The surface view, when it is still in here, is suspended and torn
    /// down on the next main-loop turn unless a new container adopts it first.
    func dismantle() {
        isDismantled = true
        if surface.container === self {
            surface.scheduleTeardownCheck()
        }
    }
}

struct HostSurfaceRepresentable {
    let windowUUID: String
    let viewID: Int
    let properties: HostSurfaceProperties
    let model: ViewModel
    let logger: any ActionUILogger

    @MainActor
    func makeContainer() -> HostSurfaceContainer {
        let key = HostSurfaceRegistry.Key(windowUUID: windowUUID, viewID: viewID)
        let surface = HostSurfaceRegistry.shared.obtainSurface(for: key, surfaceName: properties.surfaceName) {
            HostSurfaceView(windowUUID: windowUUID, viewID: viewID, properties: properties, model: model,
                            logger: logger)
        }
        return HostSurfaceContainer(surface: surface)
    }

    @MainActor
    func updateContainer(_ container: HostSurfaceContainer, enabled: Bool) {
        container.surface.update(properties, enabled: enabled)
    }

    func fit(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: properties.idealWidth,
                                                           height: properties.idealHeight))
    }
}

#if os(macOS)
extension HostSurfaceRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> HostSurfaceContainer {
        makeContainer()
    }

    func updateNSView(_ container: HostSurfaceContainer, context: Context) {
        updateContainer(container, enabled: context.environment.isEnabled)
    }

    static func dismantleNSView(_ container: HostSurfaceContainer, coordinator: ()) {
        container.dismantle()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HostSurfaceContainer, context: Context) -> CGSize? {
        fit(proposal)
    }
}
#else
extension HostSurfaceRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> HostSurfaceContainer {
        makeContainer()
    }

    func updateUIView(_ container: HostSurfaceContainer, context: Context) {
        updateContainer(container, enabled: context.environment.isEnabled)
    }

    static func dismantleUIView(_ container: HostSurfaceContainer, coordinator: ()) {
        container.dismantle()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HostSurfaceContainer, context: Context) -> CGSize? {
        fit(proposal)
    }
}
#endif
