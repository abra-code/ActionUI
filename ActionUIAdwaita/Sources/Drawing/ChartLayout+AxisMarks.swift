// Sources/Drawing/ChartLayout+AxisMarks.swift
/*
 What an axis draws, Swift Charts' default marks or its AxisMarks: gridlines, ticks and labels.

 - The y axis is on the trailing side, with solid gridlines at its ticks.
 - Categories are bands of equal width, in order of first use, with dashed lines at the band edges
   on x and solid ones on y. On y their labels take no room: each sits on the top line of its band,
   inside the plot at the leading edge or just past it at the trailing edge, and nothing thins or
   clips them. A bar there has only what a label's row leaves of its band; on a tight axis that is
   less than nothing, it draws at that size and runs past its band. Other marks stay at the band's
   center. Automatic marks sit at the leading edge, and a tick there runs into the plot.
 - Number and date ticks on the x axis have a dashed line, and their label starts at the tick.
 - An AxisMarks chooses its ticks and draws in its own way: desiredCount is the count of ticks an
   automatic axis aims for, and explicit values or a stride change the ticks, not the domain, which
   holds what each automatic AxisMarks widens it to. A list of names on bands changes nothing.
   Marks with content draw only that content, each entry its own way. Lines on x and on bands are
   dashed, and on bands they sit at the band edges, centered or not. A tick's given length adds to
   the room around the plot and moves no label.
 - A label's anchor counts only in these (measured on macOS 27): on x topTrailing and bottomTrailing
   end it before its tick or its band's end, and bottomLeading and bottomTrailing put it inside the
   plot; on a y axis of numbers top and bottom put it under or over its tick, and the side that
   faces the plot puts it inside. A centered label on x numbers and dates sits between its tick and
   the next.
*/

extension ChartAlignment {
    var isLeading: Bool { self == .leading || self == .topLeading || self == .bottomLeading }
    var isTrailing: Bool { self == .trailing || self == .topTrailing || self == .bottomTrailing }
    var isTop: Bool { self == .top || self == .topLeading || self == .topTrailing }
    var isBottom: Bool { self == .bottom || self == .bottomLeading || self == .bottomTrailing }
}

extension ChartLayout {
    private static let tickDash = ChartStroke(lineWidth: 1, dash: [2, 2])
    // How far a tick line runs past the plot, into the labels' room.
    private static let tickLength = 6.0
    private static let yTickLength = 4.0

    /// A line of an axis: a gridline across the plot, running `length` past it, or a tick that is
    /// only that part outside it.
    struct AxisLine {
        var ink = ChartLayout.gridInk
        var stroke: ChartStroke
        var length = 0.0
    }

    struct AxisLabel {
        var ink = ChartLayout.labelInk
        var anchor: ChartAlignment?
        var centered = false
        var offset = ChartSize(width: 0, height: 0)
    }

    /// One thing an AxisMarks draws, or Swift Charts' default marks: the ticks, the edge its labels
    /// and ticks are on, and what it draws at them.
    struct AxisGroup {
        var ticks: [(value: ChartScalar, label: String)]
        var edge: ChartAxisMarkPosition
        var grid: AxisLine?
        var tick: AxisLine?
        var label: AxisLabel?
        /// Where lines may go on a scrolled axis (points): its band lines past the plot are left out.
        var inView: ClosedRange<Double>?
    }

    func marks(_ spec: ChartAxisSpec) -> [ChartAxisMarksSpec] {
        guard spec.visibility != .hidden else { return [] }
        return spec.marks.flatMap { $0.isEmpty ? nil : $0 } ?? [ChartAxisMarksSpec()]
    }

    private func edge(_ marks: ChartAxisMarksSpec, isX: Bool, bands: Bool = false) -> ChartAxisMarkPosition {
        switch (marks.position, isX) {
        case (.top, true), (.bottom, true), (.leading, false), (.trailing, false): return marks.position
        case (_, true): return .bottom
        case (.automatic, false) where bands: return .leading
        case (_, false): return .trailing
        }
    }

    // The edges that hold labels, known before any tick is.
    func labelEdges(_ spec: ChartAxisSpec, isX: Bool) -> Set<ChartAxisMarkPosition> {
        Set(marks(spec).filter { marks in
            guard let items = marks.items else { return true }
            return items.contains { item in
                if case .valueLabel = item.kind { return true } else { return false }
            }
        }.map { edge($0, isX: isX) })
    }

