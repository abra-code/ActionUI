// Tests/Styling/StyleSheetTests.swift
/*
 Tests for StyleSheet and the Color renderer: identical declarations share one generated class, a
 slot's classes are replaced rather than added to, a class two slots share stays, named classes;
 every value GTK parses and every CSS variable resolves; caption2 is smaller than caption; a Color
 fills its widget's background, expands, is 10 x 10 naturally, and takes a runtime value.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class StyleSheetTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "style-sheet-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func ownedWidget() -> WidgetPointer {
        let widget = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        g_object_ref_sink(UnsafeMutableRawPointer(widget))
        return widget
    }

    /// The widget's CSS classes.
    private func classes(_ widget: WidgetPointer) -> Set<String> {
        guard let list = gtk_widget_get_css_classes(widget) else { return [] }
        defer { g_strfreev(list) }
        var result: Set<String> = []
        var index = 0
        while let entry = list[index] {
            result.insert(String(cString: entry))
            index += 1
        }
        return result
    }

    func testIdenticalDeclarationsShareAClass() {
        let first = StyleSheet.shared.className(for: ["color: rgba(1, 2, 3, 1);"])
        let second = StyleSheet.shared.className(for: ["color: rgba(1, 2, 3, 1);"])
        let other = StyleSheet.shared.className(for: ["color: rgba(3, 2, 1, 1);"])
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
        XCTAssertNil(StyleSheet.shared.className(for: []))
        XCTAssertTrue(StyleSheet.shared.css.contains(".\(first!) { color: rgba(1, 2, 3, 1); }"))
    }

    func testARuleNoWidgetUsesIsDropped() {
        let widget = ownedWidget()
        let before = StyleSheet.shared.ruleCount
        StyleSheet.shared.apply(["border-top-width: 7px;"], to: widget, slot: "lifetime")
        XCTAssertEqual(StyleSheet.shared.ruleCount, before + 1)
        StyleSheet.shared.apply(["border-top-width: 8px;"], to: widget, slot: "lifetime")
        XCTAssertEqual(StyleSheet.shared.ruleCount, before + 1, "the replaced look's rule is gone")
        XCTAssertFalse(StyleSheet.shared.css.contains("border-top-width: 7px;"))
        g_object_unref(UnsafeMutableRawPointer(widget))
        XCTAssertEqual(StyleSheet.shared.ruleCount, before, "finalizing the widget released its rule")
        XCTAssertFalse(StyleSheet.shared.css.contains("border-top-width: 8px;"))
    }

    func testARuleTwoWidgetsUseStaysUntilBothLetGo() {
        let first = ownedWidget()
        let second = ownedWidget()
        let before = StyleSheet.shared.ruleCount
        StyleSheet.shared.apply(["border-left-width: 3px;"], to: first, slot: "shared")
        StyleSheet.shared.apply(["border-left-width: 3px;"], to: second, slot: "shared")
        g_object_unref(UnsafeMutableRawPointer(first))
        XCTAssertTrue(StyleSheet.shared.css.contains("border-left-width: 3px;"))
        g_object_unref(UnsafeMutableRawPointer(second))
        XCTAssertEqual(StyleSheet.shared.ruleCount, before)
    }

    func testDraggingThroughManyColorsKeepsTheSheetSmall() {
        let widget = ownedWidget()
        defer { g_object_unref(UnsafeMutableRawPointer(widget)) }
        let before = StyleSheet.shared.ruleCount
        for step in 0..<1000 {
            let color = ColorSpec.rgba(red: Double(step) / 1000, green: 0.5, blue: 0.25, alpha: 1)
            StyleSheet.shared.apply(["background-color: \(ColorCSS.value(color));"], to: widget, slot: "drag")
        }
        XCTAssertEqual(StyleSheet.shared.ruleCount, before + 1, "only the current color's rule is kept")
    }

    func testApplyingASlotReplacesItsClasses() {
        let widget = ownedWidget()
        defer { g_object_unref(UnsafeMutableRawPointer(widget)) }
        let red = StyleSheet.shared.className(for: ["background-color: rgba(255, 0, 0, 1);"])!
        let blue = StyleSheet.shared.className(for: ["background-color: rgba(0, 0, 255, 1);"])!
        StyleSheet.shared.apply(["background-color: rgba(255, 0, 0, 1);"], named: ["card"], to: widget, slot: "background")
        XCTAssertTrue(classes(widget).isSuperset(of: [red, "card"]))
        StyleSheet.shared.apply(["background-color: rgba(0, 0, 255, 1);"], to: widget, slot: "background")
        XCTAssertTrue(classes(widget).contains(blue))
        XCTAssertFalse(classes(widget).contains(red))
        XCTAssertFalse(classes(widget).contains("card"))
        StyleSheet.shared.apply([], to: widget, slot: "background")
        XCTAssertFalse(classes(widget).contains(blue))
    }

    func testAClassTwoSlotsShareStays() {
        let widget = ownedWidget()
        defer { g_object_unref(UnsafeMutableRawPointer(widget)) }
        StyleSheet.shared.apply(["opacity: 0.5;"], to: widget, slot: "one")
        StyleSheet.shared.apply(["opacity: 0.5;"], to: widget, slot: "two")
        let shared = StyleSheet.shared.className(for: ["opacity: 0.5;"])!
        StyleSheet.shared.apply([], to: widget, slot: "one")
        XCTAssertTrue(classes(widget).contains(shared), "slot two still has it")
    }

    func testGTKParsesEveryColorStyleAndFontWeWrite() {
        var rules: [String] = []
        var index = 0
        func rule(_ declarations: [String]) {
            index += 1
            rules.append(".parse-check-\(index) { \(declarations.joined(separator: " ")) }")
        }
        for name in ColorName.allCases {
            rule(["color: \(ColorCSS.value(.named(name)));", "background-color: \(ColorCSS.value(.withOpacity(.named(name), 0.4)));"])
        }
        for name in ShapeStyleName.allCases {
            rule(["background-color: \(ColorCSS.value(name));"])
        }
        rule(["color: \(ColorCSS.value(.rgba(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)));"])
        for style in FontTextStyle.allCases {
            rule(FontCSS.style(.textStyle(style)).declarations + ["color: red;"])
        }
        for weight in FontWeight.allCases {
            rule(FontCSS.style(.sized(name: #"Odd "Name" \ here"#, size: 14, weight: weight, design: .default)).declarations)
        }
        for design in FontDesign.allCases {
            rule(FontCSS.style(.sized(name: nil, size: 11, weight: nil, design: design)).declarations + ["color: red;"])
        }

        let provider = gtk_css_provider_new()!
        defer { g_object_unref(UnsafeMutableRawPointer(provider)) }
        let errors = CallCounter()
        // "parsing-error" passes (provider, section, error, user data).
        let onError: @convention(c) (gpointer?, gpointer?, gpointer?, gpointer?) -> Void = { _, _, _, data in
            guard let data else { return }
            MainActor.assumeIsolated { Unmanaged<CallCounter>.fromOpaque(data).takeUnretainedValue().count += 1 }
        }
        let handler = g_signal_connect_data(UnsafeMutableRawPointer(provider), "parsing-error",
                                            unsafeBitCast(onError, to: GCallback.self),
                                            Unmanaged.passUnretained(errors).toOpaque(), nil, GConnectFlags(0))
        defer { g_signal_handler_disconnect(UnsafeMutableRawPointer(provider), handler) }
        gtk_css_provider_load_from_string(provider, rules.joined(separator: "\n"))
        XCTAssertEqual(errors.count, 0, "GTK refused some of:\n\(rules.joined(separator: "\n"))")
    }

    /// A window holding `widgets` in a box, so GTK computes their style; destroyed by the caller.
    private func windowHolding(_ widgets: [WidgetPointer]) -> (window: WidgetPointer, box: WidgetPointer) {
        let window = gtk_window_new()!
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        for widget in widgets {
            gtk_box_append(typed(box) as UnsafeMutablePointer<GtkBox>, widget)
        }
        gtk_window_set_child(typed(window), box)
        return (window, box)
    }

    /// A GTK parse does not check var(): an unknown variable parses, and the property then falls
    /// back to its inherited value. Each variable we write must resolve to something other than
    /// the parent's color.
    func testEveryCSSVariableWeWriteExists() {
        var values = ColorName.allCases.map { ColorCSS.value(.named($0)) }
        values += ShapeStyleName.allCases.map { ColorCSS.value($0) }
        values = values.filter { $0.contains("var(") }
        XCTAssertFalse(values.isEmpty)
        let labels = values.map { _ in gtk_label_new("x")! }
        let (window, box) = windowHolding(labels)
        defer { gtk_window_destroy(typed(window)) }
        StyleSheet.shared.apply(["color: rgba(1, 2, 3, 1);"], to: box, slot: "color")
        let sentinel = GdkRGBA(red: 1 / 255, green: 2 / 255, blue: 3 / 255, alpha: 1)
        var parent = GdkRGBA()
        gtk_widget_get_color(box, &parent)
        XCTAssertEqual(parent.red, sentinel.red, accuracy: 0.001, "the sentinel applies")
        for (label, value) in zip(labels, values) {
            StyleSheet.shared.apply(["color: \(value);"], to: label, slot: "color")
            var color = GdkRGBA()
            gtk_widget_get_color(label, &color)
            let inherited = abs(color.red - sentinel.red) < 0.001 && abs(color.green - sentinel.green) < 0.001
                && abs(color.blue - sentinel.blue) < 0.001 && abs(color.alpha - sentinel.alpha) < 0.001
            XCTAssertFalse(inherited, "\(value) does not resolve")
        }
        // The check itself: an unknown variable falls back to the parent's color.
        let unknown = gtk_label_new("x")!
        gtk_box_append(typed(box) as UnsafeMutablePointer<GtkBox>, unknown)
        StyleSheet.shared.apply(["color: var(--actionui-no-such-color);"], to: unknown, slot: "color")
        var fallback = GdkRGBA()
        gtk_widget_get_color(unknown, &fallback)
        XCTAssertEqual(fallback.blue, sentinel.blue, accuracy: 0.001)
    }

    /// caption2 is smaller than caption, as on Apple, not 0.85 of the parent's size.
    func testCaption2IsSmallerThanCaption() {
        let caption = gtk_label_new("caption")!
        let caption2 = gtk_label_new("caption2")!
        let (window, _) = windowHolding([caption, caption2])
        defer { gtk_window_destroy(typed(window)) }
        for (label, style) in [(caption, FontTextStyle.caption), (caption2, .caption2)] {
            let font = FontCSS.style(.textStyle(style))
            StyleSheet.shared.apply(font.declarations, named: font.classes, to: label, slot: "font")
        }
        func size(_ label: WidgetPointer) -> Int32 {
            pango_font_description_get_size(pango_context_get_font_description(gtk_widget_get_pango_context(label)))
        }
        XCTAssertGreaterThan(size(caption), 0)
        XCTAssertLessThan(size(caption2), size(caption))
        XCTAssertEqual(Double(size(caption2)) / Double(size(caption)), 0.85, accuracy: 0.02)
    }

    func testAColorFillsItsBackgroundAndIsGreedy() throws {
        _ = try ActionUIModel.shared.loadDescription(from: Data(##"{"type": "Color", "id": 1, "properties": {"color": "#FF0000"}}"##.utf8),
                                                     format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let node = try XCTUnwrap(window.root)
        let red = StyleSheet.shared.className(for: ["background-color: rgba(255, 0, 0, 1);"])!
        XCTAssertTrue(classes(node.widget).contains(red))
        XCTAssertNotEqual(gtk_widget_compute_expand(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertNotEqual(gtk_widget_compute_expand(node.outerWidget, GTK_ORIENTATION_VERTICAL), 0)
        var minimum: Int32 = -1
        var natural: Int32 = -1
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual([minimum, natural], [0, 10], "SwiftUI's Color is 10 x 10 ideally")
        // The subclass's structs are GtkWidget's, as GLib sees them.
        var fill = GTypeQuery()
        var base = GTypeQuery()
        g_type_query(Color.fillType(), &fill)
        g_type_query(gtk_widget_get_type(), &base)
        XCTAssertEqual(fill.class_size, base.class_size)
        XCTAssertEqual(fill.instance_size, base.instance_size)

        // A runtime value overrides the color property.
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: ColorSpec.named(.blue))
        AdwaitaTestHost.drainMainLoop()
        let blue = StyleSheet.shared.className(for: ["background-color: var(--blue-3);"])!
        XCTAssertTrue(classes(node.widget).contains(blue))
        XCTAssertFalse(classes(node.widget).contains(red))
    }
}
