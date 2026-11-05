// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView.swift
//
// The native view behind a HostSurface element: a CAMetalLayer-backed NSView (macOS) or UIView
// (iOS) that the registry owns, one per (windowUUID, viewID). SwiftUI's representable is a thin
// HostSurfaceContainer that adopts it (HostSurface.swift).
//
// It decides the surface events from what it observes:
// - "created" once it has a window, a nonzero pixel size, a bound client, and a live container;
// - "changed" when the size in points or the scale changes;
// - "suspended" and "resumed" as it leaves and returns to the screen: hidden, zero pixels, inside a
//   container SwiftUI dismantled (at once), out of any window (one main-loop turn later, because a
//   SwiftUI rebuild moves it out of its window and into a new container within one turn), an
//   occluded or minimized window, a scene in the background;
// - "destroyed" when it is torn down: one main-loop turn after its container was dismantled, unless a
//   new container adopted it by then (SwiftUI makes the new container before it dismantles the old
//   one); at once when its window closes or its scene disconnects, because neither detaches the
//   views; and to the outgoing client when its name is bound to another. A view out of its window in
//   a live container (a tab not shown, say) stays suspended, not destroyed.
//
// It drives frame callbacks from a display link while announced, not suspended, and continuous or
// asked for a frame. Input is in HostSurfaceView+Input.swift.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import QuartzCore
import ActionUI
import CActionUIHostSurface
#if os(macOS)
import AppKit
typealias HostSurfacePlatformView = NSView
#else
import UIKit
typealias HostSurfacePlatformView = UIView
#endif

@MainActor
final class HostSurfaceView: HostSurfacePlatformView {
    let windowUUID: String
    let viewID: Int
    /// Fixed at load, like the element's kind.
    let surfaceName: String
    private(set) var properties: HostSurfaceProperties
    private weak var model: ViewModel?
    private let logger: any ActionUILogger

    /// The container SwiftUI currently shows this view in; set by HostSurfaceContainer.
    weak var container: HostSurfaceContainer?
    /// Set by HostSurfaceContainer.adopt while it moves the view, which passes through "no superview,
    /// no window"; that moment is not a reason to suspend.
    var isMoving = false

    /// Nonzero while the surface is announced: from "created" to "destroyed".
    private(set) var surfaceID: UInt64 = 0
    /// The client that got "created"; "destroyed" goes to it even after the name was rebound.
    private(set) var announcedBinding: HostSurfaceBinding?
    private(set) var suspendedSent = false
    private var lastGeometry: Geometry?

    /// SwiftUI's isEnabled for the element (the disabled modifier, its own or an ancestor's).
    private(set) var inputEnabled = true
    /// The cursor over the surface (AUIHostCursor), set by the client.
    var cursor = Int32(AUIHostCursorArrow.rawValue)
    #if os(macOS)
    /// False until the window has been key for a main-loop turn: AppKit picks an initial first
    /// responder when a window first becomes key, and the surface must not take focus unasked.
    var focusArmed = false
    var trackingArea: NSTrackingArea?
    /// The last Tab key down went to the client (Control-Tab, say), so its key up goes too.
    var tabKeyDownDelivered = false
    #else
    var lastPinchScale: CGFloat = 1
    var lastRotation: CGFloat = 0
    var lastScrollTranslation: CGPoint = .zero
    var pointerInteraction: UIPointerInteraction?
    #endif

    private var displayLink: CADisplayLink?
    private var continuousOverride: Bool?
    private var framePending = false

    private var windowVisible = true
    /// Out of any window as of the last teardown check (one turn after it left).
    private var detached = false
    private var observers: [NSObjectProtocol] = []
    private weak var observedWindow: AnyObject?
    private var warnedFixedProperties = false
    /// Set by teardown. A torn-down view can linger in a closing window or a dismantled container; it
    /// must not be announced again. Its element gets a new view from the registry.
    private(set) var isTornDown = false

    /// Tests run in windows that are never on screen, which macOS reports as occluded. With this set,
    /// a window counts as visible, so the tests see the events of an on-screen surface.
    static var ignoresWindowOcclusionForTesting = false

    var metalLayer: CAMetalLayer {
        // The view's backing layer is created as a CAMetalLayer in makeBackingLayer / layerClass.
        layer as! CAMetalLayer
    }