    // What ticks add to the room on an edge: a given length, and an automatic one on a y axis,
    // however long the labels there; they run on under the labels (measured on macOS 27).
    func tickRoom(_ spec: ChartAxisSpec, isX: Bool, _ edge: ChartAxisMarkPosition, bands: Bool = false) -> Double {
        var room = 0.0
        for marks in marks(spec) where self.edge(marks, isX: isX, bands: bands) == edge {
            for item in marks.items ?? [] {
                guard case .tick(_, let length, _) = item.kind else { continue }
                switch length {
                case .fixed(let points): room = max(room, points)
                case .automatic where !isX: room = max(room, Self.yTickLength)
                default: break
                }
            }
        }
        return room
    }

    func groups(_ spec: ChartAxisSpec, _ axis: Axis, isX: Bool) -> [AxisGroup] {
        // Lines are dashed on x and plain on y (measured on macOS 27).
        let dashed = isX
        let lineStroke = dashed ? Self.tickDash : ChartStroke()
        var bands = false
        if case .bands = axis.scale.kind { bands = true }
        return marks(spec).flatMap { marks -> [AxisGroup] in
            let ticks = ticks(marks, axis)
            let edge = edge(marks, isX: isX, bands: bands)
            guard let items = marks.items else {
                // Swift Charts' default: on x a line that runs on past the plot.
                let length = dashed ? Self.tickLength : 0
                return [AxisGroup(ticks: marks.format.map { labeled(ticks, $0) } ?? ticks, edge: edge,
                                  grid: AxisLine(stroke: marks.stroke ?? lineStroke, length: length), label: AxisLabel())]
            }
            // Every entry draws, two labels or gridlines of one AxisMarks too (measured on macOS 27).
            return items.map { item in
                var group = AxisGroup(ticks: ticks, edge: edge)
                let ink = item.foregroundStyle.map { ChartInk.color($0) }
                switch item.kind {
                case let .gridLine(_, stroke):
                    group.grid = AxisLine(ink: ink ?? Self.gridInk, stroke: stroke ?? lineStroke)
                case let .tick(_, length, stroke):
                    group.tick = AxisLine(ink: ink ?? Self.gridInk, stroke: stroke ?? lineStroke, length: tickLength(length, ticks, isX: isX))
                case let .valueLabel(format, centered, anchor, _, _, _, _, _, _):
                    if let format { group.ticks = labeled(ticks, format) }
                    group.label = AxisLabel(ink: ink ?? Self.labelInk, anchor: anchor, centered: centered == true,
                                            offset: item.offset ?? ChartSize(width: 0, height: 0))
                }
                return group
            }
        }
    }

    // How far a tick runs: to the far side of a label, across an axis's labels (measured on macOS 27).
    private func tickLength(_ length: ChartAxisMarkItem.TickLength, _ ticks: [(value: ChartScalar, label: String)], isX: Bool) -> Double {
        switch length {
        case .automatic: return isX ? Self.tickLength : Self.yTickLength
        case .fixed(let points): return points
        case .label(let past), .longestLabel(let past):
            let sizes = ticks.map { metrics.size($0.label) }
            return (sizes.map { isX ? $0.height : $0.width }.max() ?? 0) + Self.labelGap + past
        }
    }

    private func labeled(_ ticks: [(value: ChartScalar, label: String)], _ format: ChartAxisFormat) -> [(value: ChartScalar, label: String)] {
        ticks.map { tick in
            switch (format, tick.value) {
            case (.number(let spec), .number(let number)): return (tick.value, metrics.formatted(number, spec))
            case (.number(let spec), .integer(let number)): return (tick.value, metrics.formatted(Double(number), spec))
            case (.date(let format), .date(let date)): return (tick.value, metrics.date(date, format.skeleton))
            default: return tick
            }
        }
    }

