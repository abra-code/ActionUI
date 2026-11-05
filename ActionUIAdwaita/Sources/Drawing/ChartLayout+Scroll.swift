// Sources/Drawing/ChartLayout+Scroll.swift
/*
 A scrolling axis (chartScrollableAxes): the plot shows a window of the axis's domain, and the rest
 lies beyond its edges, drawn when the window moves there. Measured on macOS 27, in windows on
 screen (an offscreen render draws no marks for a scrolling chart):

 - Without a visible length the window is a third of the domain (0...100 shows 0 to 33).
 - A visible length is in data units on a number axis, seconds on a date axis. On a category axis
   of n categories a length L shows L * n / (n - 1) bands, and without one n / 3: Swift Charts
   counts a category axis from the first center to the last.
 - The initial position is the window's leading edge (for categories, the band's leading edge),
   held so the window stays in the domain: 95 with a length of 20 shows 80 to 100.
 - Ticks are spaced for the window: with a visible length a number axis takes as many ticks over
   its domain as 4 per window (0...100 with a length of 20 ticks every 5); without one it keeps
   the domain's own. A date axis spaces its ticks along the domain drawn at the window's scale.
 - The other axis keeps the domain of all the data.

 The window's place is kept in the axis's units (ChartScrollWindow), so new rows or a new size
 leave it where it was. Marks are clipped to the plot, and only the ticks in the window draw.
 Not done: Swift Charts lengthens a visible length that would lay out more than 100 automatic
 marks (ChartVisibleLengthLimit); here only the marks in the window are laid out, so none is.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Where a scrolling axis's window is, in the axis's units: a number, a date's seconds since the
/// reference date, or a band's index (band k from k to k + 1).
struct ChartScrollWindow: Equatable {
    /// The domain, and how much of it shows.
    var lo: Double
    var hi: Double
    var visible: Double
    /// The window's leading edge: the low end on a number axis, the top on a date or band y axis.
    var leading: Double
    /// Points per unit, as drawn: negative on an axis that runs up the plot (numbers on y), so a
    /// move of the content by some points is that many points over this in units.
    var pointsPerUnit: Double

    /// `leading` held so the window stays in the domain.
    func held(_ leading: Double) -> Double {
        min(max(leading, lo), max(hi - visible, lo))
    }
}

extension ChartLayout {
    /// The window of an axis that scrolls, its ticks spaced for it, and its leading edge from
    /// `leading` (the window's place so far, nil the first time: then `initial`, else the domain's
    /// start). nil for an axis that does not scroll or shows all of its domain.
    func scrollWindow(_ axis: inout Axis, visible length: ChartVisibleLength?, initial: ChartScalar?, leading: Double?,
                      plotLength: Double, pointsPerTick: Double) -> ChartScrollWindow? {
        let lo: Double, hi: Double, visible: Double
        switch axis.scale.kind {
        case .none:
            return nil
        case .bands(let names):
            let count = Double(names.count)
            guard count > 1 else { return nil }
            switch length {
            case .categories(let shown)?: visible = Double(shown) * count / (count - 1)
            case .amount(let shown)?: visible = shown * count / (count - 1)
            case nil: visible = count / 3
            }
            (lo, hi) = (0, count)
        case .numbers(let low, let high):
            guard high > low else { return nil }
            switch length {
            case .amount(let shown)?: visible = shown
            case .categories(let shown)?: visible = Double(shown)
            case nil: visible = (high - low) / 3
            }
            (lo, hi) = (low, high)
        case .dates(let low, let high):
            (lo, hi) = (low.timeIntervalSinceReferenceDate, high.timeIntervalSinceReferenceDate)
            guard hi > lo else { return nil }
            switch length {
            case .amount(let shown)?: visible = shown
            case .categories(let shown)?: visible = Double(shown)
            case nil: visible = (hi - lo) / 3
            }
        }
        guard visible.isFinite, visible > 0, visible < hi - lo else { return nil }
        let share = visible / (hi - lo)
        let drawn = plotLength / share

        switch axis.scale.kind {
        case .numbers(let low, let high) where length != nil && axis.steps != nil:
            let ideal = Int(min((Double(ChartTicks.idealTicks) / share).rounded(), 10_000))
            let inside = ChartTicks.inside(low, high, ideal: max(ideal, 1))
            let digits = ChartTicks.fractionDigits(inside.step)
            axis.ticks = inside.ticks.map { (.number($0), metrics.number($0, $0 == 0 ? 0 : digits)) }
        case .dates(let low, let high):
            let count = max(2, min(Int(drawn / pointsPerTick), Int((8 / share).rounded())))
            axis.ticks = dateTicks(low, high, count: count)
        default:
            break
        }

        var start = leading ?? lo
        if leading == nil, let initial {
            switch (axis.scale.kind, initial) {
            case (.bands(let names), .string(let name)): start = names[name].map(Double.init) ?? lo
            case (.numbers, .number(let number)): start = number
            case (.numbers, .integer(let number)): start = Double(number)
            case (.dates, .date(let date)): start = date.timeIntervalSinceReferenceDate
            default: break
            }
        }
        var window = ChartScrollWindow(lo: lo, hi: hi, visible: visible, leading: 0, pointsPerUnit: drawn / (hi - lo))
        window.leading = window.held(start.isFinite ? start : lo)
        return window
    }

    /// Puts a scrolling axis on the plot: the window where place() puts an axis that does not
    /// scroll (from `from` toward `to`, inside its padding or on its range in points), and the rest
    /// of its domain beyond at the same scale. Returns the window with that scale.
    func placeScrolled(_ axis: inout Axis, _ spec: ChartAxisSpec, _ window: ChartScrollWindow, from: Double, to: Double) -> ChartScrollWindow {
        var shown = axis
        shown.reversed = false
        place(&shown, spec, from: from, to: to)
        var window = window
        window.pointsPerUnit = (shown.scale.end - shown.scale.start) / window.visible
        let low = shown.scale.start - (window.leading - window.lo) * window.pointsPerUnit
        let high = low + (window.hi - window.lo) * window.pointsPerUnit
        axis.scale.start = axis.reversed ? high : low
        axis.scale.end = axis.reversed ? low : high
        return window
    }

    /// The axis groups with only the ticks, and band lines, that fall in the plot from `low` to
    /// `high` (points).
    func ticksInView(_ groups: [AxisGroup], _ scale: ChartAxisScale, from low: Double, to high: Double) -> [AxisGroup] {
        groups.map { group in
            var shown = group
            shown.inView = (low - 0.5)...(high + 0.5)
            shown.ticks = group.ticks.filter { tick in
                guard let place = scale.position(tick.value, unit: nil) else { return false }
                return place >= low - 0.5 && place <= high + 0.5
            }
            return shown
        }
    }
}