    init(windowUUID: String, viewID: Int, properties: HostSurfaceProperties, model: ViewModel?,
         logger: any ActionUILogger) {
        self.windowUUID = windowUUID
        self.viewID = viewID
        self.surfaceName = properties.surfaceName
        self.properties = properties
        self.model = model
        self.logger = logger
        super.init(frame: .zero)
        #if os(macOS)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        #else
        isMultipleTouchEnabled = true
        // A new display scale (another screen) is a "changed".
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: HostSurfaceView, _: UITraitCollection) in
            view.refresh()
        }
        #endif
        metalLayer.pixelFormat = .bgra8Unorm
        applyLayerProperties()
        installInputHandlers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HostSurfaceView is not loaded from a nib")
    }

    #if os(macOS)
    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    /// Top-left origin, like the input coordinates and the other platforms.
    override var isFlipped: Bool { true }
    #else
    override class var layerClass: AnyClass { CAMetalLayer.self }
    #endif

    // MARK: properties

    /// The element's properties after a render, and SwiftUI's isEnabled for it. surfaceName and kind are
    /// fixed at load.
    func update(_ new: HostSurfaceProperties, enabled: Bool = true) {
        if (new.surfaceName != surfaceName || new.kind != properties.kind) && !warnedFixedProperties {
            warnedFixedProperties = true
            logger.log("HostSurface \(viewID): 'surfaceName' and 'kind' are fixed at load; the change is ignored", .warning)
        }
        let continuousChanged = new.continuous != properties.continuous
        properties.continuous = new.continuous
        properties.preferredFrameRate = new.preferredFrameRate
        properties.focusable = new.focusable
        properties.opaque = new.opaque
        properties.hidden = new.hidden
        properties.idealWidth = new.idealWidth
        properties.idealHeight = new.idealHeight
        if continuousChanged {
            // A change of the property ends a client's override.
            continuousOverride = nil
        }
        // Hidden is applied here, on the native view, not by a SwiftUI modifier: toggling a
        // conditional .hidden() would rebuild the representable. A hidden view is not composited and
        // takes no input, and the layer and the client's surface stay alive.
        if isHidden != new.hidden {
            isHidden = new.hidden
        }
        inputEnabled = enabled
        applyLayerProperties()
        refresh()
        if !canTakeFocus {
            giveUpFocus()
        }
    }

    private func applyLayerProperties() {
        metalLayer.isOpaque = properties.opaque
        if let displayLink {
            applyFrameRate(to: displayLink)
        }
    }

    private var continuous: Bool {
        continuousOverride ?? properties.continuous
    }

    func setContinuousOverride(_ on: Bool) {
        continuousOverride = on
        updateDisplayLink()
    }

    func requestFrame() {
        framePending = true
        updateDisplayLink()
    }

    // MARK: geometry

    struct Geometry: Equatable {
        var widthPoints: Double
        var heightPoints: Double
        var scale: Double

        var widthPixels: UInt32 { Self.pixels(widthPoints, scale) }
        var heightPixels: UInt32 { Self.pixels(heightPoints, scale) }
        var hasPixels: Bool { widthPixels > 0 && heightPixels > 0 }

        static func pixels(_ points: Double, _ scale: Double) -> UInt32 {
            let value = (points * scale).rounded()
            guard value.isFinite, value > 0 else {
                return 0
            }
            return UInt32(min(value, Double(UInt32.max)))
        }
    }

    /// The window's scale; out of a window, the last one known, so a move between containers is not
    /// a scale change.
    private var scale: Double {
        #if os(macOS)
        if let window {
            return Double(window.backingScaleFactor)
        }
        return lastGeometry?.scale ?? 1
        #else
        if window != nil {
            return Double(traitCollection.displayScale)
        }
        return lastGeometry?.scale ?? Double(traitCollection.displayScale)
        #endif
    }

    private var geometry: Geometry {
        Geometry(widthPoints: Double(bounds.width), heightPoints: Double(bounds.height), scale: scale)
    }

    private func info(_ geometry: Geometry) -> AUIHostSurfaceInfo {
        AUIHostSurfaceInfo(
            structSize: UInt32(MemoryLayout<AUIHostSurfaceInfo>.size),
            kind: Int32(AUIHostSurfaceMetalLayer.rawValue),
            handle: Unmanaged.passUnretained(metalLayer).toOpaque(),
            widthPoints: geometry.widthPoints, heightPoints: geometry.heightPoints, scale: geometry.scale,
            widthPixels: geometry.widthPixels, heightPixels: geometry.heightPixels)
    }

    private func swiftInfo(_ geometry: Geometry) -> HostSurfaceInfo {
        HostSurfaceInfo(surfaceID: surfaceID, windowUUID: windowUUID, viewID: viewID, metalLayer: metalLayer,
                        widthPoints: geometry.widthPoints, heightPoints: geometry.heightPoints,
                        scale: geometry.scale, widthPixels: Int(geometry.widthPixels),
                        heightPixels: Int(geometry.heightPixels))
    }

    /// Out of the screen for any reason; see the file note.
    private var shouldSuspend: Bool {
        properties.hidden || !geometry.hasPixels || detached || !hasLiveContainer || !windowVisible
    }

    /// In a container SwiftUI still shows (not dismantled).
    private var hasLiveContainer: Bool {
        guard let container, superview === container else {
            return false
        }
        return !container.isDismantled
    }

    // MARK: lifecycle

    /// Brings the surface events up to date with what the view observes. Called after every change.
    func refresh() {
        guard !isTornDown, !isMoving else {
            return
        }
        let current = geometry
        if current != lastGeometry, current.hasPixels {
            metalLayer.contentsScale = CGFloat(current.scale)
        }
        if surfaceID == 0 {
            guard let binding = HostSurfaceRegistry.shared.binding(for: surfaceName),
                  window != nil, hasLiveContainer, current.hasPixels else {
                updateDisplayLink()
                return
            }
            surfaceID = HostSurfaceRegistry.shared.announce(self)
            announcedBinding = binding
            lastGeometry = current
            suspendedSent = false
            send(.created, current)
        } else if current != lastGeometry, current.hasPixels {
            lastGeometry = current
            send(.changed, current)
        }
        // A delegate change made inside a callback can retract the surface before this point.
        if surfaceID != 0, shouldSuspend != suspendedSent {
            suspendedSent.toggle()
            send(suspendedSent ? .suspended : .resumed, lastGeometry ?? current)
        }
        updateDisplayLink()
    }

    /// Sends "destroyed" to the client that was told about the surface, and forgets the surfaceID. The
    /// view stays, and is announced again when a client is bound (a new surfaceID).
    func retract() {
        guard surfaceID != 0 else {
            return
        }
        // FocusOut before "destroyed"; a surface with no client must not keep taking the keys.
        giveUpFocus()
        // The client's cursor lasts until "destroyed" (the header): a hidden one must not outlive it.
        if cursor != Int32(AUIHostCursorArrow.rawValue) {
            setCursor(Int32(AUIHostCursorArrow.rawValue))
        }
        send(.destroyed, lastGeometry ?? geometry)
        HostSurfaceRegistry.shared.retire(surfaceID)
        surfaceID = 0
        announcedBinding = nil
        suspendedSent = false
        lastGeometry = nil
        framePending = false
        continuousOverride = nil
        updateDisplayLink()
    }

    /// The end of the element: "destroyed", then the registry forgets the view.
    func teardown() {
        guard !isTornDown else {
            return
        }
        // One deferral scope: a delegate change the client makes inside "destroyed" applies after the
        // view is torn down and forgotten, so it neither retracts nor announces this view again.
        HostSurfaceRegistry.shared.deliver {
            retract()
            isTornDown = true
            displayLink?.invalidate()
            displayLink = nil
            stopObservingWindow()
            HostSurfaceRegistry.shared.releaseSurface(self)
        }
    }

    /// Called when the view left its window or its container was dismantled. Decides on the next
    /// main-loop turn: torn down when no live container holds it (none adopted it), else suspended
    /// while it is out of any window.
    func scheduleTeardownCheck() {
        refresh()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isTornDown else {
                    return
                }
                if self.hasLiveContainer {
                    self.detached = self.window == nil
                    self.refresh()
                } else {
                    self.teardown()
                }
            }
        }
    }

    /// Delivers one input event to the client that got "created". The platform handlers decide whether
    /// input is allowed (HostSurfaceView+Input.swift).
    func deliverInput(_ event: AUIHostInputEvent, code: String = "", text: String? = nil) {
        guard surfaceID != 0, let binding = announcedBinding else {
            return
        }
        var event = event
        event.structSize = UInt32(MemoryLayout<AUIHostInputEvent>.size)
        let surfaceID = surfaceID
        HostSurfaceRegistry.shared.deliver {
            switch binding.client {
            case .c(let delegate, let userData):
                guard let callback = delegate.input else {
                    return
                }
                windowUUID.withCString { uuid in
                    code.withCString { codePointer in
                        event.code = codePointer
                        if let text {
                            text.withCString { textPointer in
                                event.text = textPointer
                                callback(surfaceID, uuid, Int64(viewID), &event, userData)
                            }
                        } else {
                            event.text = nil
                            callback(surfaceID, uuid, Int64(viewID), &event, userData)
                        }
                    }
                }
            case .swift(let delegate):
                event.code = nil
                event.text = nil
                delegate.hostSurfaceInput(swiftInfo(lastGeometry ?? geometry),
                                          event: HostSurfaceInput(event: event, code: code, text: text))
            }
        }
    }

    private func send(_ event: HostSurfaceEvent, _ geometry: Geometry) {
        guard let binding = announcedBinding else {
            return
        }
        let surfaceID = surfaceID
        HostSurfaceRegistry.shared.deliver {
            switch binding.client {
            case .c(let delegate, let userData):
                guard let callback = delegate.surface else {
                    return
                }
                var cInfo = info(geometry)
                windowUUID.withCString { uuid in
                    callback(surfaceID, uuid, Int64(viewID), Int32(event.cValue.rawValue), &cInfo, userData)
                }
            case .swift(let delegate):
                delegate.hostSurface(swiftInfo(geometry), event: event)
            }
        }
        if event == .created || event == .changed {
            publishSize(geometry)
        }
    }

    /// The element's "size" state, [width, height] in points, for ActionUI handlers.
    private func publishSize(_ geometry: Geometry) {
        let size = [geometry.widthPoints, geometry.heightPoints]
        // After the current layout pass: a state write during a SwiftUI update is not allowed.
        DispatchQueue.main.async { [weak model] in
            MainActor.assumeIsolated {
                guard let model, model.states["size"] as? [Double] != size else {
                    return
                }
                model.states["size"] = size
            }
        }
    }

    // MARK: window

    private func attachedToWindow() {
        detached = false
        startObservingWindow()
        refresh()
    }

    private func startObservingWindow() {
        guard let window, observedWindow !== window else {
            return
        }
        stopObservingWindow()
        observedWindow = window
        let center = NotificationCenter.default
        #if os(macOS)
        focusArmed = false
        armFocusIfKey()
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.armFocusIfKey()
                self?.windowKeyChanged(isKey: true)
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowKeyChanged(isKey: false)
            }
        })
        let ignoresOcclusion = Self.ignoresWindowOcclusionForTesting
        windowVisible = ignoresOcclusion || window.occlusionState.contains(.visible)
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.teardown()
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                            object: window, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !ignoresOcclusion, let window = self.observedWindow as? NSWindow else {
                    return
                }
                self.windowVisible = window.occlusionState.contains(.visible)
                self.refresh()
            }
        })
        #else
        guard let scene = window.windowScene else {
            windowVisible = true
            return
        }
        windowVisible = scene.activationState != .background
        observers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene,
                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowVisible = false
                self?.refresh()
            }
        })
        observers.append(center.addObserver(forName: UIScene.willEnterForegroundNotification, object: scene,
                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowVisible = true
                self?.refresh()
            }
        })
        // A disconnected scene keeps its views, like a closed NSWindow.
        observers.append(center.addObserver(forName: UIScene.didDisconnectNotification, object: scene,
                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.teardown()
            }
        })
        #endif
    }

    private func stopObservingWindow() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        observedWindow = nil
        windowVisible = true
    }

    #if os(macOS)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            attachedToWindow()
        } else {
            scheduleTeardownCheck()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refresh()
    }
    #else
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            attachedToWindow()
        } else {
            scheduleTeardownCheck()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }
    #endif

    // MARK: frames

    private func updateDisplayLink() {
        let wanted = surfaceID != 0 && !suspendedSent && (continuous || framePending)
        if wanted, displayLink == nil {
            #if os(macOS)
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            #else
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            #endif
            applyFrameRate(to: link)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = !wanted
    }

    private func applyFrameRate(to link: CADisplayLink) {
        let rate = Float(properties.preferredFrameRate)
        link.preferredFrameRateRange = rate > 0
            ? CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            : .default
    }

    @objc private func tick(_ link: CADisplayLink) {
        framePending = false
        if surfaceID != 0, !suspendedSent, let binding = announcedBinding {
            let surfaceID = surfaceID
            let timestamp = link.targetTimestamp
            HostSurfaceRegistry.shared.deliver {
                switch binding.client {
                case .c(let delegate, let userData):
                    guard let callback = delegate.frame else {
                        return
                    }
                    windowUUID.withCString { uuid in
                        callback(surfaceID, uuid, Int64(viewID), timestamp, userData)
                    }
                case .swift(let delegate):
                    delegate.hostSurfaceFrame(swiftInfo(lastGeometry ?? geometry), timestamp: timestamp)
                }
            }
        }
        updateDisplayLink()
    }
}
