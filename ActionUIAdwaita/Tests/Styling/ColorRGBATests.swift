// Tests/Styling/ColorRGBATests.swift
/*
 Tests for ColorRGBA: every named color is the one GTK resolves from ColorCSS's value for it, in a
 shown window (where libadwaita's CSS variables are defined), so the two tables cannot drift
 apart; rgba components and opacities carry over.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ColorRGBATests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    func testNamedColorsAreWhatTheCSSResolves() throws {
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        let parent = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        let probe = gtk_label_new("x")!
        gtk_box_append(typed(parent), probe)
        gtk_window_set_child(typed(window), parent)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(probe) != 0 }))
        for name in ColorName.allCases {
            StyleSheet.shared.apply(["color: \(ColorCSS.value(name));"], to: probe, slot: "probe")
            AdwaitaTestHost.drainMainLoop()
            var css = GdkRGBA()
            gtk_widget_get_color(probe, &css)
            // secondary is the text color around it at an opacity: the probe's parent's.
            let drawn = ColorRGBA.resolve(name, for: parent)
            let close = abs(css.red - drawn.red) < 0.01 && abs(css.green - drawn.green) < 0.01
                && abs(css.blue - drawn.blue) < 0.01 && abs(css.alpha - drawn.alpha) < 0.01
            XCTAssertTrue(close, "\(name): CSS \(css), drawn \(drawn)")
        }
    }

    func testComponentsAndOpacitiesCarryOver() throws {
        let widget = gtk_label_new("x")!
        g_object_ref_sink(UnsafeMutableRawPointer(widget))
        defer { g_object_unref(UnsafeMutableRawPointer(widget)) }
        let color = ColorRGBA.resolve(.withOpacity(.rgba(red: 1, green: 0.5, blue: 0, alpha: 0.8), 0.5), for: widget)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0.5)
        XCTAssertEqual(color.blue, 0)
        XCTAssertEqual(color.alpha, 0.4, accuracy: 0.0001)
        XCTAssertEqual(ColorRGBA.resolve(.rgba(red: 2, green: -1, blue: .nan, alpha: 1), for: widget).red, 1, "clamped")
    }
}
