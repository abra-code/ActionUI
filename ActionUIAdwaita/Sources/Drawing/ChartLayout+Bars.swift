// Sources/Drawing/ChartLayout+Bars.swift
/*
 Bars and rectangles: their size and their rounded corners.

 - A bar takes 0.7 of its band or date bin, and 8 points where a value has neither.
 - A bar has a corner of 2 unless given. A stack, or a bar on its own on 0, rounds as one shape that
   cuts its parts: an end at 0 stays square, so one that stands on 0 rounds only its tip, facing its
   own way, and a centered stack both ends; a bar from a start to an end rounds all four. A corner
   stops at half across, and at half the length, or the whole of it with one end to round. A
   RectangleMark takes a bar's forms and sizes, 8 at a number on either axis, with no corner unless
   given, and then all four.
*/

extension ChartLayout {
    private static let barRatio = 0.7
    private static let unbinnedBarThickness = 8.0
    private static let defaultBarCorner = 2.0
    // Thinner bars stay plain rectangles: no corner would show, and side by side under GSK's rounded
    // clip they ink too much, twice over at 5,000 in a plot 364 wide.
    private static let thinnestRoundedBar = 1.0

    // How thick a bar is in a slot, which an inset measures by its size.
    private func thickness(_ dimension: ChartDimension, slot width: Double) -> Double {
        if case .inset(let points) = dimension { return abs(abs(width) - 2 * points) }
        return thickness(dimension, room: abs(width))
    }

    // How thick a bar is in `room`, the width of its band or bin. A value that has neither gives
    // no room: automatic is a fixed size there and a ratio nothing (measured on macOS 27).
    func thickness(_ dimension: ChartDimension, room: Double) -> Double {
        switch dimension {
        case .automatic: return room > 0 ? room * Self.barRatio : Self.unbinnedBarThickness
        case .fixed(let points): return points
        case .ratio(let ratio): return room * ratio
        case .inset(let points): return max(room - 2 * points, 0)
        }
    }

    func bar(_ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect,
                     bandLabelRow: Double) -> ChartRect? {
        let mark = instance.mark
        let wholeX = (plot.x, plot.x + plot.width), wholeY = (plot.y, plot.y + plot.height)

        func crossSpan(_ key: String, _ scale: ChartAxisScale, _ dimension: ChartDimension) -> (Double, Double)? {
            guard let value = instance.values[key], let center = scale.position(value, unit: mark.values[key]?.unit) else { return nil }
            // On y a bar has what its band's label leaves of the band, in any form. Room below
            // nothing still counts, by its size (measured on macOS 27: 4.2 high on bands of 12, no minimum).
            if key == "y", bandLabelRow > 0 {
                let band = abs(scale.bandWidth), room = band - bandLabelRow
                let slot = slot(instance, key, scale, room: abs(room), stacked: stack != nil)
                var across = thickness(dimension, room: abs(room))
                if case .inset(let points) = dimension { across = abs(room - 2 * points) }
                if let slot { across = thickness(dimension, slot: slot.width) }
                let middle = center - band / 2 + bandLabelRow + room / 2 + (slot?.shift ?? 0)
                return (middle - across / 2, middle + across / 2)
            }
            let slot = slot(instance, key, scale, stacked: stack != nil)
            let across = slot.map { thickness(dimension, slot: $0.width) } ?? thickness(dimension, room: scale.binWidth(value, unit: mark.values[key]?.unit))
            let middle = center + (slot?.shift ?? 0)
            return (middle - across / 2, middle + across / 2)
        }

        var xs: (Double, Double)?
        var ys: (Double, Double)?
        if let stack {
            // A stacked bar stands on 0 even above another: no place for 0, no bars (measured on macOS 27).
            guard (stack.vertical ? y : x).position(0).isFinite else { return nil }
            if stack.vertical {
                ys = (y.position(stack.low), y.position(stack.high))
                xs = mark.form == .yPoints ? pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
                    : crossSpan("x", x, mark.width)
            } else {
                xs = (x.position(stack.low), x.position(stack.high))
                ys = mark.form == .xPoints ? pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
                    : crossSpan("y", y, mark.height)
            }
        } else {
            switch mark.form {
            case .xy:
                // No number on either axis: a block where the two values meet.
                xs = crossSpan("x", x, mark.width)
                ys = crossSpan("y", y, mark.height)
            case .xPoints:
                xs = crossSpan("x", x, mark.width)
                ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
            case .yPoints:
                ys = crossSpan("y", y, mark.height)
                xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
            case .xPair:
                xs = crossSpan("x", x, mark.width)
                ys = span(instance, "yStart", "yEnd", y)
            case .pairY:
                xs = span(instance, "xStart", "xEnd", x)
                ys = crossSpan("y", y, mark.height)
            case .pointsPair:
                xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
                ys = span(instance, "yStart", "yEnd", y)
            case .pairPoints:
                xs = span(instance, "xStart", "xEnd", x)
                ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
            case .pairPair:
                xs = span(instance, "xStart", "xEnd", x)
                ys = span(instance, "yStart", "yEnd", y)
            case .pointsOnly:
                xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
                ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
            default:
                break
            }
        }
        guard let xs, let ys else { return nil }
        return ChartRect(x: min(xs.0, xs.1), y: min(ys.0, ys.1), width: abs(xs.1 - xs.0), height: abs(ys.1 - ys.0))
    }

