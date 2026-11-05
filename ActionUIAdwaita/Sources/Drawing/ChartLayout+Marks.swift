// Sources/Drawing/ChartLayout+Marks.swift
/*
 A chart's marks, in drawing order, each under its effects, and points and rules, which are a single
 shape each. Bars, lines and areas, and sectors have files of their own.

 - A value the scale's math has no answer for is not drawn, and a bar stands on 0, so a log scale
   draws no bars at all, not even the upper bar of a stack. Stacked areas draw the layers that have
   both edges. A value past a domain goes where the math puts it, on every scale type.
 - A point's size is the area of a circle in its box, 50 unless given, or the shorter side of a
   width and a height, and no symbol stretches. A rule is 2 wide unless given.
 - The modifier nearest a mark wins: its own over its Plot's.
 - Marks draw in the order of the content, over the grid, lowest zIndex first.
 - A mark's opacity, offset, shadow and blur take the mark alone, not its legend entry, and the
   nearest opacity and shadow win: a Plot's opacity does not multiply a mark's. Offsets add, and
   blurs nest. An offset moves a whole mark, past its axis too. One with a start or an end moves
   those edges of a rule along it, or of a range bar or a rectangle, start being the one nearer the
   top or leading side. A bar on 0 moves only across its axis, so it narrows.
*/

import Glibc

extension ChartLayout {
    private static let defaultSymbolArea = 50.0

