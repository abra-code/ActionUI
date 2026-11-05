// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/ActionUIHostSurface.swift
//
// Public entry points of the ActionUIHostSurface add-on: registration, the Swift client API, and the
// plain C functions declared in include/ActionUIHostSurface.h (for C, C++, Rust and the other
// language adapters).
//
// This library is a separately linkable ActionUI add-on. It compiles against ActionUI's public API but
// does not link the ActionUI static library; the host app links ActionUI and this add-on and registers
// the element once at launch, before any window that uses "HostSurface" is built.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import QuartzCore
import ActionUI
@_exported import CActionUIHostSurface

public enum ActionUIHostSurface {

    /// Registers the `HostSurface` element type with the shared ActionUI registry. Call once at app
    /// launch, before building any window that uses it. A second call re-binds the same token.
    @MainActor
    public static func register() {
        ActionUIRegistry.shared.register(HostSurface.self)   // JSON token: "HostSurface"
    }

    /// Binds a Swift client to every HostSurface element whose "surfaceName" is `surfaceName`, in every
    /// window, now and later; nil unbinds. The registry keeps a strong reference until the name is
    /// bound to another client or unbound. The rules are those of actionUIHostSurfaceSetDelegate:
    /// live surfaces are announced at once, the outgoing client gets "destroyed" first, and a call
    /// made inside a callback takes effect when the callback returns.
    @MainActor
    public static func setDelegate(_ delegate: (any HostSurfaceDelegate)?, forSurfaceName surfaceName: String) {
        HostSurfaceRegistry.shared.setBinding(delegate.map { HostSurfaceBinding(.swift($0)) }, for: surfaceName)
    }

    /// Asks for one frame callback at the next display refresh. Any thread; never waits. Does nothing
    /// when `surfaceID` is not a live surface.
    public static func requestFrame(surfaceID: UInt64) {
        runOnMainWithoutWaiting {
            HostSurfaceRegistry.shared.liveSurface(surfaceID)?.requestFrame()
        }
    }

    /// Sets the cursor shown over the surface (an AUIHostCursor value). Returns false when `surfaceID` is
    /// not a live surface or `cursor` is not an AUIHostCursor value.
    @MainActor
    @discardableResult
    public static func setCursor(_ cursor: Int32, surfaceID: UInt64) -> Bool {
        guard HostSurfaceView.isKnownCursor(cursor),
              let surface = HostSurfaceRegistry.shared.liveSurface(surfaceID) else {
            return false
        }
        surface.setCursor(cursor)
        return true
    }

    /// Turns frame callbacks at every display refresh on or off, overriding the element's
    /// "continuous" property until the property changes value. Any thread; never waits.
    public static func setContinuous(_ continuous: Bool, surfaceID: UInt64) {
        runOnMainWithoutWaiting {
            HostSurfaceRegistry.shared.liveSurface(surfaceID)?.setContinuousOverride(continuous)
        }
    }
}

// MARK: - Swift client API

public enum HostSurfaceEvent: Sendable {
    case created, changed, suspended, resumed, destroyed
}

/// One surface as the client sees it. `metalLayer` is valid until the "destroyed" event for this
/// `surfaceID` returns.
@MainActor
public struct HostSurfaceInfo {
    /// Unique for the life of the process; a new one with every "created".
    public let surfaceID: UInt64
    public let windowUUID: String
    public let viewID: Int
    public let metalLayer: CAMetalLayer
    public let widthPoints: Double
    public let heightPoints: Double
    /// Pixels per point.
    public let scale: Double
    public let widthPixels: Int
    public let heightPixels: Int
}

/// A Swift client of HostSurface elements. Every method runs on the main thread. A client that renders
/// on its own thread stops and joins it in "destroyed" before returning.
@MainActor
public protocol HostSurfaceDelegate: AnyObject {
    func hostSurface(_ surface: HostSurfaceInfo, event: HostSurfaceEvent)
    /// `timestamp`: the target presentation time of the frame in seconds, on the display clock. Use
    /// differences only.
    func hostSurfaceFrame(_ surface: HostSurfaceInfo, timestamp: Double)
    /// Pointer, touch, scroll, gesture, key and focus input; see AUIHostInputEvent in the header.
    func hostSurfaceInput(_ surface: HostSurfaceInfo, event: HostSurfaceInput)
}

