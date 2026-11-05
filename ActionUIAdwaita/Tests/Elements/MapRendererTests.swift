// Tests/Elements/MapRendererTests.swift
/*
 Tests for the Map renderer on GTK, over libshumate loaded at run time: without the library, a
 placeholder naming its package; the opening zoom frames Apple's 0.1-degree region in the map's
 size; the map opens on the value at that zoom when first laid out; a move of the map sets the value
 and fires valueChangeActionID and actionID once it settles, a host's value moves the map and fires
 only actionID, and nothing fires before the first layout; interactionModes turn libshumate's input
 handlers off and on; each annotation is a pin, with its tip on the coordinate, and its title and
 subtitle, replaced when the annotations change; with showsUserLocation, while the map is on screen,
 the user's location is a dot that moves nothing and fires nothing. The renderer tests need
 libshumate (package libshumate-1.0-1) and skip without it; none needs the tiles or the location
 portal (a stand-in sends the locations).
*/

import XCTest
import CAdwaita
@testable import ActionUI

/// Sends the locations a test gives to the maps listening, and counts them.
@MainActor private final class StandInLocationSource: UserLocationSource {
    var listeners: [Int: @MainActor (ActionUICoordinate) -> Void] = [:]
    var starts = 0
    private var nextToken = 1

    func startUpdates(_ update: @escaping @MainActor (ActionUICoordinate) -> Void) -> Int {
        starts += 1
        let token = nextToken
        nextToken += 1
        listeners[token] = update
        return token
    }

    func stopUpdates(_ token: Int) {
        listeners[token] = nil
    }

    func send(_ coordinate: ActionUICoordinate) {
        for update in listeners.values {
            update(coordinate)
        }
    }
}

