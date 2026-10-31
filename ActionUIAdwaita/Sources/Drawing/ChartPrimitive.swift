// Sources/Drawing/ChartPrimitive.swift
/*
 What ChartLayout gives the renderer: a chart as drawing primitives in points, with no GTK in them.
*/

struct ChartPoint: Equatable {
    var x: Double
    var y: Double
}

struct ChartRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ChartInk: Equatable {
    case color(ColorSpec)
    /// The widget's text color at this opacity, so axes follow the theme.
    case text(opacity: Double)
    /// A point along even stops, 0 to 1.
    case blend([ColorSpec], at: Double)
}

enum ChartPrimitive: Equatable {
    case line(from: ChartPoint, to: ChartPoint, ink: ChartInk, stroke: ChartStroke)
    case rect(ChartRect, ink: ChartInk)
    /// A bar or a rectangle seen through `shape` with rounded corners; a stack's parts share one.
    case bar(ChartRect, shape: ChartRect, corners: ChartCorners, ink: ChartInk)
    /// `side` is the box of ChartSymbols.
    case symbol(ChartSymbol, center: ChartPoint, side: Double, ink: ChartInk)
    case path([ChartPathElement], ink: ChartInk, stroke: ChartStroke)
    /// A line with symbols on its points, which it may be too short to join.
    case markedLine([ChartPathElement], ink: ChartInk, stroke: ChartStroke, symbols: [ChartLineSymbol])
    case fill([ChartPathElement], ink: ChartInk)
    /// `alignment` is the point of the text placed at `position`, as fractions of its size.
    case text(String, position: ChartPoint, alignment: ChartPoint, ink: ChartInk)
    /// Text turned clockwise by `degrees` around its center.
    case turnedText(String, center: ChartPoint, degrees: Double, ink: ChartInk)
    /// What follows up to `endEffect` is one mark, under these effects.
    case beginEffect(ChartMarkEffect)
    case endEffect(ChartMarkEffect)
    /// What follows up to `endPlot` draws as one layer.
    case beginPlot(ChartPlotLayer)
    case endPlot(ChartPlotLayer)
    case roundedFill(ChartRect, radius: Double, ink: ChartInk)
    case border(ChartRect, width: Double, ink: ChartInk)
    /// Along `rect`, across if not `vertical`, its ends past the stops in their colors.
    case gradientBar(ChartRect, stops: [ChartGradientStop], vertical: Bool)

    /// Whether GSK can take it: values from a document or rows can pass what its floats hold (they
    /// would reach it as infinities), and a line needs a width.
    var isDrawable: Bool {
        func finite(_ values: Double...) -> Bool { values.allSatisfy { Float($0).isFinite } }
        switch self {
        case let .line(from, to, _, stroke):
            return Float(stroke.lineWidth) > 0 && finite(from.x, from.y, to.x, to.y, stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) }
        case let .rect(rect, _):
            return finite(rect.x, rect.y, rect.width, rect.height)
        case let .bar(rect, shape, corners, _):
            return finite(rect.x, rect.y, rect.width, rect.height, shape.x, shape.y, shape.width, shape.height,
                          corners.topLeading, corners.topTrailing, corners.bottomTrailing, corners.bottomLeading)
        case let .symbol(_, center, side, _):
            return finite(center.x, center.y, side)
        case let .path(elements, _, stroke):
            return Float(stroke.lineWidth) > 0 && finite(stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) } && Self.finite(elements)
        case let .markedLine(elements, _, stroke, symbols):
            return finite(stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) } && Self.finite(elements)
                && symbols.allSatisfy { finite($0.center.x, $0.center.y, $0.side) }
        case let .fill(elements, _):
            return Self.finite(elements)
        case let .text(_, position, _, _):
            return finite(position.x, position.y)
        case let .turnedText(_, center, _, _):
            return finite(center.x, center.y)
        case let .beginEffect(effect), let .endEffect(effect):
            return finite(effect.offset.x, effect.offset.y, effect.opacity, effect.blur)
                && (effect.shadow.map { finite($0.radius, $0.x, $0.y) } ?? true)
        case let .beginPlot(layer), let .endPlot(layer):
            return finite(layer.rect.x, layer.rect.y, layer.rect.width, layer.rect.height, layer.radius, layer.opacity)
        case let .roundedFill(rect, radius, _):
            return finite(rect.x, rect.y, rect.width, rect.height, radius)
        case let .border(rect, width, _):
            return width > 0 && finite(rect.x, rect.y, rect.width, rect.height, width)
        case let .gradientBar(rect, stops, _):
            return finite(rect.x, rect.y, rect.width, rect.height) && stops.allSatisfy { (0...1).contains($0.offset) }
        }
    }

    private static func finite(_ elements: [ChartPathElement]) -> Bool {
        func finite(_ point: ChartPoint) -> Bool { Float(point.x).isFinite && Float(point.y).isFinite }
        return elements.allSatisfy { element in
            switch element {
            case .move(let point), .line(let point): return finite(point)
            case let .curve(first, second, end): return finite(first) && finite(second) && finite(end)
            case .close: return true
            }
        }
    }
}

struct ChartMarkShadow: Equatable {
    /// SwiftUI's default when nil.
    var color: ColorSpec?
    var radius: Double
    var x: Double
    var y: Double
}

struct ChartMarkEffect: Equatable {
    var opacity = 1.0
    var offset = ChartPoint(x: 0, y: 0)
    var blur = 0.0
    var shadow: ChartMarkShadow?
}

struct ChartCorners: Equatable {
    var topLeading: Double
    var topTrailing: Double
    var bottomTrailing: Double
    var bottomLeading: Double
}

struct ChartLineSymbol: Equatable {
    var symbol: ChartSymbol
    var center: ChartPoint
    /// The box of ChartSymbols.
    var side: Double
    /// Its outline: the width its own mark's line style gives, not the line's.
    var lineWidth: Double
}

/// The layer a plot style draws the marks on.
struct ChartPlotLayer: Equatable {
    var rect: ChartRect
    var radius: Double
    var opacity: Double
    var clips: Bool
}
