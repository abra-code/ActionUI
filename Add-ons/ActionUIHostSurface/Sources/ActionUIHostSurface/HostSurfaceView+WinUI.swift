// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView+WinUI.swift
//
// The surface behind a HostSurface element on Windows: a frame sink, as on Linux. The client renders where it likes
// (offscreen with Direct3D, wgpu or Vulkan, or on the CPU) and presents finished frames
// (actionUIHostSurfacePresentPixels, HostSurfaceSinks+WinUI.swift); the element shows the newest one in a WinUI
// Image, scaled to its size.
//
// One HostSurfaceView per element (its panel, which ActionUI's renderer never rebuilds for a property change; the
// element applies "hidden" itself). The view decides the events from what the panel observes, by the rules of the
// Apple and Linux views:
// - "created" once the panel is in a window, has a nonzero pixel size, and its name has a client;
// - "changed" when the size in points or the window's scale changes (another display, a new scale setting);
// - "suspended" and "resumed" as it leaves and returns to the screen: hidden, zero pixels, or its window minimized;
// - "destroyed" when the panel leaves its window (the element was removed, its window closed), and to the outgoing
//   client when its name is bound to another. A panel put in a window again is announced again, with a new
//   surfaceID.
//
// Frame callbacks come from WinUI's frame tick (CompositionTarget.Rendering) while announced, not suspended, and
// continuous or asked for a frame. The tick is added only then: WinUI draws frames while one is added.
//
// The window's scale and visibility come from a watch on the window the panel is in (its XamlRoot), added when the
// panel is put in a window and removed when it leaves.
//
// The client's cursor (actionUIHostSurfaceSetCursor) is the panel's own cursor while the pointer is over it, until
// "destroyed". Windows has no hand for grabbing, so the open and closed hands show the move cursor; hidden is a blank
// cursor from the shim's resources.
//
// Not yet on Windows: input and focus.

#if os(Windows)

import FoundationEssentials
import ActionUI
import CWinUI
import CActionUIHostSurface
import Dispatch

/// One reference to a WinUI object of the shim's, given back when this goes.
final class HostShimObject {
    let pointer: OpaquePointer

    init?(adopting pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        self.pointer = pointer
    }

    deinit {
        actionUIWinUIRelease(pointer)
    }
}

/// The shim's last error on this thread, for the log.
func lastHostShimError() -> String {
    var buffer = [CChar](repeating: 0, count: 1024)
    let copied = buffer.withUnsafeMutableBufferPointer { actionUIWinUICopyLastError($0.baseAddress, $0.count) }
    let message = copied ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    return message.isEmpty ? "(no message)" : message
}

@MainActor
final class HostSurfaceView {
    let windowUUID: String
    let viewID: Int
    /// Fixed at load (the first update), like the element's kind.
    private(set) var surfaceName = ""
    private(set) var properties = HostSurfaceProperties()
    private var loaded = false
    private weak var model: ViewModel?
    private let logger: any ActionUILogger

    /// The element's object: a panel laid out here, holding the image the frames show in (or the placeholder).
    let panel: HostShimObject
    private var image: HostShimObject?
    private var placeholderFill: HostShimObject?
    private var placeholderLabel: HostShimObject?

    /// Nonzero while the surface is announced: from "created" to "destroyed".
    private(set) var surfaceID: UInt64 = 0
    /// The client that got "created"; "destroyed" goes to it even after the name was rebound.
    private(set) var announcedBinding: HostSurfaceBinding?
    private(set) var suspendedSent = false
    private var lastGeometry: Geometry?
    /// The size the panel was last arranged at, in points.
    private var arrangedWidth = 0.0
    private var arrangedHeight = 0.0
    /// In the registry (attach): from being in a window to leaving it, so a view whose element is gone is not kept.
    private var attached = false

