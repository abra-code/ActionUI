// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView+Adwaita.swift
//
// The surface behind a HostSurface element on Linux: a frame sink. GTK gives a widget no native surface
// to hand out, so the client renders where it likes (offscreen with wgpu or Vulkan, or on the CPU) and
// presents finished frames (actionUIHostSurfacePresentPixels, HostSurfaceSinks+Adwaita.swift); the widget
// shows the newest one as a texture, scaled to its size.
//
// One HostSurfaceView per element widget (an ActionUIHostSurfaceWidget, a GtkWidget subclass that owns
// it). GTK never rebuilds an element's widget for a property change, and the element applies "hidden"
// itself, so the surface lives as long as the widget is in its window. The view decides the events from
// what the widget observes, by the same rules as the Apple view (HostSurfaceView.swift):
// - "created" once the widget is in a window, has a nonzero pixel size, and its name has a client;
// - "changed" when the size in points or the window's scale changes;
// - "suspended" and "resumed" as it leaves and returns to the screen: hidden, zero pixels, unmapped (a page
//   not shown), its window minimized or suspended by the compositor (not visible at all);
// - "destroyed" when the widget leaves its window (the element was removed, its window closed), and to
//   the outgoing client when its name is bound to another. A widget put in a window again is announced
//   again, with a new surfaceID.
//
// Frame callbacks come from the widget's tick callback (the window's frame clock) while announced, not
// suspended, and continuous or asked for a frame.

#if os(Linux)