    // The ticks an AxisMarks asks for. Values outside the domain have no tick; they do not move it.
    // A stride or a list past ChartAxisStrideLimit is automatic values: a draw of 100,000 lines runs
    // the box out of memory. A list is in the axis's order, and a list of names on bands changes
    // nothing (measured on macOS 27).
    private func ticks(_ marks: ChartAxisMarksSpec, _ axis: Axis) -> [(value: ChartScalar, label: String)] {
        func numbers(_ values: [Double], digits: Int) -> [(value: ChartScalar, label: String)] {
            values.map { (.number($0), metrics.number($0, $0 == 0 ? 0 : digits)) }
        }
        func chosen(_ values: [Double]) -> [(value: ChartScalar, label: String)] {
            numbers(values, digits: ChartTicks.fractionDigits(of: values))
        }
        switch (marks.values, axis.scale.kind) {
        case let (.automatic(count, lower, upper), .numbers) where count != nil || lower != nil || upper != nil:
            guard let steps = axis.steps else { return axis.ticks }
            let ideal = count ?? ChartTicks.idealTicks
            if steps.exact {
                let inside = ChartTicks.inside(steps.lo, steps.hi, ideal: ideal)
                return numbers(inside.ticks, digits: ChartTicks.fractionDigits(inside.step))
            }
            let widened = ChartTicks.widened(steps.lo, steps.hi, ideal: ideal, roundLower: lower ?? true, roundUpper: upper ?? true)
            return numbers(widened.ticks, digits: ChartTicks.fractionDigits(widened.step))
        case let (.automatic(count?, _, _), .dates(lo, hi)):
            return dateTicks(lo, hi, count: count)
        case let (.numberStride(step), .numbers(lo, hi)) where hi > lo && (hi - lo) / step <= Double(ChartAxisStrideLimit.maxStrideMarks):
            return chosen(ChartTicks.multiples(of: step, lo, hi))
        case let (.calendarStride(unit, count), .dates(lo, hi)):
            let dates = ChartDates.ticks(lo, hi, stride: ChartDateStride(unit: unit, count: count))
            return dates.count < ChartAxisStrideLimit.maxStrideMarks ? dateLabels(dates, unit: unit) : axis.ticks
        case let (.numbers(values), .numbers(lo, hi)):
            let shown = values.filter { $0 >= lo && $0 <= hi }
            return shown.count <= ChartAxisStrideLimit.maxStrideMarks ? chosen(shown.sorted()) : axis.ticks
        case let (.dates(values), .dates(lo, hi)):
            let shown = values.filter { $0 >= lo && $0 <= hi }
            return shown.count <= ChartAxisStrideLimit.maxStrideMarks ? dateLabels(shown.sorted(), unit: .day) : axis.ticks
        default:
            return axis.ticks
        }
    }

    // How many bands a label takes that needs `room` points, so labels never overlap, and their
    // lines, which would otherwise fill a tight axis.
    private func bandStride(_ scale: ChartAxisScale, room: Double) -> Int {
        guard case .bands(let names) = scale.kind else { return 1 }
        let band = abs(scale.bandWidth)
        // A range in points can make bands far narrower than an Int counts: past the last is enough.
        return band > 0 ? max(1, Int(min((room / band).rounded(.up), Double(names.count + 1)))) : 1
    }

    // A tick's place among those a tight axis thins: on bands its band, so the labels of a scrolled
    // axis, which has only the ticks in view, stay on the bands of its lines; else its place in the list.
    private func thinned(_ value: ChartScalar, _ scale: ChartAxisScale, _ index: Int) -> Int {
        if case .bands(let names) = scale.kind, case .string(let name) = value, let band = names[name] { return band }
        return index
    }

    // A band's lines are at its edges, centered or not (measured on macOS 27).
    private func linePositions(_ group: AxisGroup, _ scale: ChartAxisScale, every: Int) -> [Double] {
        if case .bands(let names) = scale.kind {
            let edges = stride(from: 0, through: names.count, by: every).map { scale.start + Double($0) * scale.bandWidth }
            return group.inView.map { view in edges.filter { view.contains($0) } } ?? edges
        }
        return group.ticks.compactMap { scale.position($0.value, unit: nil) }
    }

    func appendYGroup(_ group: AxisGroup, _ scale: ChartAxisScale, _ plot: ChartRect, lineHeight: Double, into primitives: inout [ChartPrimitive]) {
        let left = plot.x, right = plot.x + plot.width
        let trailing = group.edge == .trailing
        var bands = false
        if case .bands = scale.kind { bands = true }
        // Bands keep every line and label however tight; only lines under a point apart thin.
        let every = bandStride(scale, room: 1)
        if let grid = group.grid {
            for y in linePositions(group, scale, every: every) {
                let from = ChartPoint(x: trailing ? left : left - grid.length, y: y)
                let to = ChartPoint(x: trailing ? right + grid.length : right, y: y)
                primitives.append(.line(from: from, to: to, ink: grid.ink, stroke: grid.stroke))
            }
        }
        if let tick = group.tick {
            for y in linePositions(group, scale, every: every) {
                // Out from the plot, and on bands into it (measured on macOS 27).
                let start = trailing ? right : left
                let end = start + (trailing != bands ? tick.length : -tick.length)
                primitives.append(.line(from: ChartPoint(x: start, y: y), to: ChartPoint(x: end, y: y), ink: tick.ink, stroke: tick.stroke))
            }
        }
        guard let label = group.label else { return }
        let anchor = label.anchor
        // The anchor's side that faces the plot puts a label inside it, on either edge. On bands a
        // label starts past its edge, unless a trailing anchor ends it there (measured on macOS 27).
        let inward = trailing ? anchor?.isTrailing == true : anchor?.isLeading == true
        let rightward = bands ? anchor?.isTrailing != true : trailing != inward
        let x = (trailing ? right : left) + (rightward ? Self.labelGap : -Self.labelGap)
        for (index, tick) in group.ticks.enumerated() where thinned(tick.value, scale, index) % every == 0 {
            guard var y = scale.position(tick.value, unit: nil) else { continue }
            // A band's tick is its top line.
            if bands { y -= abs(scale.bandWidth) / 2 }
            var alignment = 0.5
            // Under or over its tick, one that would then pass the plot's end is left out.
            if anchor?.isTop == true {
                y += Self.labelGap
                alignment = 0
                guard y + lineHeight <= plot.y + plot.height else { continue }
            } else if anchor?.isBottom == true {
                y -= Self.labelGap
                alignment = 1
                guard y - lineHeight >= plot.y else { continue }
            }
            primitives.append(.text(tick.label, position: ChartPoint(x: x + label.offset.width, y: y + label.offset.height),
                                    alignment: ChartPoint(x: rightward ? 0 : 1, y: alignment), ink: label.ink))
        }
    }

