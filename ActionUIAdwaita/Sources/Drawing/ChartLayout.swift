// Sources/Drawing/ChartLayout.swift
/*
 Lays out a chart for a size: its marks, axes and gridlines as drawing primitives in points. No GTK
 here: text is measured and formatted through ChartTextMetrics, so a test checks the geometry as
 numbers, and Elements/Chart+Adwaita.swift only draws the primitives.

 The goal is a chart comparable to Swift Charts, not a copy (Documentation/Schemas/Chart.md lists the
 differences). Swift Charts' look, as drawn on macOS 27, is written down beside the code that follows
 it. This file works out the room around the plot and puts each part in place; the parts are in
 ChartLayout+Stacks, +Axes, +AxisMarks, +Legend, +PlotStyle, and for marks +Marks, +Position, +Bars,
 +Lines and +Sectors.

 An axis title sits outside the labels, 8 points off: an x title at the bottom and leading along
 the plot, a y title at the top and trailing along the whole chart, or leading on an axis with
 its labels there. On the leading or trailing side either is turned to run along the plot,
 centered unless aligned top or bottom. Two titles on one side do not stack, each is its own
 spacing off.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Text as the renderer measures and formats it.
struct ChartTextMetrics {
    var size: (String) -> ChartSize
    /// A number with this many decimals.
    var number: (Double, Int) -> String
    /// A number in an axis's own format.
    var formatted: (Double, NumberFormatSpec) -> String
    var date: (Date, _ skeleton: String) -> String
}

/// Where a laid-out chart's plot is and how its axes map values onto it, so a place in the chart
/// reads back as a value (a selection).
struct ChartGeometry {
    var plot = ChartRect(x: 0, y: 0, width: 0, height: 0)
    var x = ChartAxisScale()
    var y = ChartAxisScale()
    var hasSectors = false
}

struct ChartLayout {
    // Swift Charts' order for series, in ActionUI's named colors.
    static let seriesColors: [ColorSpec] = [.named(.blue), .named(.green), .named(.orange), .named(.purple), .named(.red), .named(.cyan), .named(.yellow)]
    static let gridInk = ChartInk.text(opacity: 0.14)
    static let labelInk = ChartInk.text(opacity: 0.6)
    static let defaultLine = ChartStroke(lineWidth: 2, lineCap: .round, lineJoin: .round)
    // A date label on x is wide; on y it needs only its height and some air.
    static let pointsPerDateTick = 80.0, pointsPerYDateTick = 20.0
    // From the plot's edge to the labels.
    static let labelGap = 4.0
    private static let titleGap = 8.0

    let spec: ChartSpec
    let marks: ChartResolvedMarks
    let styles: ChartStyleMap
    let metrics: ChartTextMetrics
    let width: Double
    let height: Double

    static func primitives(_ spec: ChartSpec, marks: ChartResolvedMarks, width: Double, height: Double, metrics: ChartTextMetrics) -> [ChartPrimitive] {
        laidOut(spec, marks: marks, width: width, height: height, metrics: metrics).primitives
    }

    /// The primitives, and where the plot and its scales ended up.
    static func laidOut(_ spec: ChartSpec, marks: ChartResolvedMarks, width: Double, height: Double,
                        metrics: ChartTextMetrics) -> (primitives: [ChartPrimitive], geometry: ChartGeometry) {
        ChartLayout(spec: spec, marks: marks, styles: ChartStyleMap(spec, marks), metrics: metrics, width: width, height: height).layout()
    }

    private func layout() -> (primitives: [ChartPrimitive], geometry: ChartGeometry) {
        let stacks = stacks()
        let extents = extents(stacks)
        let lineHeight = metrics.size("0").height
        let hasSectors = marks.instances.contains { $0.mark.kind == .SectorMark }

        // The y labels' width sets the plot's width, which sets the x ticks; the height is known
        // first. An x axis's kind and edges decide the room around the plot.
        let hasX = !hasSectors && !axis(extents.x, spec.x, length: 0).isEmpty
        let unplacedY = axis(extents.y, spec.y, length: 0)
        let hasY = !hasSectors && !unplacedY.isEmpty
        var yBands = false
        if case .bands = unplacedY.scale.kind { yBands = true }
        let xRows = hasX ? labelEdges(spec.x, isX: true) : []
        let rowHeight = lineHeight + Self.labelGap * 2
        // Labels of bands take no room, so they do not count as labels on the leading edge.
        let leadingLabels = !yBands && labelEdges(spec.y, isX: false) == [.leading]
        var legend = legend(lineHeight: lineHeight)
        let legendLeading = legend?.room(.leading) ?? 0, legendTrailing = legend?.room(.trailing) ?? 0
        let titles = [title(spec.x, isX: true, leadingLabels: false), title(spec.y, isX: false, leadingLabels: leadingLabels)].compactMap { $0 }
        // Two titles on an edge share it, and a spacing past the title's size takes no room back.
        func titleRoom(_ edge: ChartAxisMarkPosition) -> Double {
            titles.filter { $0.edge == edge }.map { max(0, lineHeight + $0.spacing) }.max() ?? 0
        }
        let yShown = hasY && !labelEdges(spec.y, isX: false).isEmpty
        let topTicks = hasX ? tickRoom(spec.x, isX: true, .top) : 0, bottomTicks = hasX ? tickRoom(spec.x, isX: true, .bottom) : 0
        let xLabelsTop = (xRows.contains(.top) ? rowHeight : 0) + topTicks
        let xLabelsBottom = (xRows.contains(.bottom) ? rowHeight : 0) + bottomTicks
        let top = max(xLabelsTop + titleRoom(.top) + (legend?.room(.top) ?? 0), yShown ? lineHeight / 2 : 0)
        let bottom = xLabelsBottom + titleRoom(.bottom) + (legend?.room(.bottom) ?? 0)
        let plotHeight = max(height - top - bottom, 1)
        var yAxis = axis(extents.y, spec.y, length: plotHeight, pointsPerTick: Self.pointsPerYDateTick)
        let yGroups = hasSectors ? [] : groups(spec.y, yAxis, isX: false)
        func room(_ edge: ChartAxisMarkPosition) -> Double {
            // Labels of bands sit in the plot and take none.
            let labeled = yBands ? [] : yGroups.filter { $0.edge == edge && $0.label != nil }
            let widest = labeled.flatMap(\.ticks).map { metrics.size($0.label).width }.max() ?? 0
            return (widest > 0 ? widest + Self.labelGap * 2 : 0) + (hasY ? tickRoom(spec.y, isX: false, edge, bands: yBands) : 0)
        }
        let yLabelsLeading = room(.leading), yLabelsTrailing = room(.trailing)
        let leading = yLabelsLeading + titleRoom(.leading) + legendLeading
        let trailing = yLabelsTrailing + titleRoom(.trailing) + legendTrailing
        let plotWidth = max(width - leading - trailing, 1)
        var xAxis = axis(extents.x, spec.x, length: plotWidth)
        let xGroups = hasSectors ? [] : groups(spec.x, xAxis, isX: true)

        let style = PlotStyle(spec.plotStyle)
        let frame = style.framed(ChartRect(x: leading, y: top, width: plotWidth, height: plotHeight))
        let plot = style.padded(frame)
        legend?.fit(overPlot: frame)
        place(&xAxis, spec.x, from: plot.x, to: plot.x + plot.width)
        // Numbers rise up the axis; bands and dates read from the top (measured on macOS 27).
        switch yAxis.scale.kind {
        case .bands, .dates:
            place(&yAxis, spec.y, from: plot.y, to: plot.y + plot.height)
        default:
            place(&yAxis, spec.y, from: plot.y + plot.height, to: plot.y)
        }

        var primitives: [ChartPrimitive] = []
        for group in yGroups { appendYGroup(group, yAxis.scale, plot, lineHeight: lineHeight, into: &primitives) }
        for group in xGroups { appendXGroup(group, xAxis.scale, plot, into: &primitives) }
        let outerTop = plot.y - xLabelsTop, outerBottom = plot.y + plot.height + xLabelsBottom
        let outerLeading = plot.x - yLabelsLeading, outerTrailing = plot.x + plot.width + yLabelsTrailing
        for title in titles {
            // An x title runs along the plot and a y title along the chart inside any legend, its
            // ends moved as far as a plot style moved the plot's (measured on macOS 27).
            let start = title.isX ? plot.x : plot.x - leading + legendLeading
            let end = title.isX ? plot.x + plot.width : width - legendTrailing + ((plot.x + plot.width) - (leading + plotWidth))
            let across = start + (end - start) * title.along
            // A turned title is placed by its center: its ends line up with the plot's.
            let along = plot.y + plot.height * title.along + metrics.size(title.text).width * (0.5 - title.along)
            switch title.edge {
            case .top:
                primitives.append(.text(title.text, position: ChartPoint(x: across, y: outerTop - title.spacing), alignment: ChartPoint(x: title.along, y: 1), ink: Self.labelInk))
            case .bottom:
                primitives.append(.text(title.text, position: ChartPoint(x: across, y: outerBottom + title.spacing), alignment: ChartPoint(x: title.along, y: 0), ink: Self.labelInk))
            case .leading:
                primitives.append(.turnedText(title.text, center: ChartPoint(x: outerLeading - title.spacing - lineHeight / 2, y: along), degrees: 90, ink: Self.labelInk))
            case .trailing:
                primitives.append(.turnedText(title.text, center: ChartPoint(x: outerTrailing + title.spacing + lineHeight / 2, y: along), degrees: 90, ink: Self.labelInk))
            case .automatic:
                break
            }
        }
        // A label's row is the room under the band's top line (measured on macOS 27: it follows the font).
        let bandLabelRow = yBands && !labelEdges(spec.y, isX: false).isEmpty ? lineHeight + Self.labelGap : 0
        let layer = style.layer(frame)
        if let layer {
            primitives.append(.beginPlot(layer))
            if let background = style.background {
                primitives.append(.roundedFill(frame, radius: layer.radius, ink: .color(background)))
            }
        }
        appendMarks(stacks, xAxis.scale, yAxis.scale, plot, bandLabelRow: bandLabelRow, into: &primitives)
        if let layer { primitives.append(.endPlot(layer)) }
        if let border = style.border {
            primitives.append(.border(frame, width: border.width, ink: border.ink))
        }
        let area = ChartRect(x: frame.x - leading, y: frame.y - top, width: leading + frame.width + trailing, height: top + frame.height + bottom)
        legend?.append(to: &primitives, area: area, plot: frame)
        return (primitives.filter(\.isDrawable), ChartGeometry(plot: plot, x: xAxis.scale, y: yAxis.scale, hasSectors: hasSectors))
    }

    /// An axis title, resolved: `along` is how far along its side it sits, 0 at the start.
    private struct AxisTitle {
        var text: String
        var isX: Bool
        var edge: ChartAxisMarkPosition
        var along: Double
        var spacing: Double
    }

    // On the leading or trailing side only the vertical part of an alignment counts, and on the top
    // or bottom only the horizontal part (measured on macOS 27, for both axes).
    private func title(_ spec: ChartAxisSpec, isX: Bool, leadingLabels: Bool) -> AxisTitle? {
        guard let text = spec.label else { return nil }
        let edge: ChartAxisMarkPosition
        switch spec.labelPosition {
        case .top: edge = .top
        case .bottom: edge = .bottom
        case .leading: edge = .leading
        case .trailing: edge = .trailing
        default: edge = isX ? .bottom : .top
        }
        let alignment = spec.labelAlignment
        let along: Double
        if edge == .leading || edge == .trailing {
            along = alignment?.isTop == true ? 0 : alignment?.isBottom == true ? 1 : 0.5
        } else if let alignment {
            along = alignment.isLeading ? 0 : alignment.isTrailing ? 1 : 0.5
        } else {
            along = isX || leadingLabels ? 0 : 1
        }
        return AxisTitle(text: text, isX: isX, edge: edge, along: along, spacing: spec.labelSpacing ?? Self.titleGap)
    }
}
