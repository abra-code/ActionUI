// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceRegistry.swift
//
// The add-on's shared state, all on the main actor:
// - clients bound by surface name (a C delegate or a Swift HostSurfaceDelegate);
// - the surface views, one per (windowUUID, viewID), owned here rather than by SwiftUI, so a SwiftUI
//   rebuild of the element moves the same surface into its new container instead of destroying it
//   (on Linux, one per element widget, which GTK never rebuilds: attach and detach);
// - the live surfaces by surfaceID, which the calls from other threads address.
//
// Every client callback goes through deliver(_:), which defers a delegate change made inside a
// callback until that callback returns, so no "destroyed" or "created" runs reentrantly.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CActionUIHostSurface
import Dispatch

/// One bound client. A class, so a surface can remember which binding it announced itself to and
/// send "destroyed" to that one even after the name was bound to another client.
@MainActor
final class HostSurfaceBinding {
    enum Client {
        case c(AUIHostSurfaceDelegate, UnsafeMutableRawPointer?)
        case swift(any HostSurfaceDelegate)
    }

    let client: Client

    init(_ client: Client) {
        self.client = client
    }
}

@MainActor
final class HostSurfaceRegistry {
    static let shared = HostSurfaceRegistry()

    struct Key: Hashable {
        let windowUUID: String
        let viewID: Int
    }

    private var bindings: [String: HostSurfaceBinding] = [:]
    private var owned: [Key: HostSurfaceView] = [:]
    /// Views replaced in `owned` by an element that reuses their key under another surface name, until
    /// their teardown. A rebind must still reach them: a client may free its state once it is unbound.
    private var superseded: [ObjectIdentifier: HostSurfaceView] = [:]
    private var attached: [ObjectIdentifier: HostSurfaceView] = [:]
    private var live: [UInt64: HostSurfaceView] = [:]
    private var lastSurfaceID: UInt64 = 0

    private var callbackDepth = 0
    private var pendingBindings: [(name: String, binding: HostSurfaceBinding?)] = []

    // MARK: bindings

    func binding(for name: String) -> HostSurfaceBinding? {
        bindings[name]
    }

    /// Binds (or, with nil, unbinds) a surface name. Inside a callback, or inside another binding change
    /// or a teardown, the change waits until the outermost one is done.
    func setBinding(_ binding: HostSurfaceBinding?, for name: String) {
        if callbackDepth > 0 {
            pendingBindings.append((name, binding))
            return
        }
        // Runs as one deferral scope: a client that rebinds inside the "destroyed" below must not
        // see its change applied while this surface is half retracted.
        deliver {
            // The outgoing client first sees "destroyed" for every surface it was told about: a native
            // window (and a layer, for a client that holds a swapchain on it) takes one producer at a
            // time.
            if let old = bindings[name] {
                for surface in surfaces(named: name) where surface.announcedBinding === old {
                    surface.retract()
                }
            }
            bindings[name] = binding
            // Replay: surfaces that appeared before this client get "created" now.
            for surface in surfaces(named: name) {
                surface.refresh()
            }
        }
    }

    /// Runs a client callback, or a state change that sends several. A setBinding call made inside it
    /// is applied after the outermost one returns.
    func deliver(_ body: () -> Void) {
        callbackDepth += 1
        body()
        callbackDepth -= 1
        // One at a time from the front, so changes apply in call order even when applying one queues
        // another.
        while callbackDepth == 0, !pendingBindings.isEmpty {
            let change = pendingBindings.removeFirst()
            setBinding(change.binding, for: change.name)
        }
    }

    // MARK: surface views

    /// The surface view for an element, made on first use and reused by every container SwiftUI
    /// makes for the element until the view is torn down. A different surface name means a different
    /// element under a reused id (a new document in the same window): it gets a new view, and the old
    /// one is torn down with its container.
    func obtainSurface(for key: Key, surfaceName: String, make: () -> HostSurfaceView) -> HostSurfaceView {
        if let existing = owned[key] {
            if existing.surfaceName == surfaceName {
                return existing
            }
            superseded[ObjectIdentifier(existing)] = existing
        }
        let view = make()
        owned[key] = view
        return view
    }

    /// Forgets a torn-down surface view; the next container for its element makes a new one.
    func releaseSurface(_ view: HostSurfaceView) {
        let key = Key(windowUUID: view.windowUUID, viewID: view.viewID)
        if owned[key] === view {
            owned[key] = nil
        }
        superseded[ObjectIdentifier(view)] = nil
    }

    /// Linux: a surface view for each element widget, from the widget's creation to its end. GTK never
    /// rebuilds an element's widget, so there is nothing to move between containers.
    func attach(_ view: HostSurfaceView) {
        attached[ObjectIdentifier(view)] = view
    }

    func detach(_ view: HostSurfaceView) {
        attached[ObjectIdentifier(view)] = nil
    }

    private func surfaces(named name: String) -> [HostSurfaceView] {
        (Array(owned.values) + Array(superseded.values) + Array(attached.values)).filter { $0.surfaceName == name }
    }

    // MARK: live surfaces

    /// A new surfaceID, unique for the life of the process.
    func announce(_ view: HostSurfaceView) -> UInt64 {
        lastSurfaceID += 1
        live[lastSurfaceID] = view
        return lastSurfaceID
    }

    func retire(_ surfaceID: UInt64) {
        live[surfaceID] = nil
    }

    func liveSurface(_ surfaceID: UInt64) -> HostSurfaceView? {
        live[surfaceID]
    }

    // MARK: tests

    var ownedSurfaceCount: Int { owned.count }
    var liveSurfaceCount: Int { live.count }

    /// Unbinds every name and tears down every surface, for tests that need a clean start.
    func resetForTesting() {
        for name in Array(bindings.keys) {
            setBinding(nil, for: name)
        }
        for view in Array(owned.values) + Array(superseded.values) + Array(attached.values) {
            view.teardown()
        }
        pendingBindings = []
    }
}

#if canImport(Darwin)
/// True on the main thread.
nonisolated var isMainThread: Bool {
    Thread.isMainThread
}
#else
// FoundationEssentials has no Thread. The main queue carries this key, and the main thread runs with the
// main queue as its current queue except inside another queue's work, as in the C adapter (ActionUIC.swift).
private let mainQueueKey: DispatchSpecificKey<Bool> = {
    let key = DispatchSpecificKey<Bool>()
    DispatchQueue.main.setSpecific(key: key, value: true)
    return key
}()

/// True on the main thread.
nonisolated var isMainThread: Bool {
    DispatchQueue.getSpecific(key: mainQueueKey) == true
}
#endif

/// Runs work on the main actor: now when called on the main thread, else queued without waiting.
nonisolated func runOnMainWithoutWaiting(_ work: @escaping @MainActor @Sendable () -> Void) {
    if isMainThread {
        MainActor.assumeIsolated {
            work()
        }
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                work()
            }
        }
    }
}