    func appendXGroup(_ group: AxisGroup, _ scale: ChartAxisScale, _ plot: ChartRect, into primitives: inout [ChartPrimitive]) {
        if case .none = scale.kind { return }
        let top = plot.y, bottom = plot.y + plot.height
        let below = group.edge == .bottom
        let edgeY = below ? bottom : top
        let outward = below ? 1.0 : -1.0
        var every = 1
        if case .bands = scale.kind {
            // Labels wider than their band show every few bands.
            let widest = group.ticks.map { metrics.size($0.label).width }.max() ?? 0
            every = bandStride(scale, room: widest + Self.labelGap)
        }
        if let grid = group.grid {
            for x in linePositions(group, scale, every: every) {
                let far = below ? top : bottom
                primitives.append(.line(from: ChartPoint(x: x, y: far), to: ChartPoint(x: x, y: edgeY + outward * grid.length), ink: grid.ink, stroke: grid.stroke))
            }
        }
        if let tick = group.tick {
            for x in linePositions(group, scale, every: every) {
                primitives.append(.line(from: ChartPoint(x: x, y: edgeY), to: ChartPoint(x: x, y: edgeY + outward * tick.length), ink: tick.ink, stroke: tick.stroke))
            }
        }
        guard let label = group.label else { return }
        let inside = label.anchor == .bottomLeading || label.anchor == .bottomTrailing
        let ending = label.anchor == .topTrailing || label.anchor == .bottomTrailing
        let labelY = edgeY + (inside ? -outward : outward) * Self.labelGap
        let textY = below != inside ? 0.0 : 1.0
        if case .bands = scale.kind {
            for (index, tick) in group.ticks.enumerated() where thinned(tick.value, scale, index) % every == 0 {
                guard let center = scale.position(tick.value, unit: nil) else { continue }
                let x = ending ? center + abs(scale.bandWidth) / 2 - Self.labelGap : center
                primitives.append(.text(tick.label, position: ChartPoint(x: x + label.offset.width, y: labelY + label.offset.height),
                                        alignment: ChartPoint(x: ending ? 1 : 0.5, y: textY), ink: label.ink))
            }
            return
        }
        let right = plot.x + plot.width
        // On an axis that runs right to left a label ends at its tick (measured on macOS 27).
        let backward = scale.end < scale.start
        var nextFree = backward ? Double.infinity : -Double.infinity
        let places = group.ticks.compactMap { tick in scale.position(tick.value, unit: nil).map { (label: tick.label, x: $0) } }
        for (index, place) in places.enumerated() {
            // A label starts at its tick; one that would pass the plot's end or the label before
            // it is left out. A centered one sits between its tick and the next, and the last,
            // which has none, stays at its tick (measured on macOS 27).
            let labelWidth = metrics.size(place.label).width
            var start = backward || ending ? place.x - Self.labelGap - labelWidth : place.x + Self.labelGap
            if label.centered, index + 1 < places.count {
                start = (place.x + places[index + 1].x - labelWidth) / 2
            }
            let fits = backward ? start + labelWidth <= nextFree && start >= plot.x
                : start >= nextFree && start + labelWidth <= right && (!ending || start >= plot.x)
            guard fits else { continue }
            primitives.append(.text(place.label, position: ChartPoint(x: start + label.offset.width, y: labelY + label.offset.height),
                                    alignment: ChartPoint(x: 0, y: textY), ink: label.ink))
            nextFree = backward ? start - Self.labelGap : start + labelWidth + Self.labelGap
        }
    }
}
