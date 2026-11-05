// Tests/Runtime/BoxAnimationTests.swift
/*
 Tests for the animation modifier on GTK: SwiftUI's curves (AnimationTiming), when a sync animates
 (the trigger, as on Apple), the box's own visuals moving through a libadwaita animation
 (BoxAnimator), and colors through a CSS transition, in a window on screen (an animation of a
 widget that is not mapped ends at once).

 The tests turn GTK's animations on for themselves: GNOME turns them off in the agent-vm boxes
 (measured: the desktop portal reports enable-animations false on Debian 13 and Ubuntu 26.04
 there, though the GSettings key is true), and libadwaita and GTK then end every animation at once,
 as they should.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class BoxAnimationTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var shownWindows: [UnsafeMutablePointer<GtkWidget>] = []
    private var animationsWereEnabled = true

    override func setUp() async throws {
        // No super.setUp(): see PaintModifierTests.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        windowUUID = "animation-\(name)"
        animationsWereEnabled = Self.animationsEnabled
        Self.animationsEnabled = true
    }

    /// GtkSettings:gtk-enable-animations.
    private static var animationsEnabled: Bool {
        get {
            var value = GValue()
            g_value_init(&value, GType(5 << 2))  // G_TYPE_BOOLEAN, a macro Swift cannot import
            defer { g_value_unset(&value) }
            g_object_get_property(typed(gtk_settings_get_default()!), "gtk-enable-animations", &value)
            return g_value_get_boolean(&value) != 0
        }
        set {
            var value = GValue()
            g_value_init(&value, GType(5 << 2))
            defer { g_value_unset(&value) }
            g_value_set_boolean(&value, newValue ? 1 : 0)
            g_object_set_property(typed(gtk_settings_get_default()!), "gtk-enable-animations", &value)
        }
    }

    override func tearDown() async throws {
        for window in shownWindows {
            gtk_window_set_child(typed(window), nil)
            gtk_window_destroy(typed(window))
        }
        shownWindows = []
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
        Self.animationsEnabled = animationsWereEnabled
    }

    // MARK: Curves

    private func timing(_ json: Any) throws -> AnimationTiming {
        AnimationTiming(try XCTUnwrap(ModifierParsing.animation(json)))
    }

    func testTheCurvesAreSwiftUIs() throws {
        XCTAssertEqual(try timing("linear").curve, .bezier(x1: 0, y1: 0, x2: 1, y2: 1, duration: 0.35))
        XCTAssertEqual(try timing("easeIn").curve, .bezier(x1: 0.42, y1: 0, x2: 1, y2: 1, duration: 0.35))
        XCTAssertEqual(try timing("easeOut").curve, .bezier(x1: 0, y1: 0, x2: 0.58, y2: 1, duration: 0.35))
        XCTAssertEqual(try timing("easeInOut").curve, .bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1, duration: 0.35))
        // default is the smooth spring on macOS 27, not easeInOut.
        for name in ["default", "spring", "smooth"] {
            XCTAssertEqual(try timing(name).curve, .spring(response: 0.5, dampingRatio: 1), name)
        }
        XCTAssertEqual(try timing("snappy").curve, .spring(response: 0.5, dampingRatio: 0.85))
        XCTAssertEqual(try timing("bouncy").curve, .spring(response: 0.5, dampingRatio: 0.7))
        XCTAssertEqual(try timing(["curve": "bouncy", "duration": 1.0]).curve, .spring(response: 1, dampingRatio: 0.7))
        XCTAssertEqual(try timing(["curve": "easeOut", "duration": 1.0]).curve, .bezier(x1: 0, y1: 0, x2: 0.58, y2: 1, duration: 1))
        // interactiveSpring takes no duration.
        XCTAssertEqual(try timing(["curve": "interactiveSpring", "duration": 1.0]).curve, .spring(response: 0.15, dampingRatio: 0.85))
    }

    func testSpeedDividesTheDurationTheDelayAndTheResponse() throws {
        let timed = try timing(["curve": "linear", "duration": 0.4, "delay": 0.2, "speed": 2.0])
        XCTAssertEqual(timed.curve, .bezier(x1: 0, y1: 0, x2: 1, y2: 1, duration: 0.2))
        XCTAssertEqual(timed.delay, 0.1)
        XCTAssertEqual(try timing(["curve": "smooth", "speed": 2.0]).curve, .spring(response: 0.25, dampingRatio: 1))
    }

    func testExtremeTimingsStayInRange() throws {
        let long = try timing(["curve": "linear", "duration": 1e300, "delay": 1e300])
        XCTAssertEqual(long.curve, .bezier(x1: 0, y1: 0, x2: 1, y2: 1, duration: 1_000_000))
        XCTAssertEqual(long.delay, 1_000_000)
        XCTAssertEqual(long.cssDeclarations(["color"])[1], "transition-duration: 1000000000ms;")
        XCTAssertEqual(try timing(["curve": "linear", "delay": 1.0, "speed": 1e-300]).delay, 1_000_000)
        XCTAssertEqual(try timing(["curve": "smooth", "speed": 1e300]).curve, .spring(response: 0.001, dampingRatio: 1))
        XCTAssertEqual(try timing(["curve": "interactiveSpring", "speed": 1e300]).curve, .spring(response: 0.001, dampingRatio: 0.85))
    }

    func testBezierValues() {
        func value(_ points: (Double, Double, Double, Double), _ x: Double) -> Double {
            AnimationTiming.bezierValue(x1: points.0, y1: points.1, x2: points.2, y2: points.3, at: x)
        }
        XCTAssertEqual(value((0, 0, 1, 1), 0.3), 0.3, accuracy: 1e-6)
        XCTAssertEqual(value((0.42, 0, 0.58, 1), 0.5), 0.5, accuracy: 1e-6)
        // CSS's ease-in, the same curve, is 0.3153 half way.
        XCTAssertEqual(value((0.42, 0, 1, 1), 0.5), 0.3153, accuracy: 1e-3)
        XCTAssertEqual(value((0, 0, 0.58, 1), 0.5), 1 - 0.3153, accuracy: 1e-3)
        XCTAssertEqual(value((0.42, 0, 0.58, 1), 0), 0)
        XCTAssertEqual(value((0.42, 0, 0.58, 1), 1), 1)
        XCTAssertEqual(value((0.42, 0, 0.58, 1), -1), 0)
        XCTAssertEqual(value((0.42, 0, 0.58, 1), 2), 1)
    }

    func testTheCSSFormOfATiming() throws {
        XCTAssertEqual(try timing(["curve": "easeOut", "duration": 0.2, "delay": 0.1]).cssDeclarations(["color"]), [
            "transition-property: color;",
            "transition-duration: 200ms;",
            "transition-timing-function: cubic-bezier(0, 0, 0.58, 1);",
            "transition-delay: 100ms;",
        ])
        // A spring is the Bezier closest to it over its settling time (SwiftUI's smooth: 0.8 s).
        XCTAssertEqual(try timing("smooth").cssDeclarations(["color", "background-color"]), [
            "transition-property: color, background-color;",
            "transition-duration: 800ms;",
            "transition-timing-function: cubic-bezier(0.3, 0.75, 0.25, 1.145);",
            "transition-delay: 0ms;",
        ])
    }

    func testTheTriggerIsTheWatchedValueOrEveryMutation() throws {
        let every = try XCTUnwrap(ModifierParsing.animation("linear"))
        XCTAssertEqual(every.trigger(mutationToken: 7, properties: ["opacity": 0.5], states: [:], value: nil), AnyHashable(7))
        let watched = try XCTUnwrap(ModifierParsing.animation(["curve": "linear", "value": "opacity"]))
        XCTAssertEqual(watched.trigger(mutationToken: 7, properties: ["opacity": 0.5], states: [:], value: nil), AnyHashable(0.5))
        let state = try XCTUnwrap(ModifierParsing.animation(["curve": "linear", "value": "expanded"]))
        XCTAssertEqual(state.trigger(mutationToken: 7, properties: [:], states: ["expanded": true], value: nil), AnyHashable(true))
        let value = try XCTUnwrap(ModifierParsing.animation(["curve": "linear", "value": "value"]))
        XCTAssertEqual(value.trigger(mutationToken: 7, properties: [:], states: [:], value: "on"), AnyHashable("on"))
        let missing = try XCTUnwrap(ModifierParsing.animation(["curve": "linear", "value": "nothing"]))
        XCTAssertEqual(missing.trigger(mutationToken: 7, properties: [:], states: [:], value: nil), AnyHashable(0))
    }

    // MARK: In a window

    /// A test Rectangle 40 x 20 with these extra properties (JSON members), in a window on screen.
    private func show(_ modifiers: String) throws -> RenderNode {
        let json = ##"{"type": "Rectangle", "id": 1, "properties": {"w": 40, "h": 20, "## + modifiers + "}}"
        return try showDocument(json)
    }

    private func showDocument(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
        let window = AdwaitaWindow(windowModel: model)
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let gtkWindow = gtk_window_new()!
        shownWindows.append(gtkWindow)
        gtk_window_set_child(typed(gtkWindow), node.outerWidget)
        gtk_window_present(typed(gtkWindow))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.outerWidget) != 0 }))
        AdwaitaTestHost.drainMainLoop()
        return node
    }

    private func set(_ property: String, _ value: Any) {
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: property, value: value)
        AdwaitaTestHost.drainMainLoop()
    }

    /// Runs the main loop for `seconds`.
    private func wait(_ seconds: Double) {
        let end = g_get_monotonic_time() + Int(seconds * 1_000_000)
        _ = AdwaitaTestHost.runMainLoop(until: { g_get_monotonic_time() >= end }, timeoutMilliseconds: Int(seconds * 1000) + 1000)
    }

    private func animator(_ box: WidgetPointer) -> BoxAnimator {
        BoxAnimation.animator(of: box)
    }

    func testTheFirstSyncDrawsAtOnce() throws {
        let node = try show(#""opacity": 0.5, "offset": {"x": 10, "y": 0}, "animation": "linear""#)
        XCTAssertFalse(animator(node.outerWidget).isAnimating)
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0.5, accuracy: 1.0 / 255)
        XCTAssertEqual(attached(on: node.outerWidget, key: boxLayoutKey)?.offset.x, 10)
    }

    func testAHostChangeAnimatesOpacityToTheNewValue() throws {
        let node = try show(#""opacity": 1, "animation": {"curve": "linear", "duration": 0.6}"#)
        set("opacity", 0.2)
        XCTAssertTrue(animator(node.outerWidget).isAnimating)
        XCTAssertGreaterThan(gtk_widget_get_opacity(node.outerWidget), 0.9, "it starts where it was")
        wait(0.3)
        let midway = gtk_widget_get_opacity(node.outerWidget)
        XCTAssertGreaterThan(midway, 0.25)
        XCTAssertLessThan(midway, 0.95)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !self.animator(node.outerWidget).isAnimating }))
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0.2, accuracy: 1.0 / 255)
    }

    func testAVeryLongAnimationStarts() throws {
        // 10 million seconds is more milliseconds than libadwaita's duration holds.
        let node = try show(#""opacity": 1, "animation": {"curve": "linear", "duration": 10000000}"#)
        set("opacity", 0.2)
        XCTAssertTrue(animator(node.outerWidget).isAnimating)
    }

    func testWithoutAnAnimationAChangeIsAtOnce() throws {
        let node = try show(#""opacity": 1"#)
        set("opacity", 0.2)
        XCTAssertFalse(animator(node.outerWidget).isAnimating)
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0.2, accuracy: 1.0 / 255)
    }

    func testAWatchedValueAnimatesOnlyItsOwnChanges() throws {
        let node = try show(#""opacity": 1, "offset": {"x": 0, "y": 0}, "animation": {"curve": "linear", "duration": 0.5, "value": "offset"}"#)
        set("opacity", 0.2)
        XCTAssertFalse(animator(node.outerWidget).isAnimating, "opacity is not the watched property")
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0.2, accuracy: 1.0 / 255)
        set("offset", ["x": 30, "y": 0])
        XCTAssertTrue(animator(node.outerWidget).isAnimating)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !self.animator(node.outerWidget).isAnimating }))
        XCTAssertEqual(attached(on: node.outerWidget, key: boxLayoutKey)?.offset.x, 30)
    }

    func testHiddenChangesAtOnce() throws {
        let node = try show(#""opacity": 1, "animation": "linear""#)
        set("hidden", true)
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0)
        XCTAssertEqual(gtk_widget_get_can_target(node.outerWidget), 0)
    }

    func testANewTargetStartsFromWhatIsShown() throws {
        let node = try show(#""opacity": 1, "animation": {"curve": "linear", "duration": 0.8}"#)
        set("opacity", 0)
        wait(0.4)
        let shown = gtk_widget_get_opacity(node.outerWidget)
        set("opacity", 1)
        // On its way back from about half, not from 0 or 1.
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), shown, accuracy: 0.1)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !self.animator(node.outerWidget).isAnimating }))
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 1, accuracy: 1.0 / 255)
    }

    func testABouncySpringOvershootsAndSettles() throws {
        let node = try show(#""scaleEffect": 1, "animation": "bouncy""#)
        set("scaleEffect", 2)
        var largest = 1.0
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: {
            largest = max(largest, attached(on: node.outerWidget, key: boxLayoutKey)?.scale.x ?? 0)
            return !self.animator(node.outerWidget).isAnimating
        }, timeoutMilliseconds: 3000))
        // A damping ratio of 0.7 passes its target by about 4.6%.
        XCTAssertGreaterThan(largest, 2.02)
        XCTAssertEqual(attached(on: node.outerWidget, key: boxLayoutKey)?.scale.x, 2)
    }

    func testAShadowAnimatesBetweenTwoShadows() throws {
        let node = try show(#""shadow": {"radius": 2}, "animation": {"curve": "linear", "duration": 0.6}"#)
        set("shadow", ["radius": 10])
        wait(0.3)
        let radius = try XCTUnwrap(attached(on: node.outerWidget, key: boxShadowKey)?.value?.radius)
        XCTAssertGreaterThan(radius, 4)
        XCTAssertLessThan(radius, 20)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !self.animator(node.outerWidget).isAnimating }))
        XCTAssertEqual(attached(on: node.outerWidget, key: boxShadowKey)?.value?.radius, 20)
    }

    /// The color at the center of the content group as drawn now.
    private func centerColor(_ node: RenderNode) throws -> [UInt8] {
        let content = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        let width = gtk_widget_get_width(content)
        let height = gtk_widget_get_height(content)
        let paintable = gtk_widget_paintable_new(content)!
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        let snapshot = gtk_snapshot_new()!
        gdk_paintable_snapshot(paintable, snapshot, Double(width), Double(height))
        let drawn = try XCTUnwrap(gtk_snapshot_free_to_node(snapshot))
        defer { gsk_render_node_unref(drawn) }
        let pixels = try XCTUnwrap(AdwaitaTestHost.pixels(of: drawn, width: width, height: height))
        let index = (Int(height / 2) * Int(width) + Int(width / 2)) * 4
        return Array(pixels[index..<index + 4])
    }

    func testAnAnimatedBackgroundFadesThroughACSSTransition() throws {
        let node = try show(##""background": "#FF0000", "animation": {"curve": "linear", "duration": 0.8}"##)
        XCTAssertEqual(try centerColor(node), [255, 0, 0, 255])
        set("background", "#0000FF")
        wait(0.4)
        let midway = try centerColor(node)
        XCTAssertGreaterThan(midway[0], 40, "still partly red: \(midway)")
        XCTAssertGreaterThan(midway[2], 40, "already partly blue: \(midway)")
        wait(0.6)
        XCTAssertEqual(try centerColor(node), [0, 0, 255, 255])
    }

    func testAChangeThatDoesNotAnimateDisarmsTheTransition() throws {
        let node = try show(##""background": "#FF0000", "opacity": 1, "animation": {"curve": "linear", "duration": 0.8, "value": "opacity"}"##)
        set("background", "#0000FF")
        // A frame later: a widget's drawing is the one its window drew last.
        wait(0.1)
        XCTAssertEqual(try centerColor(node), [0, 0, 255, 255], "background is not the watched property")
    }

    func testAGroupAnimatesEachChild() throws {
        let node = try showDocument(##"""
        {"type": "Group", "id": 1, "properties": {"opacity": 1, "animation": {"curve": "linear", "duration": 0.6}}, "children": [
            {"type": "Rectangle", "id": 2, "properties": {"w": 40, "h": 20}},
            {"type": "Rectangle", "id": 3, "properties": {"w": 40, "h": 20}}]}
        """##)
        let boxes = try [2, 3].map { id -> WidgetPointer in
            // The child's box sits in the content group of the Group's child box.
            try XCTUnwrap(gtk_widget_get_parent(try XCTUnwrap(gtk_widget_get_parent(try XCTUnwrap(node.childNodes[id]).outerWidget))))
        }
        set("opacity", 0.3)
        for box in boxes {
            XCTAssertTrue(animator(box).isAnimating)
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { boxes.allSatisfy { !self.animator($0).isAnimating } }))
        for box in boxes {
            XCTAssertEqual(gtk_widget_get_opacity(box), 0.3, accuracy: 1.0 / 255)
        }
    }
}
