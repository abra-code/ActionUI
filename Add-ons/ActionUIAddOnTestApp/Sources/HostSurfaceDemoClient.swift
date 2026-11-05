// Add-ons/ActionUIAddOnTestApp/Sources/HostSurfaceDemoClient.swift
//
// The app side of the HostSurface demo (Resources/HostSurface.json): a Swift client that clears its
// surface with Metal to a color that cycles over time, and draws a trail of squares where the pointer
// drags (copied into the drawable with a blit, so no shaders are needed). Scrolling shifts the color,
// and the C key clears the trail. It shows the client contract: build on "created", resize on
// "changed", stop drawing while suspended, let go of everything on "destroyed", draw on frame
// callbacks, and take input. A real client (Rust wgpu, MoltenVK, ...) does the same through the C
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
    /// Where the pointer dragged, in pixels, by surfaceID.
    private var trails: [UInt64: [CGPoint]] = [:]
    private var scales: [UInt64: Double] = [:]
    private var hueShift = 0.0
    private static let squareSide = 16
    /// One white square, BGRA, the source of the trail's blits.
    private lazy var square: MTLBuffer? = {
        let bytes = [UInt8](repeating: 255, count: Self.squareSide * Self.squareSide * 4)
        return device?.makeBuffer(bytes: bytes, length: bytes.count)
    }()

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
            // The trail is blitted into the drawable.
            surface.metalLayer.framebufferOnly = false
            layers[surface.surfaceID] = surface.metalLayer
            fallthrough
        case .changed:
            surface.metalLayer.drawableSize = CGSize(width: surface.widthPixels, height: surface.heightPixels)
            scales[surface.surfaceID] = surface.scale
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
            trails[surface.surfaceID] = nil
            scales[surface.surfaceID] = nil
        }
    }

    func hostSurfaceInput(_ surface: HostSurfaceInfo, event: HostSurfaceInput) {
        let id = surface.surfaceID
        switch event.kind {
        case AUIHostInputPointerDown, AUIHostInputPointerDrag:
            let scale = scales[id] ?? surface.scale
            var trail = trails[id] ?? []
            trail.append(CGPoint(x: event.event.x * scale, y: event.event.y * scale))
            trails[id] = Array(trail.suffix(400))
        case AUIHostInputScroll:
            hueShift += event.event.deltaY / 200
        case AUIHostInputKeyDown:
            print("[HostSurface] key \(event.code) text \(event.text ?? "")")
            if event.code == "KeyC" {
                trails[id] = []
            }
        case AUIHostInputFocusIn, AUIHostInputFocusOut:
            print("[HostSurface] \(event.kind == AUIHostInputFocusIn ? "focus in" : "focus out")")
        default:
            return
        }
        fflush(stdout)
        ActionUIHostSurface.requestFrame(surfaceID: id)
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
        let phase = timestamp.truncatingRemainder(dividingBy: 6) / 6 * 2 * Double.pi + hueShift
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.5 + 0.4 * cos(phase), green: 0.5 + 0.4 * cos(phase - 2.1), blue: 0.5 + 0.4 * cos(phase + 2.1),
            alpha: 1)
        commands.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        drawTrail(surface.surfaceID, into: drawable.texture, commands: commands)
        commands.present(drawable)
        commands.commit()
    }

    private func drawTrail(_ surfaceID: UInt64, into texture: MTLTexture, commands: MTLCommandBuffer) {
        guard let square, let trail = trails[surfaceID], !trail.isEmpty,
              let blit = commands.makeBlitCommandEncoder() else {
            return
        }
        let side = Self.squareSide
        for point in trail {
            let x = Int(point.x) - side / 2
            let y = Int(point.y) - side / 2
            guard x >= 0, y >= 0, x + side <= texture.width, y + side <= texture.height else {
                continue
            }
            blit.copy(from: square, sourceOffset: 0, sourceBytesPerRow: side * 4, sourceBytesPerImage: side * side * 4,
                      sourceSize: MTLSize(width: side, height: side, depth: 1), to: texture, destinationSlice: 0,
                      destinationLevel: 0, destinationOrigin: MTLOrigin(x: x, y: y, z: 0))
        }
        blit.endEncoding()
    }
}
