// Sources/Drawing/ChartStyleMap.swift
/*
 What a chart's style scales come to over its marks: the names on each, what a name draws, and the
 legend's entries (measured on macOS 27).

 A color scale has names from its domain alone. A symbol or line style scale needs a mark wearing
 its {"by"}, and a domain then is the whole list: a value outside it draws in the first automatic
 style, whatever range is given. Only points and lines wear a symbol's, and only lines and rules a
 line style's. Symbols come in one order of seven, or of five once any line wears a symbol. Scales
 over the same names share their legend entries, however they were reached; others follow in the
 order color, symbol, line style. An entry without a color is the first series color, even over
 marks of a fixed one.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ChartLegendEntry {
    var name: String
    var ink: ChartInk
    /// What it shows: a symbol, a sample of a line, or a symbol on one.
    var symbol: ChartSymbol?
    var stroke: ChartStroke?
}

struct ChartStyleMap {
    private static let pointSymbols: [ChartSymbol] = [.circle, .cross, .triangle, .plus, .square, .asterisk, .diamond]
    private static let lineSymbols: [ChartSymbol] = [.circle, .square, .triangle, .diamond, .pentagon]
    private static let lineStyles: [ChartStroke] = [
        ChartLayout.defaultLine,
        dashed([4, 4]),
        dashed([8, 4]),
        dashed([8, 4, 2, 4]),
        dashed([0, 3])
    ]

    private static func dashed(_ dash: [Double]) -> ChartStroke {
        var stroke = ChartLayout.defaultLine
        stroke.dash = dash
        return stroke
    }

    private let colorRange: [ColorSpec]
    private let symbols: [ChartSymbol]
    private let strokes: [ChartStroke]
    private let colorNames: [String]
    private let symbolNames: [String]
    private let lineStyleNames: [String]
    private let colorIndex: [String: Int]
    private let symbolIndex: [String: Int]
    private let lineStyleIndex: [String: Int]

    init(_ spec: ChartSpec, _ marks: ChartResolvedMarks) {
        let styles = spec.styles
        if case .colors(let colors)? = styles.foregroundRange, !colors.isEmpty {
            colorRange = colors
        } else {
            colorRange = ChartLayout.seriesColors
        }
        let linesWearSymbols = marks.instances.contains { instance in
            instance.mark.kind == .LineMark && instance.mark.modifiers.contains { modifier in
                switch modifier {
                case .symbol, .symbolBy: return true
                default: return false
                }
            }
        }
        symbols = styles.symbolRange.isEmpty ? (linesWearSymbols ? Self.lineSymbols : Self.pointSymbols) : styles.symbolRange
        strokes = styles.lineStyleRange.isEmpty ? Self.lineStyles : styles.lineStyleRange

        if case .strings(let domain) = styles.foregroundDomain {
            colorNames = domain
        } else {
            colorNames = Self.names(marks, \.styleKey)
        }
        symbolNames = Self.names(marks, \.symbolKey, of: [.PointMark, .LineMark], domain: styles.symbolDomain)
        lineStyleNames = Self.names(marks, \.lineStyleKey, of: [.LineMark, .RuleMark], domain: styles.lineStyleDomain)
        colorIndex = Self.index(colorNames)
        symbolIndex = Self.index(symbolNames)
        lineStyleIndex = Self.index(lineStyleNames)
    }

    // The names in order of use, or the domain's once a mark uses any.
    private static func names(_ marks: ChartResolvedMarks, _ key: KeyPath<ChartMarkInstance, String?>, of kinds: Set<ChartMarkKind>? = nil,
                              domain: ChartDomain = .automatic()) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for instance in marks.instances where kinds?.contains(instance.mark.kind) ?? true {
            if let name = instance[keyPath: key], seen.insert(name).inserted {
                names.append(name)
            }
        }
        if case .strings(let domain) = domain, !names.isEmpty { return domain }
        return names
    }

    private static func index(_ names: [String]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (position, name) in names.enumerated() {
            index[name] = position
        }
        return index
    }

    func ink(_ instance: ChartMarkInstance) -> ChartInk {
        if let key = instance.styleKey, let index = colorIndex[key] {
            return .color(colorRange[index % colorRange.count])
        }
        for modifier in instance.mark.modifiers {
            if case .foregroundStyle(let color) = modifier {
                return .color(color)
            }
        }
        return .color(ChartLayout.seriesColors[0])
    }

    func symbol(named name: String) -> ChartSymbol {
        symbolIndex[name].map { symbols[$0 % symbols.count] } ?? .circle
    }

    func stroke(named name: String) -> ChartStroke {
        lineStyleIndex[name].map { strokes[$0 % strokes.count] } ?? ChartLayout.defaultLine
    }

    private struct LegendGroup {
        var names: [String]
        var colored = false
        var shaped = false
        var lined = false
    }

    var legendEntries: [ChartLegendEntry] {
        var groups: [LegendGroup] = []
        func add(_ names: [String], _ channel: WritableKeyPath<LegendGroup, Bool>) {
            guard !names.isEmpty else { return }
            let set = Set(names)
            if let index = groups.firstIndex(where: { Set($0.names) == set }) {
                groups[index][keyPath: channel] = true
            } else {
                var group = LegendGroup(names: names)
                group[keyPath: channel] = true
                groups.append(group)
            }
        }
        add(colorNames, \.colored)
        add(symbolNames, \.shaped)
        add(lineStyleNames, \.lined)
        return groups.flatMap { group in
            group.names.map { name in
                var ink = ChartInk.color(ChartLayout.seriesColors[0])
                if group.colored, let index = colorIndex[name] {
                    ink = .color(colorRange[index % colorRange.count])
                }
                let symbol = group.shaped ? symbol(named: name) : nil
                return ChartLegendEntry(name: name, ink: ink, symbol: symbol ?? (group.lined ? nil : .circle),
                                        stroke: group.lined ? stroke(named: name) : nil)
            }
        }
    }
}
