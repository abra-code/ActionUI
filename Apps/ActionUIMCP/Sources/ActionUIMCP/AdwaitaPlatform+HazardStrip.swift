// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AdwaitaPlatform+HazardStrip.swift - the yellow and black mark under the header bar of every
// actionui-mcp window on Linux, as on macOS (AppKitPlatform+HazardStrip.swift): on `show` windows a
// bar holding where the content came from, when it was shown and Save (LinuxShowFooter), on the
// others a thin striped line. It is one of the window's own bars
// (AdwaitaApplication.WindowOptions.topBar), outside the widgets that show the ActionUI JSON, so
// nothing the agent writes can remove or restyle it. Who asked leads the window's title (windowTitle).

#if os(Linux)
import FoundationEssentials
import CAdwaita

/// The mark's drawing: a yellow band, bright at the top and darker at the bottom like a bent
/// plastic tape, with black notches along its top edge that lean like a backslash; as a line,
/// black stripes across its whole height, as far apart as the strip's notches. The sizes and
/// colors are macOS's.
enum LinuxWindowMark {
    static let stripHeight: Int32 = 12
    static let lineHeight: Int32 = 3
    /// A `show` window's: the notches, then the row of LinuxShowFooter under them.
    static let barHeight: Int32 = 26
    // The notches in proportion to the strip's height; the line's stripes have the same width and spacing.
    private static let notchDepth = Double(stripHeight) * 0.4
    private static let notchWidth = Double(stripHeight) * 0.8
    private static let notchSpacing = Double(stripHeight) * 2.1
    // The yellow, bright at the top and darker at the bottom, in sRGB.
    static let bright = (red: 252.0 / 255, green: 240.0 / 255, blue: 97.0 / 255)
    static let dark = (red: 216.0 / 255, green: 185.0 / 255, blue: 74.0 / 255)

    /// A new mark widget, drawn for its current width so it follows the window as it resizes. A
    /// strip with a `show` window's `footer` is the taller bar, with the footer's row over its
    /// lower part, under the notches.
    @MainActor
    static func widget(_ mark: WindowMark, footer: ShowFooter?, windowID: String) -> UnsafeMutableRawPointer {
        let area = gtk_drawing_area_new()!
        let drawingArea = UnsafeMutableRawPointer(area).assumingMemoryBound(to: GtkDrawingArea.self)
        let height = mark == .line ? lineHeight : footer == nil ? stripHeight : barHeight
        gtk_drawing_area_set_content_height(drawingArea, height)
        gtk_widget_set_hexpand(area, 1)
        gtk_drawing_area_set_draw_func(drawingArea, mark == .strip ? drawStrip : drawLine, nil, nil)
        guard mark == .strip, let footer else { return UnsafeMutableRawPointer(area) }
        let overlay = gtk_overlay_new()!
        let overlayView = OpaquePointer(overlay)
        gtk_overlay_set_child(overlayView, area)
        let row = LinuxShowFooter.widget(footer, windowID: windowID).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_valign(row, GTK_ALIGN_END)
        gtk_widget_set_size_request(row, -1, barHeight - Int32(notchDepth.rounded()))
        gtk_overlay_add_overlay(overlayView, row)
        // Measured with the bar, as the bottom bar was: the window cannot get narrower than the
        // row, which GtkOverlay would otherwise give its minimum width past the window's edge.
        gtk_overlay_set_measure_overlay(overlayView, row, 1)
        return UnsafeMutableRawPointer(overlay)
    }

    private static let drawStrip: GtkDrawingAreaDrawFunc = { _, cairo, width, height, _ in
        guard let cairo else { return }
        LinuxWindowMark.draw(cairo, width: Double(width), height: Double(height), depth: LinuxWindowMark.notchDepth)
    }

    private static let drawLine: GtkDrawingAreaDrawFunc = { _, cairo, width, height, _ in
        guard let cairo else { return }
        // 45 degrees: as far across as down, across the line's whole height.
        LinuxWindowMark.draw(cairo, width: Double(width), height: Double(height), depth: Double(height))
    }

    /// The gradient band, then the notches `depth` deep from the top edge.
    private static func draw(_ cairo: OpaquePointer, width: Double, height: Double, depth: Double) {
        fillGradient(cairo, width: width, height: height)
        cairo_set_source_rgb(cairo, 0.03, 0.03, 0.035)
        var x = -depth - notchSpacing
        while x < width {
            cairo_move_to(cairo, x, 0)
            cairo_line_to(cairo, x + notchWidth, 0)
            cairo_line_to(cairo, x + depth + notchWidth, depth)
            cairo_line_to(cairo, x + depth, depth)
            cairo_close_path(cairo)
            x += notchSpacing
        }
        cairo_fill(cairo)
    }

    /// The yellow, bright at the top and darker at the bottom, over the whole of `width` x `height`.
    static func fillGradient(_ cairo: OpaquePointer, width: Double, height: Double) {
        guard let gradient = cairo_pattern_create_linear(0, 0, 0, height) else { return }
        cairo_pattern_add_color_stop_rgb(gradient, 0, bright.red, bright.green, bright.blue)
        cairo_pattern_add_color_stop_rgb(gradient, 1, dark.red, dark.green, dark.blue)
        cairo_set_source(cairo, gradient)
        cairo_rectangle(cairo, 0, 0, width, height)
        cairo_fill(cairo)
        cairo_pattern_destroy(gradient)
    }
}
#endif
