// Sources/Drawing/ChartAnnotations.swift
/*
 Where a mark's annotation goes, as Swift Charts places one (measured on macOS 27, ImageRenderer at
 2x, a 20 x 10 view beside bars, points and rules):

 - The mark's frame: a bar's or rectangle's rectangle; a point's symbol, 1.5 points larger on each
   side (a point's annotation sits about 5.5 points off its symbol, 4 off a bar); a rule's line,
   without its width; one point of a line or area, where it is plotted; a sector's bounding box,
   and for overlay its centroid (a quarter sector of radius 100: 60 out along its middle).
 - automatic is top for every mark: bars of positive and negative values, vertical and horizontal
   (a negative bar's view is above the bar, over its zero end), points, lines, rules, sectors (a
   sector at the top of a pie puts it above the chart, where it is cut off).
 - spacing, 4 points unless given, lies between the frame and the view: top, bottom, leading and
   trailing put the view outside that edge, centered across it unless an alignment along the edge
   moves it to one end (top, alignment leading: the view's leading edge at the frame's); the corner
   positions are outside both edges; overlay centers it in the frame, an alignment moving it to an
   edge, spacing in from it.
 - What does not fit: without an overflow resolution, or with "disabled", the view stays where it
   goes, drawn past the chart's edges over what is around it (checked in a window on macOS 27; the
   renders above only showed the chart's own bounds); "fit" moves it into the chart ("plot": into
   the plot). padScale is taken as fit (Linux does not widen the scale).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

/// One annotation of a drawn mark: which instance and which of its annotations, the frame it is
/// placed by and the position "automatic" stands for there.
struct ChartAnnotationFrame: Equatable {
    var instance: Int
    var ordinal: Int
    var frame: ChartRect
    /// Where overlay centers the view, when not the frame's center: a sector's centroid.
    var center: ChartPoint?
}

enum ChartAnnotationPlacement {
    static let defaultSpacing = 4.0
    /// How much larger than its symbol a point's frame is, on each side.
    static let pointMargin = 1.5

    /// The rectangle a view of `size` takes as `annotation` of a mark framed by `frame`, in a chart
    /// `chart` with its plot `plot`.
    static func place(_ annotation: ChartAnnotationSpec, frame: ChartRect, center: ChartPoint? = nil, size: ChartSize,
                      plot: ChartRect, chart: ChartRect) -> ChartRect {
        let spacing = annotation.spacing.flatMap { $0.isFinite ? $0 : nil } ?? defaultSpacing
        let position = annotation.position == .automatic ? ChartPosition.top : annotation.position
        let alignment = annotation.alignment
        let width = size.width, height = size.height
        func alongX() -> Double {
            if isLeading(alignment) { return frame.x }
            if isTrailing(alignment) { return frame.x + frame.width - width }
            return frame.x + (frame.width - width) / 2
        }
        func alongY() -> Double {
            if isTop(alignment) { return frame.y }
            if isBottom(alignment) { return frame.y + frame.height - height }
            return frame.y + (frame.height - height) / 2
        }
        let above = frame.y - spacing - height, below = frame.y + frame.height + spacing
        let before = frame.x - spacing - width, after = frame.x + frame.width + spacing
        var x: Double, y: Double
        switch position {
        case .top: (x, y) = (alongX(), above)
        case .bottom: (x, y) = (alongX(), below)
        case .leading: (x, y) = (before, alongY())
        case .trailing: (x, y) = (after, alongY())
        case .topLeading: (x, y) = (before, above)
        case .topTrailing: (x, y) = (after, above)
        case .bottomLeading: (x, y) = (before, below)
        case .bottomTrailing: (x, y) = (after, below)
        case .overlay, .automatic:
            x = (center?.x ?? frame.x + frame.width / 2) - width / 2
            y = (center?.y ?? frame.y + frame.height / 2) - height / 2
            if isLeading(alignment) { x = frame.x + spacing }
            if isTrailing(alignment) { x = frame.x + frame.width - spacing - width }
            if isTop(alignment) { y = frame.y + spacing }
            if isBottom(alignment) { y = frame.y + frame.height - spacing - height }
        }
        var placed = ChartRect(x: x, y: y, width: width, height: height)
        if let overflow = annotation.overflow {
            placed.x = fitted(placed.x, width, overflow.x, plot: (plot.x, plot.x + plot.width), chart: (chart.x, chart.x + chart.width))
            placed.y = fitted(placed.y, height, overflow.y, plot: (plot.y, plot.y + plot.height), chart: (chart.y, chart.y + chart.height))
        }
        return placed
    }

    /// The box around a sector: its arc's ends, the points where it crosses an axis, and the
    /// center or its inner arc's ends.
    static func bounds(of sector: ChartSector) -> ChartRect {
        func point(_ angle: Double, _ radius: Double) -> ChartPoint {
            ChartPoint(x: sector.center.x + radius * sin(angle), y: sector.center.y - radius * cos(angle))
        }
        var points = [point(sector.start, sector.outer), point(sector.end, sector.outer)]
        points += sector.inner > 0 ? [point(sector.start, sector.inner), point(sector.end, sector.inner)] : [sector.center]
        var quarter = (sector.start / (.pi / 2)).rounded(.up) * (.pi / 2)
        while quarter < sector.end {
            points.append(point(quarter, sector.outer))
            quarter += .pi / 2
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? sector.center.x, minY = ys.min() ?? sector.center.y
        return ChartRect(x: minX, y: minY, width: (xs.max() ?? minX) - minX, height: (ys.max() ?? minY) - minY)
    }

    /// A sector's centroid: 2/3 (R^3 - r^3) / (R^2 - r^2) sin(a/2) / (a/2) out along its middle, for
    /// an angle a between radii r and R.
    static func centroid(of sector: ChartSector) -> ChartPoint {
        let angle = sector.end - sector.start
        let middle = (sector.start + sector.end) / 2
        let outer = sector.outer, inner = sector.inner
        guard angle > 0, outer > inner else { return sector.center }
        let radial = 2.0 / 3 * (outer * outer * outer - inner * inner * inner) / (outer * outer - inner * inner)
        let distance = radial * sin(angle / 2) / (angle / 2)
        return ChartPoint(x: sector.center.x + distance * sin(middle), y: sector.center.y - distance * cos(middle))
    }

    private static func fitted(_ start: Double, _ length: Double, _ strategy: ChartOverflowResolution.Strategy,
                               plot: (Double, Double), chart: (Double, Double)) -> Double {
        let bounds: (Double, Double)
        switch strategy {
        case .automatic, .disabled: return start
        case .fit, .padScale, .fitTo(.chart), .fitTo(.automatic): bounds = chart
        case .fitTo(.plot): bounds = plot
        }
        // Larger than the room: its leading or top edge at the room's.
        guard length < bounds.1 - bounds.0 else { return bounds.0 }
        return min(max(start, bounds.0), bounds.1 - length)
    }

    private static func isLeading(_ alignment: ChartAlignment) -> Bool {
        alignment == .leading || alignment == .topLeading || alignment == .bottomLeading
    }

    private static func isTrailing(_ alignment: ChartAlignment) -> Bool {
        alignment == .trailing || alignment == .topTrailing || alignment == .bottomTrailing
    }

    private static func isTop(_ alignment: ChartAlignment) -> Bool {
        alignment == .top || alignment == .topLeading || alignment == .topTrailing
    }

    private static func isBottom(_ alignment: ChartAlignment) -> Bool {
        alignment == .bottom || alignment == .bottomLeading || alignment == .bottomTrailing
    }
}