@MainActor
final class MapRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var shownWindows: [UnsafeMutablePointer<GtkWindow>] = []
    private let location = StandInLocationSource()
    private var fired: [String] = []
    private let actionIDs = ["test.camera", "test.center"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "map-\(name)"
        fired = []
        LocationPortal.shared = location
        for actionID in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] actionID, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(actionID) }
            }
        }
    }

    override func tearDown() async throws {
        for window in shownWindows {
            gtk_window_destroy(window)
        }
        shownWindows = []
        windows = []
        LocationPortal.shared = LocationPortal()
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

    // MARK: Annotations

    private let annotations = #""annotations": [{"coordinate": {"latitude": 37.332, "longitude": -122.031}, "title": "Point", "subtitle": "Subtitle"}, {"coordinate": {"latitude": 37.36, "longitude": -122.05}, "title": "Only a title"}, {"coordinate": {"latitude": 37.31, "longitude": -122.0}}, {"coordinate": {"latitude": "bad", "longitude": 0}, "title": "Skipped"}]"#

    /// The markers on the map, in order.
    private func markers(_ node: RenderNode) throws -> [WidgetPointer] {
        let map = try maps(node).map
        let layer = try XCTUnwrap(Gtk.Widget(map).children.map(\.pointer).first {
            swiftString(g_type_name_from_instance(typed(OpaquePointer($0)))) == "ShumateMarkerLayer"
        })
        return Gtk.Widget(layer).children.map(\.pointer)
    }

    /// The box of a marker's labels, under its pin.
    private func textBox(_ marker: WidgetPointer) throws -> WidgetPointer {
        let view = try XCTUnwrap(gtk_widget_get_first_child(marker))
        return try XCTUnwrap(gtk_widget_get_first_child(view).flatMap { gtk_widget_get_next_sibling($0) })
    }

    /// The texts of the labels in a marker, in order.
    private func texts(_ marker: WidgetPointer) throws -> [String] {
        Gtk.Widget(try textBox(marker)).children.map { swiftString(gtk_label_get_text(opaque($0.pointer))) ?? "?" }
    }

    func testEachAnnotationIsAPinWithItsTitleAndSubtitleAtItsCoordinate() throws {
        let library = try requireShumate()
        let node = try render(annotations)
        let markers = try markers(node)
        // The one without a valid coordinate is skipped, as on Apple.
        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers.map { library.latitude(OpaquePointer($0)) }, [37.332, 37.36, 37.31])
        XCTAssertEqual(markers.map { library.longitude(OpaquePointer($0)) }, [-122.031, -122.05, -122.0])
        XCTAssertEqual(try texts(markers[0]), ["Point", "Subtitle"])
        XCTAssertEqual(try texts(markers[1]), ["Only a title"])
        XCTAssertEqual(try texts(markers[2]), [])
        let labels = Gtk.Widget(try textBox(markers[0])).children.map(\.pointer)
        XCTAssertNotEqual(gtk_widget_has_css_class(labels[0], "caption-heading"), 0)
        XCTAssertNotEqual(gtk_widget_has_css_class(labels[1], "caption"), 0)
        // A drag that starts on a pin moves the map.
        XCTAssertTrue(markers.allSatisfy { gtk_widget_get_can_target($0) == 0 })
    }

    func testThePinsTipIsOnItsCoordinateInTheLaidOutMap() throws {
        _ = try requireShumate()
        // Pins at the map's center, with and without text, so their points belong at the middle.
        let center = #"{"latitude": 37.33233141, "longitude": -122.0312186}"#
        let node = try render(#""annotations": [{"coordinate": "# + center + #", "title": "Point", "subtitle": "Subtitle"}, {"coordinate": "# + center + #"}]"#)
        layOut(node, width: 400, height: 400)
        let map = try maps(node).map
        for marker in try markers(node) {
            let pin = try XCTUnwrap(gtk_widget_get_first_child(try XCTUnwrap(gtk_widget_get_first_child(marker))))
            var bounds = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(pin, map, &bounds), 0)
            XCTAssertEqual(bounds.size.height, Float(Map.pinSize))
            // The glyph's point is a twelfth of the pin above the bottom of its square.
            let tip = bounds.origin.y + bounds.size.height - Float(Map.pinSize) / 12
            XCTAssertEqual(tip, 200, accuracy: 1.5)
            XCTAssertEqual(bounds.origin.x + bounds.size.width / 2, 200, accuracy: 1.5)
        }
    }

    func testNewAnnotationsReplaceThePins() throws {
        let library = try requireShumate()
        let node = try render(annotations)
        XCTAssertEqual(try markers(node).count, 3)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "annotations", value: [
            ["coordinate": ["latitude": 48.8584, "longitude": 2.2945], "title": "Eiffel Tower"],
        ])
        AdwaitaTestHost.drainMainLoop()
        let replaced = try markers(node)
        XCTAssertEqual(replaced.count, 1)
        XCTAssertEqual(library.latitude(OpaquePointer(replaced[0])), 48.8584)
        XCTAssertEqual(try texts(replaced[0]), ["Eiffel Tower"])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "annotations", value: [Any]())
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try markers(node).count, 0)
    }

    // MARK: User location

    /// `node`'s window on screen.
    private func show(_ node: RenderNode) throws {
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        shownWindows.append(window)
        adw_window_set_content(typed(window), try XCTUnwrap(windows.last).contentWidget)
        gtk_window_present(window)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
    }

    /// libshumate's location dots on the map.
    private func userLocationDots(_ node: RenderNode) throws -> [WidgetPointer] {
        let layers = Gtk.Widget(try maps(node).map).children.map(\.pointer).filter {
            swiftString(g_type_name_from_instance(typed(OpaquePointer($0)))) == "ShumateMarkerLayer"
        }
        return layers.flatMap { Gtk.Widget($0).children.map(\.pointer) }.filter {
            swiftString(g_type_name_from_instance(typed(OpaquePointer($0)))) == "ShumatePoint"
        }
    }

    private let apple = ActionUICoordinate(latitude: 37.3349, longitude: -122.009)

    func testTheUserLocationIsADotThatMovesNothingAndFiresNothing() throws {
        let library = try requireShumate()
        let node = try render(#""showsUserLocation": true"#)
        try show(node)
        XCTAssertEqual(location.starts, 1)
        XCTAssertEqual(try userLocationDots(node).count, 0, "no dot before a location")
        let viewport = try viewport(node, library)
        location.send(apple)
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: Int(Map.moveSettleMilliseconds) * 2)
        let dots = try userLocationDots(node)
        XCTAssertEqual(dots.count, 1)
        XCTAssertEqual(library.latitude(OpaquePointer(dots[0])), apple.latitude)
        XCTAssertEqual(library.longitude(OpaquePointer(dots[0])), apple.longitude)
        XCTAssertNotEqual(gtk_widget_get_visible(dots[0]), 0)
        XCTAssertEqual(gtk_widget_get_can_target(dots[0]), 0, "a drag that starts on the dot moves the map")
        // The map stays where it was, with its value, and nothing fires.
        XCTAssertEqual(library.latitude(viewport), cupertino.latitude, accuracy: 1e-9)
        XCTAssertEqual(library.longitude(viewport), cupertino.longitude, accuracy: 1e-9)
        XCTAssertEqual(node.model.value as? ActionUICoordinate, cupertino)
        XCTAssertEqual(fired, [])
        // A new location moves the dot.
        location.send(ActionUICoordinate(latitude: 37.34, longitude: -122.02))
        XCTAssertEqual(try userLocationDots(node).count, 1)
        XCTAssertEqual(library.latitude(OpaquePointer(dots[0])), 37.34)
    }

    func testWithoutShowsUserLocationTheMapDoesNotAskForTheLocation() throws {
        _ = try requireShumate()
        let node = try render()
        try show(node)
        XCTAssertEqual(location.starts, 0)
        XCTAssertEqual(try userLocationDots(node).count, 0)
    }

    func testTheMapAsksForTheLocationOnlyWhileOnScreen() throws {
        _ = try requireShumate()
        let node = try render(#""showsUserLocation": true"#)
        XCTAssertEqual(location.starts, 0, "not on screen yet")
        try show(node)
        XCTAssertEqual(location.starts, 1)
        XCTAssertEqual(location.listeners.count, 1)
        gtk_widget_set_visible(typed(try XCTUnwrap(shownWindows.last)), 0)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) == 0 }))
        XCTAssertEqual(location.listeners.count, 0, "stopped when hidden")
        gtk_window_present(try XCTUnwrap(shownWindows.last))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        XCTAssertEqual(location.starts, 2)
        XCTAssertEqual(location.listeners.count, 1)
    }

    func testAMapShownAgainHasNoDotUntilALocationComes() throws {
        _ = try requireShumate()
        let node = try render(#""showsUserLocation": true"#)
        try show(node)
        location.send(apple)
        let dot = try XCTUnwrap(try userLocationDots(node).first)
        let window = try XCTUnwrap(shownWindows.last)
        gtk_widget_set_visible(typed(window), 0)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) == 0 }))
        XCTAssertEqual(gtk_widget_get_visible(dot), 0, "hidden when the map stops listening")
        gtk_window_present(window)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        XCTAssertEqual(gtk_widget_get_visible(dot), 0, "the location service may have been turned off meanwhile")
        location.send(apple)
        XCTAssertNotEqual(gtk_widget_get_visible(dot), 0)
    }

    func testClosingTheWindowStopsTheLocation() throws {
        _ = try requireShumate()
        let node = try render(#""showsUserLocation": true"#)
        try show(node)
        XCTAssertEqual(location.listeners.count, 1)
        gtk_window_destroy(try XCTUnwrap(shownWindows.popLast()))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(location.listeners.count, 0)
    }

    func testTurningShowsUserLocationOffStopsAndHidesTheDot() throws {
        _ = try requireShumate()
        let node = try render(#""showsUserLocation": true"#)
        try show(node)
        location.send(apple)
        let dot = try XCTUnwrap(try userLocationDots(node).first)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "showsUserLocation", value: false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(location.listeners.count, 0)
        XCTAssertEqual(gtk_widget_get_visible(dot), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "showsUserLocation", value: true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(location.starts, 2)
        location.send(apple)
        XCTAssertNotEqual(gtk_widget_get_visible(dot), 0)
        XCTAssertEqual(try userLocationDots(node).count, 1, "the same dot again")
    }
}
