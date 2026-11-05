// Sources/Elements/Map+Adwaita.swift
/*
 Map on GTK: a libshumate map (Interop/ShumateLibrary.swift, loaded at run time) showing
 OpenStreetMap's standard tiles, as Android's map-osm module does, with libshumate's attribution,
 scale, zoom buttons and compass on it. As large as it is offered in both axes, as SwiftUI's Map is.
 - It opens on the value (the coordinate property until a host sets one) framed as Apple frames it:
   a region 0.1 degrees of latitude by 0.1 of longitude, all of it in view. The zoom level that
   shows that is worked out from the map's size when it is first laid out, before it asks for tiles.
 - A later value moves the map's center there (no animation), keeping its zoom, as Android does.
 - When the map stops moving (no change for moveSettleMilliseconds, and no finger or button still
   down), the value follows the center and valueChangeActionID fires if the center moved; actionID
   fires after every move, a host's included, as Apple's onMapCameraChange(frequency: .onEnd)
   does. Moves before the map is first laid out (setting it up) fire nothing.
 - interactionModes: without "pan", dragging, flicking and the arrow keys do nothing; without
   "zoom", the scroll wheel, pinching, double-clicking and the zoom buttons (hidden) do nothing;
   "rotate" turns the two-finger rotation on, but only with "zoom": libshumate's rotation reuses the
   point its pinch-zoom gesture records.
 - Not yet: annotations and showsUserLocation are accepted and not drawn.
 - Without libshumate: a dimmed label naming the package to install (logged once, by ShumateLibrary).
*/

import Glibc
import CAdwaita

/// What a Map's handlers share, kept on its widget.
@MainActor private final class MapState {
    weak var node: RenderNode?
    let library: ShumateLibrary
    let simpleMap: WidgetPointer
    let map: WidgetPointer
    let viewport: OpaquePointer
    /// The center the value was last set to, by a host or from the map, so an update showing it again
    /// moves nothing.
    var lastTracked: ActionUICoordinate?
    /// Set at the first layout with a size, which applies the opening zoom; moves count from then.
    var tracking = false
    /// Counts the map's changes; a settle check scheduled for an older count is dropped.
    var moveCount = 0
    /// libshumate's own input handlers on the map, by what they do.
    var drag: OpaquePointer?
    var swipe: OpaquePointer?
    var scroll: OpaquePointer?
    var zoom: OpaquePointer?
    var rotate: OpaquePointer?
    /// Its double-click zoom: libshumate 1.4 zooms on a double click whatever
    /// shumate_map_set_zoom_on_double_click says (on_click_gesture_pressed never reads it).
    var click: OpaquePointer?

    init(_ node: RenderNode, library: ShumateLibrary, simpleMap: WidgetPointer, map: WidgetPointer, viewport: OpaquePointer) {
        self.node = node
        self.library = library
        self.simpleMap = simpleMap
        self.map = map
        self.viewport = viewport
    }
}

private let mapStateKey = AttachKey<MapState>("actionui-map")

extension Map: ActionUIAdwaitaRenderer {
    /// Apple frames its value in a region this many degrees high and wide.
    static let openingSpan = 0.1

