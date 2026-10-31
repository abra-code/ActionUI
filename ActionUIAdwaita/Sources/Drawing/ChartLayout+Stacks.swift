// Sources/Drawing/ChartLayout+Stacks.swift
/*
 How bars and areas stack: each stacking mark's reach along its value axis, known before any axis is.

 Bars at one position stack in row order, those below 0 downward. A normalized stack is that as a
 percentage of the longer side, on an axis of plain numbers (a rule at 40 sits at 40 of 100); a
 centered one is that moved so its two ends are as far from 0.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ChartLayout {
    private static let percent = 100.0

    /// One bar's reach along its value axis, when it comes from stacking.
    struct Stacked {
        var vertical: Bool
        var low: Double
        var high: Double
        /// The reach of its whole stack, which rounds as one shape.
        var whole: (low: Double, high: Double)
    }

    private func isNumber(_ value: ChartScalar?) -> Bool {
        switch value {
        case .number?, .integer?: return true
        default: return false
        }
    }

    func number(_ value: ChartScalar?) -> Double? {
        switch value {
        case .number(let number)?: return number
        case .integer(let number)?: return Double(number)
        default: return nil
        }
    }

    /// What marks stack by: their kind (a bar and an area at one place do not stack, measured on
    /// macOS 27), direction and position, one for a date bin however the dates in it differ, and one
    /// for a number written as an integer or not.
    private struct StackKey: Hashable {
        enum Position: Hashable {
            case none
            case category(String)
            case number(Double)
            case date(Date)
        }
        var kind: ChartMarkKind
        var vertical: Bool
        var position: Position
        /// A position scale's name: only marks in one slot stack.
        var slot: String?
    }

    private func stackPosition(_ value: ChartScalar?, unit: Calendar.Component?) -> StackKey.Position {
        switch value {
        case .string(let name)?: return .category(name)
        case .number(let number)?: return .number(number)
        case .integer(let number)?: return .number(Double(number))
        case .date(let date)?: return .date(ChartDates.bin(date, unit).start)
        case nil: return .none
        }
    }

    // The value of a bar that stacks, and where. nil for one that spans two values of its own or
    // has no number.
    private func stackedValue(_ instance: ChartMarkInstance) -> (value: Double, key: StackKey)? {
        guard instance.mark.kind == .BarMark || instance.mark.kind == .AreaMark else { return nil }
        let x = instance.values["x"], y = instance.values["y"]
        switch instance.mark.form {
        case .xy, .xySeries:
            let vertical = !(isNumber(x) && !isNumber(y))
            let position = vertical ? stackPosition(x, unit: instance.mark.values["x"]?.unit) : stackPosition(y, unit: instance.mark.values["y"]?.unit)
            return number(vertical ? y : x).map { ($0, StackKey(kind: instance.mark.kind, vertical: vertical, position: position, slot: instance.positionKey)) }
        case .xPoints:
            return number(x).map { ($0, StackKey(kind: instance.mark.kind, vertical: false, position: .none, slot: instance.positionKey)) }
        case .yPoints:
            return number(y).map { ($0, StackKey(kind: instance.mark.kind, vertical: true, position: .none, slot: instance.positionKey)) }
        default:
            return nil
        }
    }

    // Each stacking bar's span, by instance. Bars at one position and in one direction stack in
    // row order, out from 0 on each side. Normalized divides that by the longer side, so it reaches
    // 1; center moves it so its ends are as far from 0 (measured on macOS 27, negatives included).
    func stacks() -> [Int: Stacked] {
        var entries: [(index: Int, value: Double, key: StackKey)] = []
        var totals: [StackKey: (positive: Double, negative: Double)] = [:]
        for (index, instance) in marks.instances.enumerated() {
            guard let stacked = stackedValue(instance), stacked.value.isFinite else { continue }
            entries.append((index, stacked.value, stacked.key))
            if stacked.value >= 0 {
                totals[stacked.key, default: (0, 0)].positive += stacked.value
            } else {
                totals[stacked.key, default: (0, 0)].negative += stacked.value
            }
        }
        var reached: [StackKey: (positive: Double, negative: Double)] = [:]
        var spans: [Int: Stacked] = [:]
        var wholes: [StackKey: (low: Double, high: Double)] = [:]
        for entry in entries {
            let stacking = marks.instances[entry.index].mark.stacking
            var low = 0.0, high = entry.value
            if stacking != .unstacked {
                if entry.value >= 0 {
                    low = reached[entry.key]?.positive ?? 0
                    high = low + entry.value
                    reached[entry.key, default: (0, 0)].positive = high
                } else {
                    low = reached[entry.key]?.negative ?? 0
                    high = low + entry.value
                    reached[entry.key, default: (0, 0)].negative = high
                }
            }
            let total = totals[entry.key] ?? (0, 0)
            if stacking == .normalized {
                let longest = max(total.positive, -total.negative)
                low = longest == 0 ? 0 : low / longest * Self.percent
                high = longest == 0 ? 0 : high / longest * Self.percent
            } else if stacking == .center {
                let shift = (total.positive + total.negative) / 2
                low -= shift
                high -= shift
            }
            if stacking != .unstacked {
                let known = wholes[entry.key] ?? (low, high)
                wholes[entry.key] = (min(known.low, low, high), max(known.high, low, high))
            }
            spans[entry.index] = Stacked(vertical: entry.key.vertical, low: low, high: high, whole: (min(low, high), max(low, high)))
        }
        for entry in entries where marks.instances[entry.index].mark.stacking != .unstacked {
            spans[entry.index]?.whole = wholes[entry.key] ?? (0, 0)
        }
        return spans
    }
}
