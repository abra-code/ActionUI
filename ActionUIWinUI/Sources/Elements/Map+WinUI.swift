// Sources/Elements/Map+WinUI.swift
/*
 Map on WinUI: a map of OpenStreetMap's standard tiles drawn by the shim (actionUIWinUIMapCreate), as
 Android's map-osm module and the Linux renderer (Map+Adwaita.swift) show them, with OpenStreetMap's
 attribution and zoom buttons on it. As large as it is offered in both axes, as SwiftUI's Map is.
 - Tiles are fetched with Windows' HTTP client, whose cache honors the server's cache headers; the
   User-Agent names the program and ActionUI's version, as OpenStreetMap's tile usage policy asks.
   A few seconds after the map is first laid out, how many tiles loaded (and why one failed) is
   logged, so a map left empty by a blocked network says why.
 - It opens on the value (the coordinate property until a host sets one) framed as Apple frames it:
   a region 0.1 degrees of latitude by 0.1 of longitude, all of it in view. The zoom level that
   shows that is worked out from the map's size when it is first laid out.
 - A later value moves the map's center there (no animation), keeping its zoom, as on Linux and
   Android.
 - When the map stops moving (no change for moveSettleMilliseconds, and no press or flick still
   going), the value follows the center and valueChangeActionID fires if the center moved; actionID
   fires after every move, a host's included, as Apple's onMapCameraChange(frequency: .onEnd) does.
   Moves before the map is first laid out (setting it up) fire nothing.
 - interactionModes: without "pan", dragging and flicking do nothing; without "zoom", the wheel,
   pinching, double-tapping and the zoom buttons (hidden) do nothing. "rotate" is ignored: the map
   always points north.

 Not yet (logged once): annotations and showsUserLocation.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
// log, tan: FoundationEssentials does not bring the C math library on Windows.
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import ucrt
#endif
import CWinUI
import Dispatch

@MainActor private var reportedAnnotations = false
@MainActor private var reportedUserLocation = false

/// What a Map's handlers share, kept in its node's state.
@MainActor final class MapState {
    let map: WinUIObject
    let fill: FillLayout
    /// The center the value was last set to, by a host or from the map, so an update showing it again
    /// moves nothing.
    var lastTracked: ActionUICoordinate?
    /// Set at the first layout with a size, which applies the opening zoom; moves count from then.
    var tracking = false
    /// Counts the map's changes; a settle check scheduled for an older count is dropped.
    var moveCount = 0
    /// The camera when the last move ended (or the map opened): the shim also reports a press or a
    /// flick that ends, so one that left the camera where it was (a click) fires nothing, as on Apple
    /// and Linux.
    var settledCamera: (latitude: Double, longitude: Double, zoom: Double)?

    init(map: WinUIObject, fill: FillLayout) {
        self.map = map
        self.fill = fill
    }
}

extension Map: ActionUIWinUIRenderer {
    /// Apple frames its value in a region this many degrees high and wide.
    static let openingSpan = 0.1
    /// How long the map must stay still for a move to have ended.
    static let moveSettleMilliseconds = 250
    /// How long after the first layout the tiles' outcome is logged.
    static let tileReportSeconds = 5
    /// OpenStreetMap's tiles: 256 pixels, zoom levels 0 to 19.
    static let tileSize = 256.0
    static let maxZoomLevel = 19.0

    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let map = WinUIObject(adopting: actionUIWinUIMapCreate(userAgent)) else {
            throw WinUIError.last("creating a Map")
        }
        let fill = try FillLayout(child: map)
        let state = MapState(map: map, fill: fill)
        node.state = state
        fill.arranged = { [weak node, weak state] size in
            guard let node, let state, !state.tracking, size.width > 0, size.height > 0 else { return }
            open(node, state, size)
        }
        WinUIEvents.connect(map, actionUIWinUIMapOnMoved, "a Map's moves") { [weak node, weak state] in
            guard let node, let state, node.isAttached, state.tracking else { return }
            state.moveCount += 1
            scheduleSettleCheck(node, state, count: state.moveCount)
        }
        return fill.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? MapState else { return }
        let props = Props(node.properties)
        let modes = props.interactionModes
        if !actionUIWinUIMapSetInteraction(state.map.pointer, modes.contains(.pan), modes.contains(.zoom)) {
            ActionUIModel.shared.logger.log("Map: \(WinUIError.last("setting its interaction modes"))", .error)
        }
        reportNotYet(props)
        guard let center = initialValue(node.model) as? ActionUICoordinate, center != state.lastTracked else { return }
        state.lastTracked = center
        // Before the first layout the opening zoom comes with it (open).
        guard state.tracking else { return }
        if !actionUIWinUIMapSetCamera(state.map.pointer, center.latitude, center.longitude, -1) {
            ActionUIModel.shared.logger.log("Map: \(WinUIError.last("moving to \(center)"))", .error)
        }
    }

    /// The User-Agent tile requests carry: the program's name, then ActionUI's version, as
    /// OpenStreetMap's tile usage policy asks.
    static var userAgent: String {
        var name = CommandLine.arguments.first ?? ""
        if let separator = name.lastIndex(where: { $0 == "\\" || $0 == "/" }) {
            name = String(name[name.index(after: separator)...])
        }
        if name.lowercased().hasSuffix(".exe") {
            name = String(name.dropLast(4))
        }
        return "\(name.isEmpty ? "ActionUI-app" : name) ActionUI/\(ActionUIVersion.string) WinUI"
    }

    // MARK: Opening

    /// The zoom level that shows a region `openingSpan` degrees high and wide around `latitude`, all
    /// of it, in a map `width` by `height` pixels (zoom level z draws the world tileSize * 2^z pixels
    /// wide, in Web Mercator), within the tiles' zoom levels; as on Linux.
    static func openingZoomLevel(latitude: Double, width: Double, height: Double) -> Double {
        let limit = 85.05112878
        func mercatorY(_ degrees: Double) -> Double {
            let clamped = Swift.min(Swift.max(degrees, -limit), limit)
            return log(tan(Double.pi / 4 + clamped * Double.pi / 360))
        }
        let acrossScale = width * 360 / (openingSpan * tileSize)
        let mercatorSpan = mercatorY(latitude + openingSpan / 2) - mercatorY(latitude - openingSpan / 2)
        let downScale = mercatorSpan > 0 ? height * 2 * Double.pi / (tileSize * mercatorSpan) : acrossScale
        let level = log2(Swift.min(acrossScale, downScale))
        return Swift.min(Swift.max(level, 0), maxZoomLevel)
    }

    /// At the first layout with a size: the value framed at the opening zoom, then moves count.
    private static func open(_ node: RenderNode, _ state: MapState, _ size: ActionUIWinUISize) {
        let center = state.lastTracked ?? ActionUICoordinate(latitude: 0, longitude: 0)
        let zoom = openingZoomLevel(latitude: center.latitude, width: size.width, height: size.height)
        if !actionUIWinUIMapSetCamera(state.map.pointer, center.latitude, center.longitude, zoom) {
            ActionUIModel.shared.logger.log("Map: \(WinUIError.last("opening at \(center)"))", .error)
        }
        var camera = ActionUIWinUIMapCamera(latitude: 0, longitude: 0, zoom: 0, interacting: false)
        if actionUIWinUIMapGetCamera(state.map.pointer, &camera) {
            state.settledCamera = (camera.latitude, camera.longitude, camera.zoom)
        }
        state.tracking = true
        let map = state.map
        let id = node.element.id
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(tileReportSeconds)) { [weak map] in
            MainActor.assumeIsolated {
                guard let map, let copy = actionUIWinUIMapCopyStatus(map.pointer) else { return }
                let status = String(cString: copy)
                actionUIWinUIFreeString(copy)
                if status.hasPrefix("0 tiles loaded") {
                    ActionUIModel.shared.logger.log("Map \(id) has no tiles: \(status)", .warning)
                } else {
                    ActionUIModel.shared.logger.log("Map \(id) tiles: \(status)", .info)
                }
            }
        }
    }

    // MARK: Moves

    private static func scheduleSettleCheck(_ node: RenderNode, _ state: MapState, count: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(moveSettleMilliseconds)) { [weak node, weak state] in
            MainActor.assumeIsolated {
                guard let node, let state, node.isAttached, state.moveCount == count else { return }
                var camera = ActionUIWinUIMapCamera(latitude: 0, longitude: 0, zoom: 0, interacting: false)
                guard actionUIWinUIMapGetCamera(state.map.pointer, &camera) else { return }
                // A finger or button still down, or a flick still going: the move goes on.
                if camera.interacting {
                    scheduleSettleCheck(node, state, count: count)
                } else {
                    moveEnded(node, state, camera)
                }
            }
        }
    }

    private static func moveEnded(_ node: RenderNode, _ state: MapState, _ camera: ActionUIWinUIMapCamera) {
        let settled = (latitude: camera.latitude, longitude: camera.longitude, zoom: camera.zoom)
        if let last = state.settledCamera, last == settled { return }
        state.settledCamera = settled
        let center = ActionUICoordinate(latitude: camera.latitude, longitude: camera.longitude)
        let props = Props(node.properties)
        let windowUUID = node.windowModel.windowUUID
        if center != state.lastTracked {
            state.lastTracked = center
            node.model.value = center
            if let actionID = props.valueChangeActionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0)
            }
        }
        if let actionID = props.actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0)
        }
    }

    /// Logs, once per process each, what the Windows map does not show.
    private static func reportNotYet(_ props: Props) {
        let logger = ActionUIModel.shared.logger
        if !props.annotations.isEmpty, !reportedAnnotations {
            reportedAnnotations = true
            logger.log("Map: annotations are not shown on Windows yet", .warning)
        }
        if props.showsUserLocation, !reportedUserLocation {
            reportedUserLocation = true
            logger.log("Map: showsUserLocation is not shown on Windows yet", .warning)
        }
    }
}