extension HostSurfaceDelegate {
    public func hostSurfaceFrame(_ surface: HostSurfaceInfo, timestamp: Double) {}
    public func hostSurfaceInput(_ surface: HostSurfaceInfo, event: HostSurfaceInput) {}
}

/// One input event for a Swift client: the C struct's numbers, and its strings as Swift strings.
public struct HostSurfaceInput: Sendable {
    /// The numeric fields of AUIHostInputEvent (`code` and `text` are NULL here; use the properties).
    public let event: AUIHostInputEvent
    /// The W3C UI Events "code" of the key ("KeyA", "ArrowLeft"); "" when unknown or not a key event.
    public let code: String
    /// The text a key produced, or nil.
    public let text: String?

    public var kind: AUIHostInputKind { AUIHostInputKind(rawValue: UInt32(bitPattern: event.kind)) }
}

extension AUIHostInputEvent: @retroactive @unchecked Sendable {}

// MARK: - C interface (include/ActionUIHostSurface.h)

/// Plain C entry point for registration, callable from every adapter without the Swift or
/// Objective-C runtime. Main thread; `MainActor.assumeIsolated` traps otherwise.
@c
public func ActionUIHostSurface_register() {
    MainActor.assumeIsolated {
        ActionUIHostSurface.register()
    }
}

@c
public func actionUIHostSurfaceSetDelegate(_ surfaceName: UnsafePointer<CChar>?,
                                           _ delegate: UnsafePointer<AUIHostSurfaceDelegate>?,
                                           _ userData: UnsafeMutableRawPointer?) -> Bool {
    guard Thread.isMainThread, let surfaceName else {
        return false
    }
    let name = String(cString: surfaceName)
    guard !name.isEmpty else {
        return false
    }
    var copy: AUIHostSurfaceDelegate?
    if let delegate {
        guard let copied = copyDelegate(delegate) else {
            return false
        }
        copy = copied
    }
    // Already on the main thread (checked above): the pointer is only stored here and passed back to
    // the client's callbacks on this thread, never read.
    nonisolated(unsafe) let clientData = userData
    let clientDelegate = copy
    MainActor.assumeIsolated {
        HostSurfaceRegistry.shared.setBinding(clientDelegate.map { HostSurfaceBinding(.c($0, clientData)) }, for: name)
    }
    return true
}

@c
public func actionUIHostSurfaceRequestFrame(_ surfaceID: UInt64) {
    ActionUIHostSurface.requestFrame(surfaceID: surfaceID)
}

@c
public func actionUIHostSurfaceSetContinuous(_ surfaceID: UInt64, _ continuous: Bool) {
    ActionUIHostSurface.setContinuous(continuous, surfaceID: surfaceID)
}

@c
public func actionUIHostSurfaceSetCursor(_ surfaceID: UInt64, _ cursor: Int32) -> Bool {
    guard Thread.isMainThread else {
        return false
    }
    return MainActor.assumeIsolated {
        ActionUIHostSurface.setCursor(cursor, surfaceID: surfaceID)
    }
}

/// Copies a client's delegate struct, honoring its structSize: a client built against an older,
/// shorter struct gets NULL for the callbacks it does not know. nil when structSize does not even
/// cover the first callback.
func copyDelegate(_ delegate: UnsafePointer<AUIHostSurfaceDelegate>) -> AUIHostSurfaceDelegate? {
    let ours = MemoryLayout<AUIHostSurfaceDelegate>.size
    let theirs = Int(delegate.pointee.structSize)
    let minimum = MemoryLayout<AUIHostSurfaceDelegate>.offset(of: \.frame) ?? ours
    guard theirs >= minimum else {
        return nil
    }
    // Whole fields only: the callbacks are pointers, so a size that ends inside one stops before it.
    let pointerSize = MemoryLayout<UnsafeRawPointer>.stride
    let count = min(theirs, ours) / pointerSize * pointerSize
    var copy = AUIHostSurfaceDelegate()
    withUnsafeMutableBytes(of: &copy) { destination in
        let source = UnsafeRawBufferPointer(start: UnsafeRawPointer(delegate), count: count)
        destination.copyMemory(from: source)
    }
    copy.structSize = UInt32(ours)
    return copy
}