    func appendMarks(_ stacks: [Int: Stacked], _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect,
                             bandLabelRow: Double, into primitives: inout [ChartPrimitive],
                             annotations: inout [ChartAnnotationFrame]) {
        let angles = sectorAngles()
        var joined: [JoinedMarks: [Int]] = [:]
        for (index, instance) in marks.instances.enumerated() where instance.mark.kind == .LineMark || instance.mark.kind == .AreaMark {
            joined[JoinedMarks(kind: instance.mark.kind, series: instance.seriesKey), default: []].append(index)
        }
        for index in drawingOrder() {
            let instance = marks.instances[index]
            let ink = styles.ink(instance)
            let start = primitives.count
            let annotationCount = instance.mark.modifiers.reduce(0) { count, modifier in
                if case .annotation = modifier { return count + 1 }
                return count
            }
            // Where the mark's annotations go (ChartAnnotations), and what "automatic" is for it.
            func annotate(_ frame: ChartRect?, center: ChartPoint? = nil) {
                guard annotationCount > 0, let frame else { return }
                for ordinal in 0..<annotationCount {
                    annotations.append(ChartAnnotationFrame(instance: index, ordinal: ordinal, frame: frame, center: center))
                }
            }
            defer {
                if primitives.count > start, let effect = effect(instance) {
                    primitives.insert(.beginEffect(effect), at: start)
                    primitives.append(.endEffect(effect))
                }
            }
            // An annotation of a line or area belongs to one of its points.
            if instance.mark.kind == .LineMark || instance.mark.kind == .AreaMark, annotationCount > 0,
               let px = position(instance, "x", x), let py = position(instance, "y", y) {
                annotate(ChartRect(x: px, y: py, width: 0, height: 0))
            }
            switch instance.mark.kind {
            case .BarMark, .RectangleMark:
                if var rect = bar(instance, stack: stacks[index], x, y, plot, bandLabelRow: bandLabelRow) {
                    var moving = edges(instance)
                    if stacks[index]?.vertical == true {
                        moving.yStart = 0
                        moving.yEnd = 0
                    } else if stacks[index] != nil {
                        moving.xStart = 0
                        moving.xEnd = 0
                    }
                    rect = moved(rect, by: moving)
                    primitives.append(rounded(rect, instance, stack: stacks[index], x, y, ink: ink))
                    annotate(rect)
                }
            case .PointMark:
                if let primitive = point(instance, x, y, plot, ink: ink) {
                    primitives.append(primitive)
                    if case let .symbol(_, center, side, _) = primitive {
                        let half = side / 2 + ChartAnnotationPlacement.pointMargin
                        annotate(ChartRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2))
                    }
                }
            case .RuleMark:
                if let primitive = rule(instance, x, y, plot, ink: ink) {
                    primitives.append(primitive)
                    if case let .line(from, to, _, _) = primitive {
                        annotate(ChartRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y)))
                    }
                }
            case .LineMark:
                // Joined marks draw at the first one's place, zIndex included, whichever comes up first.
                if let indices = joined[JoinedMarks(kind: .LineMark, series: instance.seriesKey)], indices[0] == index,
                   let primitive = line(indices, x, y, ink: ink) {
                    primitives.append(primitive)
                }
            case .AreaMark:
                if let indices = joined[JoinedMarks(kind: .AreaMark, series: instance.seriesKey)], indices[0] == index,
                   let primitive = area(indices, stacks, x, y, ink: ink) {
                    primitives.append(primitive)
                }
            case .SectorMark:
                if let angle = angles[index] {
                    let shape = sector(instance, angle, plot)
                    let outline = ChartSectors.outline(shape)
                    if !outline.isEmpty {
                        primitives.append(.fill(outline, ink: ink))
                        annotate(ChartAnnotationPlacement.bounds(of: shape), center: ChartAnnotationPlacement.centroid(of: shape))
                    }
                }
            }
        }
    }

    /// The marks that draw as one line or one area.
    private struct JoinedMarks: Hashable {
        var kind: ChartMarkKind
        var series: String
    }

    // Lowest zIndex first, each level in the order of the content.
    private func drawingOrder() -> [Int] {
        func zIndex(_ instance: ChartMarkInstance) -> Double {
            for modifier in instance.mark.modifiers {
                if case .zIndex(let value) = modifier { return value }
            }
            return 0
        }
        let levels = marks.instances.map(zIndex)
        guard levels.contains(where: { $0 != 0 }) else { return Array(levels.indices) }
        return levels.indices.sorted { levels[$0] == levels[$1] ? $0 < $1 : levels[$0] < levels[$1] }
    }

    // What a mark asks of its drawing, nearest modifier first; nil for nothing.
    private func effect(_ instance: ChartMarkInstance) -> ChartMarkEffect? {
        var effect = ChartMarkEffect()
        for modifier in instance.mark.modifiers.reversed() {
            switch modifier {
            case .opacity(let opacity):
                effect.opacity = min(max(opacity, 0), 1)
            case .blur(let radius):
                let added = max(radius, 0)
                effect.blur = (effect.blur * effect.blur + added * added).squareRoot()
            case .shadow(let color, let radius, let x, let y):
                effect.shadow = ChartMarkShadow(color: color, radius: radius, x: x, y: y)
            case .offset(.xy(let x, let y)):
                effect.offset.x += x
                effect.offset.y += y
            case .offset(.xYRange(let x, _, _)):
                effect.offset.x += x
            case .offset(.xRangeY(_, _, let y)):
                effect.offset.y += y
            default:
                break
            }
        }
        return effect == ChartMarkEffect() ? nil : effect
    }

    /// How far an offset moves a mark's edges: start nearer the top or leading side.
    private struct MarkEdges {
        var xStart = 0.0
        var xEnd = 0.0
        var yStart = 0.0
        var yEnd = 0.0
    }

    private func edges(_ instance: ChartMarkInstance) -> MarkEdges {
        var edges = MarkEdges()
        for modifier in instance.mark.modifiers.reversed() {
            guard case .offset(let offset) = modifier else { continue }
            switch offset {
            case .xy:
                break
            case .xYRange(_, let yStart, let yEnd):
                edges.yStart += yStart
                edges.yEnd += yEnd
            case .xRangeY(let xStart, let xEnd, _):
                edges.xStart += xStart
                edges.xEnd += xEnd
            case .ranges(let xStart, let xEnd, let yStart, let yEnd):
                edges.xStart += xStart
                edges.xEnd += xEnd
                edges.yStart += yStart
                edges.yEnd += yEnd
            }
        }
        return edges
    }

    private func moved(_ rect: ChartRect, by edges: MarkEdges) -> ChartRect {
        let width = rect.width + edges.xEnd - edges.xStart, height = rect.height + edges.yEnd - edges.yStart
        return ChartRect(x: rect.x + edges.xStart + min(width, 0), y: rect.y + edges.yStart + min(height, 0), width: abs(width), height: abs(height))
    }

    // A mark's symbol, if it names one, and its box.
    func symbol(_ instance: ChartMarkInstance) -> (shape: ChartSymbol?, side: Double) {
        var shape: ChartSymbol?
        var area = Self.defaultSymbolArea
        var size: ChartSize?
        // Backward, so the modifier nearest the mark is the one that stays.
        for modifier in instance.mark.modifiers.reversed() {
            switch modifier {
            case .symbol(let symbol):
                shape = symbol
            case .symbolBy:
                shape = instance.symbolKey.map(styles.symbol(named:))
            case .symbolArea(let given):
                area = max(given, 0)
                size = nil
            case .symbolSizeBy:
                if let given = styles.area(instance) {
                    area = max(given, 0)
                    size = nil
                }
            case .symbolSize(let given):
                size = given
            default:
                break
            }
        }
        return (shape, size.map { max(min($0.width, $0.height), 0) } ?? 2 * (area / .pi).squareRoot())
    }

    func stroke(_ instance: ChartMarkInstance, default fallback: ChartStroke) -> ChartStroke {
        if let key = instance.lineStyleKey { return styles.stroke(named: key) }
        if let value = instance.lineStyleValue { return styles.stroke(for: value) }
        var stroke = fallback
        for modifier in instance.mark.modifiers.reversed() {
            if case .lineStyle(let style) = modifier {
                stroke = style
            }
        }
        return stroke
    }

    private func point(_ instance: ChartMarkInstance, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect, ink: ChartInk) -> ChartPrimitive? {
        guard let centerX = coordinate(instance, "x", x, origin: plot.x, length: plot.width),
              let centerY = coordinate(instance, "y", y, origin: plot.y, length: plot.height) else { return nil }
        let (shape, side) = symbol(instance)
        return .symbol(shape ?? .circle, center: ChartPoint(x: centerX, y: centerY), side: side, ink: ink)
    }

    private func rule(_ instance: ChartMarkInstance, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect, ink: ChartInk) -> ChartPrimitive? {
        let mark = instance.mark
        let wholeX = (plot.x, plot.x + plot.width), wholeY = (plot.y, plot.y + plot.height)
        let stroke = stroke(instance, default: Self.defaultLine)
        let atX = coordinate(instance, "x", x, origin: plot.x, length: plot.width).map { ($0, $0) }
        let atY = coordinate(instance, "y", y, origin: plot.y, length: plot.height).map { ($0, $0) }
        let xs: (Double, Double)?
        let ys: (Double, Double)?
        switch mark.form {
        case .xPoints:
            xs = atX
            ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
        case .yPoints:
            ys = atY
            xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
        case .xPair:
            xs = atX
            ys = span(instance, "yStart", "yEnd", y)
        case .pairY:
            ys = atY
            xs = span(instance, "xStart", "xEnd", x)
        case .pointsPair:
            xs = atX
            ys = span(instance, "yStart", "yEnd", y)
        case .pairPoints:
            ys = atY
            xs = span(instance, "xStart", "xEnd", x)
        default:
            return nil
        }
        guard let xs, let ys else { return nil }
        // Its ends are its only edges: an offset across a rule moves nothing (measured on macOS 27).
        func ends(_ span: (Double, Double), _ start: Double, _ end: Double) -> (Double, Double) {
            span.0 <= span.1 ? (span.0 + start, span.1 + end) : (span.0 + end, span.1 + start)
        }
        let edges = edges(instance)
        let isVertical = mark.form == .xPoints || mark.form == .xPair || mark.form == .pointsPair
        let along = isVertical ? (xs, ends(ys, edges.yStart, edges.yEnd)) : (ends(xs, edges.xStart, edges.xEnd), ys)
        return .line(from: ChartPoint(x: along.0.0, y: along.1.0), to: ChartPoint(x: along.0.1, y: along.1.1), ink: ink, stroke: stroke)
    }
}