    private var continuousOverride: Bool?
    private var framePending = false
    /// The frame tick (actionUIWinUIRenderingAdd), 0 when none.
    private var renderingToken: UInt64 = 0
    /// The watch on the panel's window (actionUIWinUIXamlRootChangedAdd), 0 when none.
    private var windowWatch: UInt64 = 0
    private var warnedWindowWatch = false
    private var warnedFixedProperties = false
    private var warnedFrame = false
    private var warnedCursor = false
    /// The cursor over the surface (AUIHostCursor), set by the client.
    private(set) var cursor = Int32(AUIHostCursorArrow.rawValue)
    private var warnedTick = false
    private(set) var isTornDown = false

    /// Set when the element is made: its content may not show the host's surface (the trust policy refuses
    /// .hostSurface), so it draws the placeholder and never announces itself.
    var isRefused = false

    init?(windowUUID: String, viewID: Int, model: ViewModel?, logger: any ActionUILogger) {
        self.windowUUID = windowUUID
        self.viewID = viewID
        self.model = model
        self.logger = logger
        let box = Unmanaged.passRetained(WeakHostSurfaceView()).toOpaque()
        guard let panel = HostShimObject(adopting: actionUIWinUIPanelCreate(measureHostSurface, arrangeHostSurface, box,
                                                                            releaseWeakHostSurfaceView)) else {
            logger.log("HostSurface \(viewID): making its panel failed: \(lastHostShimError())", .error)
            return nil
        }
        self.panel = panel
        Unmanaged<WeakHostSurfaceView>.fromOpaque(box).takeUnretainedValue().view = self
        observe(actionUIWinUIElementOnLoaded, "being shown")
        observe(actionUIWinUIElementOnUnloaded, "being taken out of its window")
    }

    private typealias Observer = (OpaquePointer?, ActionUIWinUICallback?, UnsafeMutableRawPointer?, ActionUIWinUICallback?) -> Bool

    private func observe(_ register: Observer, _ what: String) {
        let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
        if !register(panel.pointer, hostSurfaceWindowChanged, box, releaseWeakHostSurfaceView) {
            logger.log("HostSurface \(viewID): observing its \(what) failed: \(lastHostShimError())", .warning)
        }
    }

    // MARK: properties