    // A stack rounds as one shape, measured on macOS 27: a part under its corner is cut by it, an end
    // at 0 stays square, and with one end to round a corner has the whole length. Others have four.
    func rounded(_ rect: ChartRect, _ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive {
        var radius = instance.mark.kind == .BarMark ? Self.defaultBarCorner : 0
        for modifier in instance.mark.modifiers.reversed() {
            if case .cornerRadius(let given, _) = modifier {
                radius = given
            }
        }
        guard radius > 0 else { return .rect(rect, ink: ink) }
        guard let stack else {
            let side = min(rect.width, rect.height)
            guard side >= Self.thinnestRoundedBar else { return .rect(rect, ink: ink) }
            let corner = min(radius, side / 2)
            return .bar(rect, shape: rect, corners: ChartCorners(topLeading: corner, topTrailing: corner, bottomTrailing: corner, bottomLeading: corner), ink: ink)
        }
        let scale = stack.vertical ? y : x
        let lowEnd = scale.position(stack.whole.low), highEnd = scale.position(stack.whole.high)
        let start = min(lowEnd, highEnd), end = max(lowEnd, highEnd), length = end - start
        let startValue = lowEnd < highEnd ? stack.whole.low : stack.whole.high
        let endValue = lowEnd < highEnd ? stack.whole.high : stack.whole.low
        let across = stack.vertical ? rect.width : rect.height
        guard across >= Self.thinnestRoundedBar else { return .rect(rect, ink: ink) }
        let corner = min(radius, across / 2, startValue != 0 && endValue != 0 ? length / 2 : length)
        let partStart = stack.vertical ? rect.y : rect.x
        let partEnd = partStart + (stack.vertical ? rect.height : rect.width)
        let cutAtStart = startValue != 0 && partStart < start + corner
        let cutAtEnd = endValue != 0 && partEnd > end - corner
        guard cutAtStart || cutAtEnd else { return .rect(rect, ink: ink) }
        let atStart = cutAtStart ? corner : 0, atEnd = cutAtEnd ? corner : 0
        if stack.vertical {
            return .bar(rect, shape: ChartRect(x: rect.x, y: start, width: rect.width, height: length),
                        corners: ChartCorners(topLeading: atStart, topTrailing: atStart, bottomTrailing: atEnd, bottomLeading: atEnd), ink: ink)
        }
        return .bar(rect, shape: ChartRect(x: start, y: rect.y, width: length, height: rect.height),
                    corners: ChartCorners(topLeading: atStart, topTrailing: atEnd, bottomTrailing: atEnd, bottomLeading: atStart), ink: ink)
    }
}
