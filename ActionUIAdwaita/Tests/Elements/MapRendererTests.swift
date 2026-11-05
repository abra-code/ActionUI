// Tests/Elements/MapRendererTests.swift
/*
 Tests for the Map renderer on GTK, over libshumate loaded at run time: without the library, a
 placeholder naming its package; the opening zoom frames Apple's 0.1-degree region in the map's
 size; the map opens on the value at that zoom when first laid out; a move of the map sets the value
 and fires valueChangeActionID and actionID once it settles, a host's value moves the map and fires
 only actionID, and nothing fires before the first layout; interactionModes turn libshumate's input
 handlers off and on. The renderer tests need libshumate (package libshumate-1.0-1) and skip without
 it; none needs the tiles.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class MapRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []
    private let actionIDs = ["test.camera", "test.center"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "map-\(name)"
        fired = []
        for actionID in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] actionID, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(actionID) }
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for actionID in actionIDs {
            ActionUIModel.shared.unregisterActionHandler(for: actionID)
        }
        ShumateLibrary.disabledForTesting = false
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private let cupertino = ActionUICoordinate(latitude: 37.33233141, longitude: -122.0312186)

    private func render(_ properties: String = "") throws -> RenderNode {
        let base = #""coordinate": {"latitude": 37.33233141, "longitude": -122.0312186}, "actionID": "test.camera", "valueChangeActionID": "test.center""#
        let json = #"{"type": "Map", "id": 1, "properties": {"# + base + (properties.isEmpty ? "" : ", " + properties) + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func requireShumate() throws -> ShumateLibrary {
        guard let library = ShumateLibrary.shared else {
            throw XCTSkip("libshumate is not installed (package \(ShumateLibrary.packageName))")
        }
        return library
    }

    /// The ShumateSimpleMap and the ShumateMap inside the node's container.
    private func maps(_ node: RenderNode) throws -> (simpleMap: WidgetPointer, map: WidgetPointer) {
        let simpleMap = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        let map = try XCTUnwrap(gtk_widget_get_first_child(simpleMap))
        XCTAssertEqual(swiftString(g_type_name_from_instance(typed(OpaquePointer(map)))), "ShumateMap")
        return (simpleMap, map)
    }

    private func viewport(_ node: RenderNode, _ library: ShumateLibrary) throws -> OpaquePointer {
        try XCTUnwrap(library.viewport(try maps(node).simpleMap))
    }

    private func layOut(_ node: RenderNode, width: Int32 = 400, height: Int32 = 400) {
        let widget = node.outerWidget!
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, nil, nil, nil, nil)
        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, width, nil, nil, nil, nil)
        gtk_widget_allocate(widget, width, height, -1, nil)
    }

    /// The propagation phase of each of libshumate's input handlers on the map, by GTK type name.
    private func phases(_ node: RenderNode) throws -> [String: GtkPropagationPhase] {
        let controllers = gtk_widget_observe_controllers(try maps(node).map)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        var result: [String: GtkPropagationPhase] = [:]
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            defer { g_object_unref(item) }
            let name = swiftString(g_type_name_from_instance(typed(OpaquePointer(item)))) ?? "?"
            result[name] = gtk_event_controller_get_propagation_phase(OpaquePointer(item))
        }
        return result
    }

    /// Runs the main loop until the map's move has settled and fired `count` actions.
    private func waitForActions(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let done = AdwaitaTestHost.runMainLoop(until: { fired.count >= count }, timeoutMilliseconds: 3000)
        XCTAssertTrue(done, "fired \(fired), expected \(count) actions", file: file, line: line)
        // Nothing more comes after a settled move.
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: Int(Map.moveSettleMilliseconds) * 2)
    }

    func testWithoutLibshumateTheMapShowsAPlaceholderNamingThePackage() throws {
        ShumateLibrary.disabledForTesting = true
        let node = try render()
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(node.widget))), "Map needs libshumate (package libshumate-1.0-1)")
        XCTAssertNotEqual(gtk_widget_has_css_class(node.widget, "dim-label"), 0)
    }

    func testTheOpeningZoomShowsApplesRegionInTheMapsSize() {
        // At the equator 0.1 degree is as high as it is wide: 400 pixels show it at 2^z = 400 * 360 /
        // (0.1 * 256) = 5625.
        XCTAssertEqual(Map.openingZoomLevel(latitude: 0, width: 400, height: 400, tileSize: 256, minZoom: 0, maxZoom: 18),
                       log2(5625), accuracy: 0.001)
        // The narrower side decides: twice as wide shows more longitude at the same zoom.
        XCTAssertEqual(Map.openingZoomLevel(latitude: 0, width: 800, height: 400, tileSize: 256, minZoom: 0, maxZoom: 18),
                       log2(5625), accuracy: 0.001)
        // At 60 degrees a degree of latitude is drawn twice as high (1 / cos 60), so one zoom level less.
        XCTAssertEqual(Map.openingZoomLevel(latitude: 60, width: 400, height: 400, tileSize: 256, minZoom: 0, maxZoom: 18),
                       log2(5625) - 1, accuracy: 0.001)
        // Within the source's zoom levels.
        XCTAssertEqual(Map.openingZoomLevel(latitude: 0, width: 10_000_000, height: 10_000_000, tileSize: 256, minZoom: 0, maxZoom: 18), 18)
        XCTAssertEqual(Map.openingZoomLevel(latitude: 0, width: 1, height: 1, tileSize: 256, minZoom: 5, maxZoom: 18), 5)
    }

    func testTheMapOpensOnTheValueAtTheOpeningZoomWhenFirstLaidOut() throws {
        let library = try requireShumate()
        let node = try render()
        let viewport = try viewport(node, library)
        XCTAssertEqual(node.model.value as? ActionUICoordinate, cupertino)
        XCTAssertEqual(library.latitude(viewport), cupertino.latitude)
        XCTAssertEqual(library.longitude(viewport), cupertino.longitude)
        layOut(node, width: 600, height: 400)
        let expected = Map.openingZoomLevel(latitude: cupertino.latitude, width: 600, height: 400, tileSize: 256, minZoom: 0, maxZoom: 18)
        XCTAssertEqual(library.zoomLevel(viewport), expected, accuracy: 0.0001)
        // The same in numbers: 400 pixels high at 37.33 degrees, a little over 12.
        XCTAssertEqual(library.zoomLevel(viewport), 12.13, accuracy: 0.01)
        XCTAssertEqual(library.latitude(viewport), cupertino.latitude)
        // Opening is no move: nothing fires.
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: Int(Map.moveSettleMilliseconds) * 2)
        XCTAssertEqual(fired, [])
    }

    func testAMoveOfTheMapSetsTheValueAndFiresBothActionsOnceSettled() throws {
        let library = try requireShumate()
        let node = try render()
        layOut(node)
        // As a drag would: the map's own center moves, not the value.
        library.centerOn(try maps(node).map, 40.7128, -74.0060)
        XCTAssertEqual(fired, [], "nothing before the move settles")
        waitForActions(2)
        XCTAssertEqual(fired, ["test.center", "test.camera"])
        XCTAssertEqual(node.model.value as? ActionUICoordinate, ActionUICoordinate(latitude: 40.7128, longitude: -74.0060))
    }

    func testAZoomAloneFiresOnlyTheCameraAction() throws {
        let library = try requireShumate()
        let node = try render()
        layOut(node)
        let viewport = try viewport(node, library)
        library.setZoomLevel(viewport, library.zoomLevel(viewport) + 1)
        waitForActions(1)
        XCTAssertEqual(fired, ["test.camera"])
        XCTAssertEqual(node.model.value as? ActionUICoordinate, cupertino)
    }

    func testAHostValueMovesTheMapAndFiresOnlyTheCameraAction() throws {
        let library = try requireShumate()
        let node = try render()
        layOut(node)
        let viewport = try viewport(node, library)
        let zoom = library.zoomLevel(viewport)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: ActionUICoordinate(latitude: 51.5, longitude: -0.13))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { library.latitude(viewport) == 51.5 }))
        XCTAssertEqual(library.longitude(viewport), -0.13)
        XCTAssertEqual(library.zoomLevel(viewport), zoom, "a new center keeps the zoom")
        waitForActions(1)
        XCTAssertEqual(fired, ["test.camera"])
    }

    func testNothingFiresBeforeTheFirstLayout() throws {
        let library = try requireShumate()
        let node = try render()
        let viewport = try viewport(node, library)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: ActionUICoordinate(latitude: 51.5, longitude: -0.13))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { library.latitude(viewport) == 51.5 }))
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: Int(Map.moveSettleMilliseconds) * 2)
        XCTAssertEqual(fired, [])
        // The opening zoom frames the value the map has by then.
        layOut(node)
        XCTAssertEqual(library.zoomLevel(viewport),
                       Map.openingZoomLevel(latitude: 51.5, width: 400, height: 400, tileSize: 256, minZoom: 0, maxZoom: 18), accuracy: 0.0001)
    }

    func testInteractionModesTurnTheMapsInputHandlersOffAndOn() throws {
        _ = try requireShumate()
        let node = try render()
        let all = try phases(node)
        for name in ["GtkGestureDrag", "GtkGestureSwipe", "GtkEventControllerScroll", "GtkGestureZoom", "GtkGestureRotate", "GtkGestureClick"] {
            XCTAssertEqual(all[name], GTK_PHASE_BUBBLE, "\(name) is on by default")
        }

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "interactionModes", value: ["pan"])
        AdwaitaTestHost.drainMainLoop()
        let pan = try phases(node)
        XCTAssertEqual(pan["GtkGestureDrag"], GTK_PHASE_BUBBLE)
        XCTAssertEqual(pan["GtkGestureSwipe"], GTK_PHASE_BUBBLE)
        XCTAssertEqual(pan["GtkEventControllerScroll"], GTK_PHASE_NONE)
        XCTAssertEqual(pan["GtkGestureZoom"], GTK_PHASE_NONE)
        XCTAssertEqual(pan["GtkGestureRotate"], GTK_PHASE_NONE)
        XCTAssertEqual(pan["GtkGestureClick"], GTK_PHASE_NONE, "libshumate 1.4 zooms on a double click with zoom-on-double-click off")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "interactionModes", value: ["zoom", "rotate"])
        AdwaitaTestHost.drainMainLoop()
        let zoomRotate = try phases(node)
        XCTAssertEqual(zoomRotate["GtkGestureDrag"], GTK_PHASE_NONE)
        XCTAssertEqual(zoomRotate["GtkGestureSwipe"], GTK_PHASE_NONE)
        XCTAssertEqual(zoomRotate["GtkEventControllerScroll"], GTK_PHASE_BUBBLE)
        XCTAssertEqual(zoomRotate["GtkGestureZoom"], GTK_PHASE_BUBBLE)
        XCTAssertEqual(zoomRotate["GtkGestureRotate"], GTK_PHASE_BUBBLE)
        XCTAssertEqual(zoomRotate["GtkGestureClick"], GTK_PHASE_BUBBLE)

        // Rotation needs the zoom gesture.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "interactionModes", value: ["pan", "rotate"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try phases(node)["GtkGestureRotate"], GTK_PHASE_NONE)
    }
}
