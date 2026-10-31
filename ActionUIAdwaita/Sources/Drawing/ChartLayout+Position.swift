// Sources/Drawing/ChartLayout+Position.swift
/*
 Where a mark's values land on the plot: on its axes, and in a position scale's slots.

 - A position scale gives each of its names a slot in every band or bin, in order of first use, so
   a band without a name leaves that slot empty. The slots share what a bar would take, unless a
   span says otherwise, and on y a bar's room is what the label's row leaves, while other marks have
   the whole band. A bar takes its usual part of its slot, and others sit at its center. Stacks are
   per slot, and a position does not split a line. A date's bin is room for bars and rectangles
   alone. A position acts on one axis, the mark's own: a start and end of categories move by a slot
   as a value does, dates and numbers do not, and an inset past the room reverses the slots. A
   number or date falls along the room from the middle of the band, all of it a bar's slot. A bar
   that stacks and has no position takes the first slot, and one that does not, or a rectangle, the
   whole room, each in the first position's span.
 - A start and end on an axis of categories run from the edge of one band to the far edge of the other;
   dates with a unit go in the middle of their bins, as a single value does.
 - Points given to a mark count from the plot's top leading corner.
*/

extension ChartLayout {
    func position(_ instance: ChartMarkInstance, _ key: String, _ scale: ChartAxisScale) -> Double? {
        instance.values[key].flatMap { scale.position($0, unit: instance.mark.values[key]?.unit) }.map { $0 + (slot(instance, key, scale)?.shift ?? 0) }
    }

    // Where a position scale puts a mark on `key`'s axis, from the middle of its band or bin, and
    // its slot's width, negative when an inset passes the room. `room` is that of a bar on y bands,
    // and a bar without a position takes the first slot if it stacks. Nil without one (all measured
    // on macOS 27).
    func slot(_ instance: ChartMarkInstance, _ key: String, _ scale: ChartAxisScale, room given: Double? = nil, stacked: Bool = false) -> (shift: Double, width: Double)? {
        guard instance.positionAxis == key else { return nil }
        let sized = instance.mark.kind == .BarMark || instance.mark.kind == .RectangleMark
        let span: ChartDimension
        if instance.positionKey != nil {
            span = instance.positionSpan
        } else if sized, let first = styles.firstPosition, first.axis == key {
            span = first.span
        } else {
            return nil
        }
        let bin = instance.values[key].map { scale.binWidth($0, unit: instance.mark.values[key]?.unit) } ?? 0
        let room = given ?? (sized ? bin : abs(scale.bandWidth))
        let whole: Double
        switch span {
        case .automatic where room <= 0 && !sized: whole = 0
        case .inset(let points): whole = room - 2 * points
        default: whole = thickness(span, room: room)
        }
        // A bar's or a rectangle's slots run with a date bin on an axis that runs backward. Other
        // marks and dates without a unit, which have no bin, keep their order (measured on macOS 27).
        var backward = false
        if case .dates = scale.kind {
            backward = sized && instance.mark.values[key]?.unit != nil && scale.end < scale.start
        }
        let along = backward ? -1.0 : 1.0
        if let value = instance.positionValue {
            return (along * styles.positionShare(value.start) * whole, whole)
        }
        guard let name = instance.positionName else {
            guard stacked else { return (0, whole) }
            let width = whole / Double(max(styles.positionSlots, 1))
            return (along * (width / 2 - whole / 2), width)
        }
        guard let place = styles.positionSlot(named: name) else { return nil }
        let width = whole / Double(place.count)
        return (along * ((Double(place.index) + 0.5) * width - whole / 2), width)
    }

    // Where a mark's value goes on an axis. A coordinate in points counts from the plot's corner; a
    // missing one is its middle.
    func coordinate(_ instance: ChartMarkInstance, _ key: String, _ scale: ChartAxisScale, origin: Double, length: Double) -> Double? {
        if instance.values[key] != nil {
            return position(instance, key, scale)
        }
        return instance.mark.points[key].map { origin + $0 } ?? origin + length / 2
    }

    // The points a start and an end span on an axis: the middles of their date bins, or the outer
    // edges of their bands (measured on macOS 27: a pair of categories covers both whole).
    func span(_ instance: ChartMarkInstance, _ startKey: String, _ endKey: String, _ scale: ChartAxisScale) -> (Double, Double)? {
        let unit = instance.mark.values[startKey]?.unit ?? instance.mark.values[endKey]?.unit
        guard let start = instance.values[startKey], let end = instance.values[endKey],
              let low = scale.position(start, unit: unit), let high = scale.position(end, unit: unit) else { return nil }
        var shift = 0.0
        if case .bands = scale.kind {
            shift = slot(instance, startKey == "xStart" ? "x" : "y", scale, room: abs(scale.bandWidth))?.shift ?? 0
        }
        return (low - scale.bandWidth / 2 + shift, high + scale.bandWidth / 2 + shift)
    }

    // A span in points from the plot's corner, or the plot's whole run where a mark gives none.
    func pointsSpan(_ instance: ChartMarkInstance, _ startKey: String, _ endKey: String, whole: (Double, Double)) -> (Double, Double) {
        (instance.mark.points[startKey].map { whole.0 + $0 } ?? whole.0, instance.mark.points[endKey].map { whole.0 + $0 } ?? whole.1)
    }
}
