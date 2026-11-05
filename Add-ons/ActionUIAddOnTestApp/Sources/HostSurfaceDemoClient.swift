// Add-ons/ActionUIAddOnTestApp/Sources/HostSurfaceDemoClient.swift
//
// The app side of the HostSurface demo (Resources/HostSurface.json): a Swift client that clears its
// surface with Metal to a color that cycles over time. It shows the client contract: build on
// "created", resize on "changed", stop drawing while suspended, let go of everything on "destroyed",
// and draw on frame callbacks. A real client (Rust wgpu, MoltenVK, ...) does the same through the C
// interface. The toggles under the surface change its properties through the model, as a host would.

import Foundation
import Metal
import QuartzCore
import ActionUI
import ActionUISwiftAdapter
import ActionUIHostSurface

@MainActor
final class HostSurfaceDemoClient: HostSurfaceDelegate {
    static let shared = HostSurfaceDemoClient()

    private let device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()
    /// The layers of the live surfaces, by surfaceID.
    private var layers: [UInt64: CAMetalLayer] = [:]
    private var suspended: Set<UInt64> = []

    static func install() {
        ActionUIHostSurface.setDelegate(shared, forSurfaceName: "demo.metal")
        ActionUISwift.registerActionHandler(actionID: "hostSurface.animate") { _, windowUUID, viewID, _, _ in
            let on = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: viewID) as? Bool ?? false
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 90, propertyName: "continuous", value: on)
        }
        ActionUISwift.registerActionHandler(actionID: "hostSurface.hidden") { _, windowUUID, viewID, _, _ in
            let on = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: viewID) as? Bool ?? false
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 90, propertyName: "hidden", value: on)
        }
        ActionUISwift.registerActionHandler(actionID: "hostSurface.padding") { _, windowUUID, viewID, _, _ in
            let on = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: viewID) as? Bool ?? false
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 90, propertyName: "padding", value: on ? 24 : 0)
        }
    }

    func hostSurface(_ surface: HostSurfaceInfo, event: HostSurfaceEvent) {
        print("[HostSurface] \(event) #\(surface.surfaceID) view \(surface.viewID) \(surface.widthPixels)x\(surface.heightPixels) px at scale \(surface.scale)")
        fflush(stdout)
        switch event {
        case .created:
            surface.metalLayer.device = device
            surface.metalLayer.framebufferOnly = true
            layers[surface.surfaceID] = surface.metalLayer
            fallthrough
        case .changed:
            surface.metalLayer.drawableSize = CGSize(width: surface.widthPixels, height: surface.heightPixels)
            // Not continuous: one frame shows the new size.
            ActionUIHostSurface.requestFrame(surfaceID: surface.surfaceID)
        case .suspended:
            suspended.insert(surface.surfaceID)
        case .resumed:
            suspended.remove(surface.surfaceID)
            ActionUIHostSurface.requestFrame(surfaceID: surface.surfaceID)
        case .destroyed:
            layers[surface.surfaceID] = nil
            suspended.remove(surface.surfaceID)
        }
    }

    func hostSurfaceFrame(_ surface: HostSurfaceInfo, timestamp: Double) {
        guard let layer = layers[surface.surfaceID], !suspended.contains(surface.surfaceID),
              let queue, let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else {
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let phase = timestamp.truncatingRemainder(dividingBy: 6) / 6 * 2 * Double.pi
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.5 + 0.4 * cos(phase), green: 0.5 + 0.4 * cos(phase - 2.1), blue: 0.5 + 0.4 * cos(phase + 2.1),
            alpha: 1)
        commands.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}