import FoundationEssentials
import ActionUI
import CAdwaita
import CActionUIHostSurface
import Dispatch

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

    /// Not a reference: the widget owns this view (HostSurfaceWidget), so the pointer outlives it.
    let widget: UnsafeMutablePointer<GtkWidget>

    /// Nonzero while the surface is announced: from "created" to "destroyed".
    private(set) var surfaceID: UInt64 = 0
    /// The client that got "created"; "destroyed" goes to it even after the name was rebound.
    private(set) var announcedBinding: HostSurfaceBinding?
    private(set) var suspendedSent = false
    private var lastGeometry: Geometry?

    /// The newest presented frame (a GdkTexture this view holds a reference to).
    private(set) var texture: OpaquePointer?
    /// The cursor over the surface (AUIHostCursor), set by the client.
    private(set) var cursor = Int32(AUIHostCursorArrow.rawValue)

    private var continuousOverride: Bool?
    private var framePending = false
    private var tickID: guint = 0

    /// The window's surface while the widget is realized, observed for its scale and state.
    private var windowSurface: OpaquePointer?
    private var windowSignals: [gulong] = []
    private var warnedFixedProperties = false
    private(set) var isTornDown = false

    init(widget: UnsafeMutablePointer<GtkWidget>, windowUUID: String, viewID: Int, model: ViewModel?,
         logger: any ActionUILogger) {
        self.widget = widget
        self.windowUUID = windowUUID
        self.viewID = viewID
        self.model = model
        self.logger = logger
        HostSurfaceRegistry.shared.attach(self)
    }

    // MARK: properties

    /// The element's properties after a render. surfaceName and kind are fixed at load.
    func update(_ new: HostSurfaceProperties) {
        if !loaded {
            loaded = true
            surfaceName = new.surfaceName
            properties = new
        } else if (new.surfaceName != surfaceName || new.kind != properties.kind) && !warnedFixedProperties {
            warnedFixedProperties = true
            logger.log("HostSurface \(viewID): 'surfaceName' and 'kind' are fixed at load; the change is ignored", .warning)
        }
        let continuousChanged = new.continuous != properties.continuous
        let sizeChanged = new.idealWidth != properties.idealWidth || new.idealHeight != properties.idealHeight
        let opaqueChanged = new.opaque != properties.opaque
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
        // Hidden is applied here, as ActionUI's box would (it keeps the space and the widget), but by the
        // element, which also suspends the surface.
        gtk_widget_set_opacity(widget, new.hidden ? 0 : 1)
        gtk_widget_set_can_target(widget, new.hidden ? 0 : 1)
        if sizeChanged {
            gtk_widget_queue_resize(widget)
        }
        if opaqueChanged {
            gtk_widget_queue_draw(widget)
        }
        refresh()
    }

    var isPlaceholder: Bool {
        if case .unsupported = properties.kind {
            return true
        }
        return false
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

    /// The window's scale (fractional since GTK 4.12); out of a window, the last one known.
    private var scale: Double {
        if let windowSurface {
            return gdk_surface_get_scale(windowSurface)
        }
        return lastGeometry?.scale ?? Double(gtk_widget_get_scale_factor(widget))
    }

    private var geometry: Geometry {
        Geometry(widthPoints: Double(gtk_widget_get_width(widget)), heightPoints: Double(gtk_widget_get_height(widget)),
                 scale: scale)
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
        HostSurfaceInfo(surfaceID: surfaceID, windowUUID: windowUUID, viewID: viewID,
                        widthPoints: geometry.widthPoints, heightPoints: geometry.heightPoints,
                        scale: geometry.scale, widthPixels: Int(geometry.widthPixels),
                        heightPixels: Int(geometry.heightPixels))
    }

    private var isInWindow: Bool {
        gtk_widget_get_root(widget) != nil
    }

    /// The window is minimized, or the compositor suspended it (not visible at all, GTK 4.12).
    private var windowHidden: Bool {
        guard let windowSurface,
              g_type_check_instance_is_a(UnsafeMutableRawPointer(windowSurface).assumingMemoryBound(to: GTypeInstance.self),
                                         gdk_toplevel_get_type()) != 0 else {
            return false
        }
        let state = gdk_toplevel_get_state(windowSurface).rawValue
        let hiddenStates = GDK_TOPLEVEL_STATE_MINIMIZED.rawValue | GDK_TOPLEVEL_STATE_SUSPENDED.rawValue
        return state & hiddenStates != 0
    }

    /// Out of the screen for any reason; see the file note.
    private var shouldSuspend: Bool {
        properties.hidden || !geometry.hasPixels || gtk_widget_get_mapped(widget) == 0 || windowHidden
    }

    // MARK: lifecycle

    /// Brings the surface events up to date with what the widget observes. Called after every change.
    func refresh() {
        guard !isTornDown, loaded, !isPlaceholder else {
            return
        }
        let current = geometry
        if surfaceID == 0 {
            guard let binding = HostSurfaceRegistry.shared.binding(for: surfaceName), isInWindow,
                  current.hasPixels else {
                updateFrames()
                return
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

    /// Sends "destroyed" to the client that was told about the surface, and forgets the surfaceID and its
    /// frame. The view stays, and is announced again when a client is bound (a new surfaceID).
    func retract() {
        guard surfaceID != 0 else {
            return
        }
        giveUpFocus()
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
        cursor = Int32(AUIHostCursorArrow.rawValue)
        gtk_widget_set_cursor(widget, nil)
        setTexture(nil)
        updateFrames()
    }

    /// The end of the element (its widget is being disposed): "destroyed", then the registry forgets the view.
    func teardown() {
        guard !isTornDown else {
            return
        }
        // One deferral scope: a delegate change the client makes inside "destroyed" applies after the view is
        // torn down and forgotten, so it neither retracts nor announces this view again.
        HostSurfaceRegistry.shared.deliver {
            retract()
            isTornDown = true
            stopObservingWindow()
            removeTick()
            HostSurfaceRegistry.shared.detach(self)
        }
    }

    /// Gives up keyboard focus when the widget has it, so a surface with no client takes no keys.
    func giveUpFocus() {
        guard gtk_widget_has_focus(widget) != 0, let root = gtk_widget_get_root(widget) else {
            return
        }
        gtk_root_set_focus(root, nil)
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

    /// The element's "size" state, [width, height] in points, for ActionUI handlers. Written after the
    /// current layout pass, as GeometryReader does: a model write during allocation would sync mid-layout.
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

    /// Shows a frame the client presented for this surface (HostSurfaceSinks hands it over).
    func show(_ frame: HostSurfaceFrame) {
        let made = gdk_memory_texture_new(Int32(frame.width), Int32(frame.height), frame.format, frame.bytes,
                                          gsize(frame.stride))
        frame.release()
        setTexture(made)
    }

    private func setTexture(_ new: OpaquePointer?) {
        if let texture {
            g_object_unref(UnsafeMutableRawPointer(texture))
        }
        texture = new
        gtk_widget_queue_draw(widget)
    }

    /// Draws the newest frame scaled to the widget, or the placeholder for a kind this platform lacks.
    func draw(_ snapshot: OpaquePointer) {
        let width = Float(gtk_widget_get_width(widget))
        let height = Float(gtk_widget_get_height(widget))
        guard width > 0, height > 0 else {
            return
        }
        var bounds = graphene_rect_t(origin: graphene_point_t(x: 0, y: 0), size: graphene_size_t(width: width, height: height))
        if isPlaceholder {
            drawPlaceholder(snapshot, bounds: &bounds)
            return
        }
        guard let texture else {
            return
        }
        if properties.opaque {
            // Opaque, as a Metal layer with isOpaque: premultiplied colors over black are the colors themselves.
            var black = GdkRGBA(red: 0, green: 0, blue: 0, alpha: 1)
            gtk_snapshot_append_color(snapshot, &black, &bounds)
        }
        gtk_snapshot_append_scaled_texture(snapshot, texture, GSK_SCALING_FILTER_LINEAR, &bounds)
    }

    /// A gray rectangle with the surface name, as on Apple platforms.
    private func drawPlaceholder(_ snapshot: OpaquePointer, bounds: inout graphene_rect_t) {
        var gray = GdkRGBA(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.25)
        gtk_snapshot_append_color(snapshot, &gray, &bounds)
        let name = surfaceName.isEmpty ? "HostSurface" : surfaceName
        guard let layout = gtk_widget_create_pango_layout(widget, name) else {
            return
        }
        var textWidth: Int32 = 0
        var textHeight: Int32 = 0
        pango_layout_get_pixel_size(layout, &textWidth, &textHeight)
        var origin = graphene_point_t(x: (bounds.size.width - Float(textWidth)) / 2,
                                      y: (bounds.size.height - Float(textHeight)) / 2)
        var color = GdkRGBA()
        gtk_widget_get_color(widget, &color)
        color.alpha *= 0.55
        gtk_snapshot_save(snapshot)
        gtk_snapshot_translate(snapshot, &origin)
        gtk_snapshot_append_layout(snapshot, layout, &color)
        gtk_snapshot_restore(snapshot)
        g_object_unref(UnsafeMutableRawPointer(layout))
    }

    // MARK: cursor

    static func isKnownCursor(_ cursor: Int32) -> Bool {
        cursorName(cursor) != nil
    }

    /// The CSS cursor name GTK takes for an AUIHostCursor value.
    static func cursorName(_ cursor: Int32) -> String? {
        switch cursor {
        case Int32(AUIHostCursorArrow.rawValue): return "default"
        case Int32(AUIHostCursorIBeam.rawValue): return "text"
        case Int32(AUIHostCursorCrosshair.rawValue): return "crosshair"
        case Int32(AUIHostCursorPointingHand.rawValue): return "pointer"
        case Int32(AUIHostCursorOpenHand.rawValue): return "grab"
        case Int32(AUIHostCursorClosedHand.rawValue): return "grabbing"
        case Int32(AUIHostCursorResizeLeftRight.rawValue): return "ew-resize"
        case Int32(AUIHostCursorResizeUpDown.rawValue): return "ns-resize"
        case Int32(AUIHostCursorNotAllowed.rawValue): return "not-allowed"
        case Int32(AUIHostCursorHidden.rawValue): return "none"
        default: return nil
        }
    }

    func setCursor(_ cursor: Int32) {
        guard let name = Self.cursorName(cursor) else {
            return
        }
        self.cursor = cursor
        gtk_widget_set_cursor_from_name(widget, name)
    }

    // MARK: what the widget reports (HostSurfaceWidget)

    func allocated() {
        refresh()
    }

    func mappedChanged() {
        refresh()
    }

    func realized() {
        startObservingWindow()
        refresh()
    }

    func unrealized() {
        stopObservingWindow()
        refresh()
    }

    /// The widget left its window: the element was removed or the window closed.
    func unrooted() {
        HostSurfaceRegistry.shared.deliver {
            retract()
        }
    }

    func rooted() {
        refresh()
    }

    // MARK: window

    private func startObservingWindow() {
        guard let root = gtk_widget_get_root(widget) else {
            return
        }
        // The root is a GtkWindow, a GtkNative.
        guard let surface = gtk_native_get_surface(root), surface != windowSurface else {
            return
        }
        stopObservingWindow()
        g_object_ref(UnsafeMutableRawPointer(surface))
        windowSurface = surface
        for signal in ["notify::scale", "notify::state"] {
            let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
            let handler = g_signal_connect_data(UnsafeMutableRawPointer(surface), signal,
                                                unsafeBitCast(windowChangedTrampoline, to: GCallback.self), box,
                                                releaseWeakView, GConnectFlags(rawValue: 0))
            windowSignals.append(handler)
        }
    }

    private func stopObservingWindow() {
        guard let windowSurface else {
            return
        }
        for handler in windowSignals {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(windowSurface), handler)
        }
        windowSignals = []
        g_object_unref(UnsafeMutableRawPointer(windowSurface))
        self.windowSurface = nil
    }

    // MARK: frames asked for

    private func updateFrames() {
        let wanted = surfaceID != 0 && !suspendedSent && (continuous || framePending)
        if wanted, tickID == 0 {
            let box = Unmanaged.passRetained(WeakHostSurfaceView(self)).toOpaque()
            tickID = gtk_widget_add_tick_callback(widget, tickTrampoline, box, releaseWeakViewData)
        } else if !wanted {
            removeTick()
        }
    }

    private func removeTick() {
        if tickID != 0 {
            gtk_widget_remove_tick_callback(widget, tickID)
            tickID = 0
        }
    }

    /// One tick of the window's frame clock; false removes the tick callback.
    fileprivate func tick(frameTimeMicroseconds: Int64) -> Bool {
        framePending = false
        if surfaceID != 0, !suspendedSent, let binding = announcedBinding {
            let surfaceID = surfaceID
            let timestamp = Double(frameTimeMicroseconds) / 1_000_000
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
        let wanted = surfaceID != 0 && !suspendedSent && (continuous || framePending)
        if !wanted {
            // GTK removes the callback when it returns false.
            tickID = 0
        }
        return wanted
    }
}

/// A weak reference for GLib callbacks, which may outlive the view by a moment.
private final class WeakHostSurfaceView {
    weak var view: HostSurfaceView?

    init(_ view: HostSurfaceView) {
        self.view = view
    }
}

private let releaseWeakView: GClosureNotify = { data, _ in
    if let data {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(data).release()
    }
}

private let releaseWeakViewData: GDestroyNotify = { data in
    if let data {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(data).release()
    }
}

/// notify::scale and notify::state of the window's surface.
private let windowChangedTrampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, _, data in
    guard let data else {
        return
    }
    nonisolated(unsafe) let box = data
    MainActor.assumeIsolated {
        Unmanaged<WeakHostSurfaceView>.fromOpaque(box).takeUnretainedValue().view?.refresh()
    }
}

private let tickTrampoline: GtkTickCallback = { _, clock, data in
    guard let clock, let data else {
        return 0
    }
    nonisolated(unsafe) let target = (clock, data)
    return MainActor.assumeIsolated {
        guard let view = Unmanaged<WeakHostSurfaceView>.fromOpaque(target.1).takeUnretainedValue().view else {
            return 0
        }
        // The header promises the target presentation time: GTK's prediction for this frame, else its frame time.
        var time = Int64(gdk_frame_clock_get_frame_time(target.0))
        if let timings = gdk_frame_clock_get_current_timings(target.0) {
            let predicted = Int64(gdk_frame_timings_get_predicted_presentation_time(timings))
            if predicted > 0 {
                time = predicted
            }
        }
        return view.tick(frameTimeMicroseconds: time) ? 1 : 0
    }
}

/// The element's widget: a GtkWidget subclass that owns its HostSurfaceView and reports to it what GTK does
/// to it (size, map, realize, root, dispose). It wants its ideal size and grows to what it is offered, as
/// the SwiftUI element takes the proposed size.
enum HostSurfaceWidget {
    private static let viewKey = "actionui-host-surface-view"
    /// More than any screen, with room for what GTK and the containers add to it.
    private static let longestNaturalSize = 16_777_216.0
    nonisolated(unsafe) private static var parentClass: UnsafeMutablePointer<GtkWidgetClass>?

    @MainActor private static let type: GType = {
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            parentClass = g_type_class_peek_parent(klass)?.assumingMemoryBound(to: GtkWidgetClass.self)
            klass.assumingMemoryBound(to: GObjectClass.self).pointee.dispose = { object in
                guard let object else { return }
                nonisolated(unsafe) let target = object
                MainActor.assumeIsolated {
                    view(of: UnsafeMutableRawPointer(target).assumingMemoryBound(to: GtkWidget.self))?.teardown()
                }
                parentClass?.withMemoryRebound(to: GObjectClass.self, capacity: 1) { $0.pointee.dispose?(object) }
            }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.measure = measure
            widgetClass.pointee.size_allocate = { widget, _, _, _ in
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.allocated() }
            }
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let snapshot else { return }
                nonisolated(unsafe) let target = (widget, snapshot)
                MainActor.assumeIsolated { view(of: target.0)?.draw(target.1) }
            }
            widgetClass.pointee.map = { widget in
                parentClass?.pointee.map?(widget)
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.mappedChanged() }
            }
            widgetClass.pointee.unmap = { widget in
                parentClass?.pointee.unmap?(widget)
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.mappedChanged() }
            }
            widgetClass.pointee.realize = { widget in
                parentClass?.pointee.realize?(widget)
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.realized() }
            }
            widgetClass.pointee.unrealize = { widget in
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.unrealized() }
                parentClass?.pointee.unrealize?(widget)
            }
            widgetClass.pointee.root = { widget in
                parentClass?.pointee.root?(widget)
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.rooted() }
            }
            widgetClass.pointee.unroot = { widget in
                nonisolated(unsafe) let target = widget
                MainActor.assumeIsolated { view(of: target)?.unrooted() }
                parentClass?.pointee.unroot?(widget)
            }
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_IMG)
            gtk_widget_class_set_css_name(widgetClass, "actionui-host-surface")
        }
        return g_type_register_static(gtk_widget_get_type(), "ActionUIHostSurfaceWidget", &info, GTypeFlags(rawValue: 0))
    }()

    /// A new widget, floating, that owns its view. The view's pointer back is not a reference, and the view
    /// goes with the widget, so it never outlives it.
    @MainActor static func make(windowUUID: String, viewID: Int, model: ViewModel?, logger: any ActionUILogger)
        -> (widget: UnsafeMutablePointer<GtkWidget>, view: HostSurfaceView) {
        let object = g_object_new_with_properties(type, 0, nil, nil)!
        let widget = UnsafeMutableRawPointer(object).assumingMemoryBound(to: GtkWidget.self)
        let view = HostSurfaceView(widget: widget, windowUUID: windowUUID, viewID: viewID, model: model, logger: logger)
        g_object_set_data_full(object, viewKey, Unmanaged.passRetained(view).toOpaque()) { data in
            if let data {
                Unmanaged<HostSurfaceView>.fromOpaque(data).release()
            }
        }
        // Grows to what it is offered, like the SwiftUI element; frame and padding apply around it as usual.
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        return (widget, view)
    }

    static func view(of widget: UnsafeMutablePointer<GtkWidget>?) -> HostSurfaceView? {
        guard let widget,
              let data = g_object_get_data(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self), viewKey) else {
            return nil
        }
        return Unmanaged<HostSurfaceView>.fromOpaque(data).takeUnretainedValue()
    }

    /// The ideal size as the natural size; nothing as the minimum.
    private static let measure: @convention(c) (UnsafeMutablePointer<GtkWidget>?, GtkOrientation, Int32,
                                                UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
                                                UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Void = {
        widget, orientation, _, minimum, natural, minimumBaseline, naturalBaseline in
        minimum?.pointee = 0
        minimumBaseline?.pointee = -1
        naturalBaseline?.pointee = -1
        nonisolated(unsafe) let target = widget
        let size = MainActor.assumeIsolated { () -> Double in
            guard let view = view(of: target) else { return 0 }
            return orientation == GTK_ORIENTATION_HORIZONTAL ? view.properties.idealWidth : view.properties.idealHeight
        }
        natural?.pointee = Int32(min(size.rounded(.up), longestNaturalSize))
    }
}

#endif