    /// How long the map must stay still for a move to have ended.
    static let moveSettleMilliseconds: UInt32 = 250

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        guard let shumate = ShumateLibrary.shared, let simpleMap = shumate.newSimpleMap(),
              let map = shumate.map(simpleMap), let viewport = shumate.viewport(simpleMap) else {
            let label = gtk_label_new("Map needs libshumate (package \(ShumateLibrary.packageName))")!
            Gtk.Widget(label).setCSSClass("dim-label", true)
            gtk_label_set_wrap(opaque(label), 1)
            return label
        }
        if let source = shumate.standardMapSource {
            shumate.setMapSource(simpleMap, source)
        }
        // The map sits in a container whose layout applies the opening zoom at the first size.
        let container: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(actionUIContainerType(), 0, nil, nil)!))
        gtk_widget_set_layout_manager(container, gtk_custom_layout_new(nil, measureMap, allocateMap))
        gtk_widget_set_parent(simpleMap, container)
        gtk_widget_set_hexpand(container, 1)
        gtk_widget_set_vexpand(container, 1)

        let state = MapState(node, library: shumate, simpleMap: simpleMap, map: map, viewport: viewport)
        findInputHandlers(state)
        attach(state, to: UnsafeMutableRawPointer(container), key: mapStateKey)
        for property in ["latitude", "longitude", "zoom-level", "rotation"] {
            connectSignal(UnsafeMutableRawPointer(viewport), "notify::\(property)", .instanceAndArgument) { [weak state] in
                guard let state else { return }
                mapMoved(state)
            }
        }
        return container
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: UnsafeMutableRawPointer(widget), key: mapStateKey) else { return }
        applyInteractionModes(Props(node.properties).interactionModes, state)
        if let center = node.model.value as? ActionUICoordinate, center != state.lastTracked {
            state.lastTracked = center
            state.library.centerOn(state.map, center.latitude, center.longitude)
        }
    }

    // MARK: Opening zoom

    /// The zoom level that shows a region `openingSpan` degrees high and wide around `latitude`, all
    /// of it, in a map `width` by `height` pixels whose tiles are `tileSize` pixels (zoom level z
    /// draws the world tileSize * 2^z pixels wide, in Web Mercator), within the source's zoom levels.
    static func openingZoomLevel(latitude: Double, width: Int32, height: Int32, tileSize: UInt32,
                                 minZoom: UInt32, maxZoom: UInt32) -> Double {
        let limit = 85.05112878
        func mercatorY(_ degrees: Double) -> Double {
            let clamped = Swift.min(Swift.max(degrees, -limit), limit)
            return log(tan(Double.pi / 4 + clamped * Double.pi / 360))
        }
        let tile = Double(Swift.max(tileSize, 1))
        // The world's width at zoom 0 is `tile`; the span must fit across and down.
        let acrossScale = Double(width) * 360 / (openingSpan * tile)
        let mercatorSpan = mercatorY(latitude + openingSpan / 2) - mercatorY(latitude - openingSpan / 2)
        let downScale = mercatorSpan > 0 ? Double(height) * 2 * Double.pi / (tile * mercatorSpan) : acrossScale
        let level = log2(Swift.min(acrossScale, downScale))
        return Swift.min(Swift.max(level, Double(minZoom)), Double(maxZoom))
    }

    private static let measureMap: @convention(c) (WidgetPointer?, GtkOrientation, Int32, UnsafeMutablePointer<Int32>?,
                                                   UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
                                                   UnsafeMutablePointer<Int32>?) -> Void = { widget, orientation, forSize, minimum, natural, _, _ in
        guard let child = widget.flatMap({ gtk_widget_get_first_child($0) }) else { return }
        gtk_widget_measure(child, orientation, forSize, minimum, natural, nil, nil)
    }

    private static let allocateMap: @convention(c) (WidgetPointer?, Int32, Int32, Int32) -> Void = { widget, width, height, baseline in
        guard let widget, let child = gtk_widget_get_first_child(widget) else { return }
        // A pointer is not Sendable; its address is. GTK lays out on the main thread.
        let address = UInt(bitPattern: widget)
        MainActor.assumeIsolated {
            guard let state = attached(on: UnsafeMutableRawPointer(bitPattern: address)!, key: mapStateKey),
                  !state.tracking, width > 0, height > 0 else { return }
            let library = state.library
            if let source = library.standardMapSource {
                let level = openingZoomLevel(latitude: state.lastTracked?.latitude ?? 0, width: width, height: height,
                                             tileSize: library.tileSize(source), minZoom: library.minZoomLevel(source),
                                             maxZoom: library.maxZoomLevel(source))
                library.setZoomLevel(state.viewport, level)
            }
            state.tracking = true
        }
        gtk_widget_allocate(child, width, height, baseline, nil)
    }

    // MARK: Moves

    private static func mapMoved(_ state: MapState) {
        guard state.tracking else { return }
        state.moveCount += 1
        scheduleSettleCheck(state, count: state.moveCount)
    }

    private static func scheduleSettleCheck(_ state: MapState, count: Int) {
        runAfter(milliseconds: moveSettleMilliseconds) { [weak state] in
            guard let state, state.moveCount == count else { return }
            // A finger or button still down: the move goes on, even standing still.
            let held = [state.drag, state.zoom, state.rotate].contains { gesture in
                gesture.map { gtk_gesture_is_active($0) != 0 } ?? false
            }
            if held {
                scheduleSettleCheck(state, count: count)
            } else {
                moveEnded(state)
            }
        }
    }

    private static func moveEnded(_ state: MapState) {
        guard let node = state.node else { return }
        let library = state.library
        let center = ActionUICoordinate(latitude: library.latitude(state.viewport), longitude: library.longitude(state.viewport))
        let props = Props(node.properties)
        if center != state.lastTracked {
            state.lastTracked = center
            node.model.value = center
            if let actionID = props.valueChangeActionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
            }
        }
        if let actionID = props.actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
    }

    // MARK: Interaction modes

    /// Finds libshumate's input handlers on the map by their GTK types (it adds one of each).
    private static func findInputHandlers(_ state: MapState) {
        let controllers = gtk_widget_observe_controllers(state.map)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            // The map keeps its controllers; the list's reference is given back at once.
            g_object_unref(item)
            let instance: UnsafeMutablePointer<GTypeInstance> = typed(OpaquePointer(item))
            func isA(_ type: GType) -> Bool { g_type_check_instance_is_a(instance, type) != 0 }
            let controller = OpaquePointer(item)
            if isA(gtk_gesture_drag_get_type()) {
                state.drag = controller
            } else if isA(gtk_gesture_swipe_get_type()) {
                state.swipe = controller
            } else if isA(gtk_event_controller_scroll_get_type()) {
                state.scroll = controller
            } else if isA(gtk_gesture_zoom_get_type()) {
                state.zoom = controller
            } else if isA(gtk_gesture_rotate_get_type()) {
                state.rotate = controller
            } else if isA(gtk_gesture_click_get_type()) {
                state.click = controller
            }
        }
    }

    private static func applyInteractionModes(_ modes: [Props.InteractionMode], _ state: MapState) {
        let pan = modes.contains(.pan)
        let zoom = modes.contains(.zoom)
        // libshumate's rotation moves the map around the point its zoom gesture recorded at the start.
        let rotate = zoom && modes.contains(.rotate)
        func enable(_ controller: OpaquePointer?, _ on: Bool) {
            guard let controller else { return }
            let phase = on ? GTK_PHASE_BUBBLE : GTK_PHASE_NONE
            if gtk_event_controller_get_propagation_phase(controller) != phase {
                gtk_event_controller_set_propagation_phase(controller, phase)
            }
        }
        enable(state.drag, pan)
        enable(state.swipe, pan)
        gtk_widget_action_set_enabled(state.map, "pan", pan ? 1 : 0)
        enable(state.scroll, zoom)
        enable(state.zoom, zoom)
        enable(state.click, zoom)
        state.library.setZoomOnDoubleClick(state.map, zoom ? 1 : 0)
        state.library.setShowZoomButtons(state.simpleMap, zoom ? 1 : 0)
        enable(state.rotate, rotate)
    }
}