    /// The element's properties after a render. surfaceName and kind are fixed at load.
    func update(_ new: HostSurfaceProperties) {
        if !loaded {
            loaded = true
            surfaceName = new.surfaceName
            properties = new
            makeContent()
        } else if (new.surfaceName != surfaceName || new.kind != properties.kind) && !warnedFixedProperties {
            warnedFixedProperties = true
            logger.log("HostSurface \(viewID): 'surfaceName' and 'kind' are fixed at load; the change is ignored", .warning)
        }
        let continuousChanged = new.continuous != properties.continuous
        let sizeChanged = new.idealWidth != properties.idealWidth || new.idealHeight != properties.idealHeight
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
        // Hidden is applied here, as ActionUI would (it keeps the space), but by the element, which also suspends
        // the surface.
        _ = actionUIWinUIElementSetOpacity(panel.pointer, new.hidden ? 0 : 1)
        _ = actionUIWinUIElementSetHitTestVisible(panel.pointer, !new.hidden)
        // Black behind the frames when "opaque" (until the first frame, and through its transparent pixels).
        var black = ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 1)
        if !isPlaceholder {
            _ = new.opaque ? actionUIWinUIElementSetBrush(panel.pointer, ActionUIWinUIBrushBackground, &black, nil)
                : actionUIWinUIElementSetBrush(panel.pointer, ActionUIWinUIBrushBackground, nil, nil)
        }
        if sizeChanged {
            _ = actionUIWinUIElementInvalidateMeasure(panel.pointer)
        }
        refresh()
    }

    var isPlaceholder: Bool {
        if isRefused {
            return true
        }
        if case .unsupported = properties.kind {
            return true
        }
        return false
    }

    /// The image the frames show in, or the placeholder: a gray box with the surface's name.
    private func makeContent() {
        if isPlaceholder {
            if let fill = HostShimObject(adopting: actionUIWinUIShapeCreate(ActionUIWinUIShapeRectangle)) {
                var gray = ActionUIWinUIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.25)
                _ = actionUIWinUIElementSetBrush(fill.pointer, ActionUIWinUIBrushFill, &gray, nil)
                if actionUIWinUIPanelInsertChild(panel.pointer, 0, fill.pointer) {
                    placeholderFill = fill
                }
            }
            if let label = HostShimObject(adopting: actionUIWinUITextBlockCreate()) {
                _ = actionUIWinUITextBlockSetText(label.pointer, surfaceName.isEmpty ? "HostSurface" : surfaceName)
                if actionUIWinUIPanelInsertChild(panel.pointer, actionUIWinUIPanelChildCount(panel.pointer), label.pointer) {
                    placeholderLabel = label
                }
            }
            return
        }
        guard let made = HostShimObject(adopting: actionUIWinUIImageCreate()) else {
            logger.log("HostSurface \(viewID): making its image failed: \(lastHostShimError())", .error)
            return
        }
        // Frames are drawn at the surface's pixel size; one of another size (a resize in flight) is scaled to it.
        _ = actionUIWinUIImageSetStretch(made.pointer, ActionUIWinUIImageStretchToSize)
        if actionUIWinUIPanelInsertChild(panel.pointer, 0, made.pointer) {
            image = made
        } else {
            logger.log("HostSurface \(viewID): placing its image failed: \(lastHostShimError())", .error)
        }
    }

    private var continuous: Bool {
        continuousOverride ?? properties.continuous
    }

    func setContinuousOverride(_ on: Bool) {
        continuousOverride = on
        updateFrames()
    }

    func requestFrame() {
        framePending = true
        updateFrames()
    }

    // MARK: layout (the panel's callbacks)

    /// The ideal size (320 x 240 by default), no more than offered; the element grows to what its container
    /// gives it (expansion), as the SwiftUI element takes the proposed size.
    func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let width = min(properties.idealWidth, available.width)
        let height = min(properties.idealHeight, available.height)
        if let placeholderLabel {
            _ = actionUIWinUIElementMeasure(placeholderLabel.pointer, ActionUIWinUISize(width: width, height: height))
        }
        if let placeholderFill {
            _ = actionUIWinUIElementMeasure(placeholderFill.pointer, ActionUIWinUISize(width: width, height: height))
        }
        if let image {
            _ = actionUIWinUIElementMeasure(image.pointer, ActionUIWinUISize(width: width, height: height))
        }
        return ActionUIWinUISize(width: width, height: height)
    }

    func arrange(_ size: ActionUIWinUISize) {
        let whole = ActionUIWinUIRect(x: 0, y: 0, width: size.width, height: size.height)
        if let image {
            _ = actionUIWinUIElementArrange(image.pointer, whole)
        }
        if let placeholderFill {
            _ = actionUIWinUIElementArrange(placeholderFill.pointer, whole)
        }
        if let placeholderLabel {
            // The name in the middle.
            let label = actionUIWinUIElementMeasure(placeholderLabel.pointer, ActionUIWinUISize(width: size.width, height: size.height))
            _ = actionUIWinUIElementArrange(placeholderLabel.pointer,
                                            ActionUIWinUIRect(x: max(0, (size.width - label.width) / 2),
                                                              y: max(0, (size.height - label.height) / 2),
                                                              width: min(label.width, size.width),
                                                              height: min(label.height, size.height)))
        }
        if size.width != arrangedWidth || size.height != arrangedHeight {
            arrangedWidth = size.width
            arrangedHeight = size.height
            // Events go out after the layout pass: a client may change the layout in its callback.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
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

    private var geometry: Geometry {
        Geometry(widthPoints: arrangedWidth, heightPoints: arrangedHeight,
                 scale: actionUIWinUIElementRasterizationScale(panel.pointer))
    }

    private func info(_ geometry: Geometry) -> AUIHostSurfaceInfo {
        AUIHostSurfaceInfo(
            structSize: UInt32(MemoryLayout<AUIHostSurfaceInfo>.size),
            kind: Int32(AUIHostSurfaceFrameSink.rawValue),
            handle: nil,
            widthPoints: geometry.widthPoints, heightPoints: geometry.heightPoints, scale: geometry.scale,
            widthPixels: geometry.widthPixels, heightPixels: geometry.heightPixels)
    }

    private func swiftInfo(_ geometry: Geometry) -> HostSurfaceInfo {
        HostSurfaceInfo(surfaceID: surfaceID, windowUUID: windowUUID, viewID: viewID, kind: AUIHostSurfaceFrameSink,
                        widthPoints: geometry.widthPoints, heightPoints: geometry.heightPoints,
                        scale: geometry.scale, widthPixels: Int(geometry.widthPixels),
                        heightPixels: Int(geometry.heightPixels))
    }

    private var isInWindow: Bool {
        actionUIWinUIElementIsInWindow(panel.pointer)
    }

    /// Out of the screen for any reason; see the file note.
    private var shouldSuspend: Bool {
        // Minimized counts only while the window is watched: without the watch nothing would resume the surface.
        properties.hidden || !geometry.hasPixels || (windowWatch != 0 && !actionUIWinUIElementIsHostVisible(panel.pointer))
    }

    // MARK: lifecycle

    /// Brings the surface events up to date with what the panel observes. Called after every change.
    func refresh() {
        guard !isTornDown, loaded, !isPlaceholder else {
            return
        }
        // Out of its window but not yet retracted (WinUI's Unloaded comes after the removal, from a frame tick or the
        // old window's watch): nothing to measure; the Unloaded retracts it, or finds it put back.
        if surfaceID != 0, !isInWindow {
            return
        }
        let current = geometry
        if surfaceID == 0 {
            guard let binding = HostSurfaceRegistry.shared.binding(for: surfaceName), isInWindow, current.hasPixels else {
                updateFrames()
                return
            }
            // In the registry before it is live, so a rebind reaches it (its Loaded may not have come yet: a parent
            // already in the window counts).
            attach()
            if windowWatch == 0 {
                watchWindow()
            }
            surfaceID = HostSurfaceRegistry.shared.announce(self)
            HostSurfaceSinks.open(surfaceID)
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
        updateFrames()
    }

    /// Sends "destroyed" to the client that was told about the surface, and forgets the surfaceID and its frame.
    /// The view stays, and is announced again when a client is bound (a new surfaceID).
    func retract() {
        guard surfaceID != 0 else {
            return
        }
        // Presents from the client's threads fail from here on; a frame waiting for the main thread is dropped.
        HostSurfaceSinks.close(surfaceID)
        send(.destroyed, lastGeometry ?? geometry)
        HostSurfaceRegistry.shared.retire(surfaceID)
        surfaceID = 0
        announcedBinding = nil
        suspendedSent = false
        lastGeometry = nil
        framePending = false
        continuousOverride = nil
        // The client's cursor lasts until "destroyed" (the header): a hidden one must not outlive it.
        if cursor != Int32(AUIHostCursorArrow.rawValue) {
            setCursor(Int32(AUIHostCursorArrow.rawValue))
        }
        // The client's last frame goes with its surface.
        if let image {
            _ = actionUIWinUIImageSetSource(image.pointer, nil)
        }
        updateFrames()
    }

    /// The end of the element: "destroyed", then the registry forgets the view.
    func teardown() {
        guard !isTornDown else {
            return
        }
        // One deferral scope: a delegate change the client makes inside "destroyed" applies after the view is
        // torn down and forgotten, so it neither retracts nor announces this view again.
        HostSurfaceRegistry.shared.deliver {
            retract()
            isTornDown = true
            removeTick()
            unwatchWindow()
            detach()
        }
    }

    /// The panel was shown or taken out of its window. WinUI raises Unloaded after the removal, and for a panel
    /// removed and added back at once (a stack re-adding its children) when it is in the window again: whether it
    /// is in a window now decides.
    fileprivate func windowChanged() {
        guard !isTornDown else {
            return
        }
        if isInWindow {
            attach()
            if !isPlaceholder {
                watchWindow()
            }
            refresh()
        } else {
            unwatchWindow()
            HostSurfaceRegistry.shared.deliver {
                retract()
                detach()
            }
        }
    }

    /// Watches the window the panel is in now, in place of any window watched before (the panel may have moved).
    private func watchWindow() {
        unwatchWindow()
        let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
        windowWatch = actionUIWinUIXamlRootChangedAdd(panel.pointer, hostSurfaceWindowRootChanged, box,
                                                      releaseWeakHostSurfaceView)
        if windowWatch == 0, !warnedWindowWatch {
            warnedWindowWatch = true
            logger.log("HostSurface \(viewID): watching its window failed: \(lastHostShimError()); a new scale is seen at the next layout or frame, and a minimized window does not suspend the surface", .warning)
        }
    }

    private func unwatchWindow() {
        if windowWatch != 0 {
            actionUIWinUIXamlRootChangedRemove(windowWatch)
            windowWatch = 0
        }
    }

    /// The window's size, scale or visibility changed.
    fileprivate func windowRootChanged() {
        guard !isTornDown else {
            return
        }
        refresh()
    }

    private func attach() {
        if !attached {
            attached = true
            HostSurfaceRegistry.shared.attach(self)
        }
    }

    private func detach() {
        if attached {
            attached = false
            HostSurfaceRegistry.shared.detach(self)
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

    /// The element's "size" state, [width, height] in points, for ActionUI handlers. Written after the current
    /// layout pass, as GeometryReader does.
    private func publishSize(_ geometry: Geometry) {
        let size = [geometry.widthPoints, geometry.heightPoints]
        DispatchQueue.main.async { [weak model] in
            MainActor.assumeIsolated {
                guard let model, model.states["size"] as? [Double] != size else {
                    return
                }
                model.states["size"] = size
            }
        }
    }

    // MARK: frames shown

    /// Shows a frame the client presented for this surface (HostSurfaceSinks hands it over, and frees it after).
    func show(_ frame: HostSurfaceFrame) {
        guard let image, let pixels = frame.pixels.baseAddress else {
            return
        }
        let shown = actionUIWinUIImageShowPixels(image.pointer, UInt32(frame.width), UInt32(frame.height),
                                                 pixels.assumingMemoryBound(to: UInt8.self))
        if !shown, !warnedFrame {
            warnedFrame = true
            logger.log("HostSurface \(viewID): showing a frame failed: \(lastHostShimError())", .warning)
        }
    }

    // MARK: cursor

    static func isKnownCursor(_ cursor: Int32) -> Bool {
        cursor >= Int32(AUIHostCursorArrow.rawValue) && cursor <= Int32(AUIHostCursorHidden.rawValue)
    }

    /// The shim's cursor for an AUIHostCursor value. The arrow is the default: the panel has no cursor of its own.
    static func winUICursor(_ cursor: Int32) -> ActionUIWinUICursor {
        switch cursor {
        case Int32(AUIHostCursorIBeam.rawValue): return ActionUIWinUICursorIBeam
        case Int32(AUIHostCursorCrosshair.rawValue): return ActionUIWinUICursorCross
        case Int32(AUIHostCursorPointingHand.rawValue): return ActionUIWinUICursorHand
        // Windows has no open or closed hand: the move cursor, as Windows shows for dragging content.
        case Int32(AUIHostCursorOpenHand.rawValue), Int32(AUIHostCursorClosedHand.rawValue): return ActionUIWinUICursorSizeAll
        case Int32(AUIHostCursorResizeLeftRight.rawValue): return ActionUIWinUICursorSizeWestEast
        case Int32(AUIHostCursorResizeUpDown.rawValue): return ActionUIWinUICursorSizeNorthSouth
        case Int32(AUIHostCursorNotAllowed.rawValue): return ActionUIWinUICursorNo
        case Int32(AUIHostCursorHidden.rawValue): return ActionUIWinUICursorHidden
        default: return ActionUIWinUICursorDefault
        }
    }

    func setCursor(_ cursor: Int32) {
        self.cursor = cursor
        if !actionUIWinUIPanelSetCursor(panel.pointer, Self.winUICursor(cursor)), !warnedCursor {
            warnedCursor = true
            logger.log("HostSurface \(viewID): setting the cursor failed: \(lastHostShimError())", .warning)
        }
    }

    // MARK: frames asked for

    private func updateFrames() {
        let wanted = surfaceID != 0 && !suspendedSent && (continuous || framePending)
        if wanted, renderingToken == 0 {
            let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
            renderingToken = actionUIWinUIRenderingAdd(hostSurfaceTick, box, releaseWeakHostSurfaceView)
            if renderingToken == 0, !warnedTick {
                warnedTick = true
                logger.log("HostSurface \(viewID): asking for frame ticks failed: \(lastHostShimError())", .warning)
            }
        } else if !wanted {
            removeTick()
        }
    }

    private func removeTick() {
        if renderingToken != 0 {
            actionUIWinUIRenderingRemove(renderingToken)
            renderingToken = 0
        }
    }

    /// One tick before WinUI draws a frame.
    fileprivate func tick(seconds: Double) {
        framePending = false
        // The window's scale can change with no new size (moved to another display): the window watch reports it, and
        // this catches it should the watch be missing.
        if surfaceID != 0, let lastGeometry, geometry != lastGeometry {
            refresh()
        }
        if surfaceID != 0, !suspendedSent, let binding = announcedBinding {
            let surfaceID = surfaceID
            HostSurfaceRegistry.shared.deliver {
                switch binding.client {
                case .c(let delegate, let userData):
                    guard let callback = delegate.frame else {
                        return
                    }
                    windowUUID.withCString { uuid in
                        callback(surfaceID, uuid, Int64(viewID), seconds, userData)
                    }
                case .swift(let delegate):
                    delegate.hostSurfaceFrame(swiftInfo(lastGeometry ?? geometry), timestamp: seconds)
                }
            }
        }
        updateFrames()
    }
}

/// A callback's context: the view, not kept alive by it.
@MainActor
private final class WeakHostSurfaceView {
    weak var view: HostSurfaceView?

    init(_ view: HostSurfaceView? = nil) {
        self.view = view
    }
}

private func weakView(_ context: UnsafeMutableRawPointer?) -> WeakHostSurfaceView? {
    context.map { Unmanaged<WeakHostSurfaceView>.fromOpaque($0).takeUnretainedValue() }
}

private let releaseWeakHostSurfaceView: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<WeakHostSurfaceView>.fromOpaque(context).release()
}

private let measureHostSurface: ActionUIWinUIMeasureCallback = { context, _, available in
    let box = weakView(context)
    return MainActor.assumeIsolated {
        box?.view?.measure(available) ?? ActionUIWinUISize(width: 0, height: 0)
    }
}

private let arrangeHostSurface: ActionUIWinUIArrangeCallback = { context, _, finalSize in
    let box = weakView(context)
    MainActor.assumeIsolated {
        box?.view?.arrange(finalSize)
    }
}

private let hostSurfaceWindowChanged: ActionUIWinUICallback = { context in
    let box = weakView(context)
    MainActor.assumeIsolated {
        box?.view?.windowChanged()
    }
}

private let hostSurfaceWindowRootChanged: ActionUIWinUICallback = { context in
    let box = weakView(context)
    MainActor.assumeIsolated {
        box?.view?.windowRootChanged()
    }
}

private let hostSurfaceTick: ActionUIWinUIRenderingCallback = { context, seconds in
    let box = weakView(context)
    MainActor.assumeIsolated {
        box?.view?.tick(seconds: seconds)
    }
}

#endif
