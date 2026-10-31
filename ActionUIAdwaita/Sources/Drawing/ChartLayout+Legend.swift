// Sources/Drawing/ChartLayout+Legend.swift
/*
 A chart's legend, from what ChartStyleMap lists.

 A legend shows the names of the color scale's domain, or without one those of the series a {"by"}
 color makes, a dot and a name each, in that order, and then those of a symbol or line style or size
 scale, and a color scale over numbers or dates as a bar (ChartStyleMap). A series outside a domain
 is not listed. A color domain alone is enough, even over marks of a fixed color, and with no names
 there is no legend, however visible it is asked to be. It takes room outside everything else, at
 the bottom unless told otherwise, starting at the chart's own edge and in columns that line up. A
 plot style's frame centers the plot and all around it, and the legend stays with them. Across, it
 fills rows; at a side it fills columns as high as the chart. A name that does not fit is not
 shortened, and one too long for a side leaves the plot a point wide. The overlay position sits on
 the plot at its top trailing corner and the corner positions at its top leading corner, taking no
 room and wrapping inside the plot.
*/

extension ChartLayout {
    private static let legendDateTicks = 4

    func legend(lineHeight: Double) -> Legend? {
        guard spec.legendVisibility != .hidden else { return nil }
        let place = Legend.Place(spec.legendPosition)
        let styled = styles.legendEntries(number: metrics.number) { lo, hi in
            dateLabels([lo, hi], unit: ChartDates.stride(lo, hi, count: Self.legendDateTicks).unit)
        }
        let entries = styled.map { Legend.Entry($0, lineHeight: lineHeight, down: place.fillsDown) { metrics.size($0).width } }
        guard !entries.isEmpty else { return nil }
        return Legend(place, entries, lineHeight: lineHeight, width: width, height: height)
    }

    /// A chart's legend, sized and laid out in a grid (measured on macOS 27).
    struct Legend {
        enum Place {
            case top, bottom, leading, trailing, overPlotLeading, overPlotTrailing

            init(_ position: ChartPosition) {
                switch position {
                case .automatic, .bottom: self = .bottom
                case .top: self = .top
                case .leading: self = .leading
                case .trailing: self = .trailing
                case .overlay: self = .overPlotTrailing
                case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: self = .overPlotLeading
                }
            }

            /// Rows fill first across the chart, columns first at a side.
            var fillsDown: Bool { self == .leading || self == .trailing }
        }

        struct Entry {
            let style: ChartLegendEntry
            let width: Double
            let height: Double
            /// How far a bar across the chart starts in: half its first label, which stays inside.
            let barStart: Double
            let sampleLength: Double
            let textStart: Double

            init(_ style: ChartLegendEntry, lineHeight: Double, down: Bool, measure: (String) -> Double) {
                self.style = style
                sampleLength = style.side.map { $0 + sizedSampleEnds } ?? sample
                textStart = style.stroke == nil ? (style.side ?? dot) + dotGap : sampleLength + sampleGap
                guard let bar = style.bar else {
                    height = max(lineHeight, style.side ?? 0)
                    barStart = 0
                    width = textStart + measure(style.name)
                    return
                }
                let labels = bar.ticks.map { measure($0.label) }
                let beside = barThickness + barTick + barLabelGap
                barStart = down ? 0 : (labels.first ?? 0) / 2
                width = down ? beside + (labels.max() ?? 0) : barStart + barLength + (labels.last ?? 0) / 2
                height = down ? barLength + lineHeight : beside + lineHeight
            }
        }

        private static let dot = 8.0, dotGap = 5.0, columnGap = 8.0, rowGap = 8.0
        /// A line's sample runs the whole of its room, and its caps past that; with a size scale it
        /// runs past the symbol's box instead, however small (measured on macOS 27).
        private static let sample = 16.0, sizedSampleEnds = 10.0, sampleGap = 5.0
        /// A color bar and the ticks past it, then a small gap to their labels.
        private static let barLength = 120.0, barThickness = 12.0, barTick = 4.0, barLabelGap = 2.0
        private static let barTickInk = ChartInk.text(opacity: 0.25)
        /// From a legend across the chart to what it shares an edge with, and from one at a side.
        private static let acrossGap = 4.0, sideGap = 8.0
        private static let plotInset = 8.0

        private let place: Place
        private let entries: [Entry]
        private let lineHeight: Double
        private let down: Bool
        private let rows: Int
        private let columnWidths: [Double]
        private let rowHeights: [Double]

        init(_ place: Place, _ entries: [Entry], lineHeight: Double, width: Double, height: Double) {
            self.place = place
            self.entries = entries
            self.lineHeight = lineHeight
            down = place.fillsDown
            let columns: Int
            if down {
                rows = Self.rowsFitting(entries, height)
                columns = (entries.count + rows - 1) / rows
            } else {
                columns = Self.columnsFitting(entries, width)
                rows = (entries.count + columns - 1) / columns
            }
            columnWidths = Self.widths(entries, columns: columns, down: down, rows: rows)
            rowHeights = Self.heights(entries, columns: columns, down: down, rows: rows)
        }

        // As many as every column holds, each counted by its own entries' heights, down to a single
        // row. Rows then line up, so a tall entry can still push others past the edge (measured on
        // macOS 27).
        private static func rowsFitting(_ entries: [Entry], _ height: Double) -> Int {
            var rows = 0, used = 0.0
            for entry in entries {
                let next = used + (rows > 0 ? rowGap : 0) + entry.height
                if rows > 0, next > height { break }
                used = next
                rows += 1
            }
            func fits(_ rows: Int) -> Bool {
                stride(from: 0, to: entries.count, by: rows).allSatisfy { start in
                    let column = entries[start..<min(start + rows, entries.count)]
                    return column.reduce(0) { $0 + $1.height } + rowGap * Double(column.count - 1) <= height
                }
            }
            while rows > 1, !fits(rows) { rows -= 1 }
            return max(rows, 1)
        }

        // Apple takes as many as fit the row as they come, then lines them up, which can push the
        // last past the edge. Here the columns stop where the lined up grid still fits.
        private static func columnsFitting(_ entries: [Entry], _ width: Double) -> Int {
            var columns = 0, used = 0.0
            for entry in entries {
                let next = used + (columns > 0 ? columnGap : 0) + entry.width
                if columns > 0, next > width { break }
                used = next
                columns += 1
            }
            while columns > 1, total(widths(entries, columns: columns, down: false, rows: 0)) > width {
                columns -= 1
            }
            return max(columns, 1)
        }

        private static func widths(_ entries: [Entry], columns: Int, down: Bool, rows: Int) -> [Double] {
            var widths = [Double](repeating: 0, count: columns)
            for (index, entry) in entries.enumerated() {
                let column = down ? index / rows : index % columns
                widths[column] = max(widths[column], entry.width)
            }
            return widths
        }

        private static func heights(_ entries: [Entry], columns: Int, down: Bool, rows: Int) -> [Double] {
            var heights = [Double](repeating: 0, count: rows)
            for (index, entry) in entries.enumerated() {
                let row = down ? index % rows : index / columns
                heights[row] = max(heights[row], entry.height)
            }
            return heights
        }

        private static func total(_ widths: [Double]) -> Double {
            widths.reduce(0, +) + columnGap * Double(max(widths.count - 1, 0))
        }

        private var size: ChartSize {
            ChartSize(width: Self.total(columnWidths), height: rowHeights.reduce(0, +) + Self.rowGap * Double(rows - 1))
        }

        /// What it takes from the plot on the edge it sits at, and nothing on any other.
        func room(_ edge: Place) -> Double {
            guard edge == place else { return 0 }
            switch place {
            case .top, .bottom: return size.height + Self.acrossGap
            case .leading, .trailing: return size.width + Self.sideGap
            case .overPlotLeading, .overPlotTrailing: return 0
            }
        }

        /// Over the plot it wraps inside it, which takes the plot's size, and that takes no room.
        mutating func fit(overPlot plot: ChartRect) {
            guard place == .overPlotLeading || place == .overPlotTrailing else { return }
            self = Legend(place, entries, lineHeight: lineHeight, width: plot.width - Self.plotInset * 2, height: plot.height)
        }

        /// `area` holds the plot and all around it: the chart, unless a frame sized the plot or
        /// what it holds does not fit. `plot` is the plot's frame, before any padding.
        func append(to primitives: inout [ChartPrimitive], area: ChartRect, plot: ChartRect) {
            var origin = ChartPoint(x: area.x, y: area.y)
            switch place {
            case .top, .leading: break
            case .bottom: origin.y = area.y + area.height - size.height
            case .trailing: origin.x = area.x + area.width - size.width
            case .overPlotLeading: origin = ChartPoint(x: plot.x + Self.plotInset, y: plot.y + Self.plotInset)
            case .overPlotTrailing: origin = ChartPoint(x: plot.x + plot.width - Self.plotInset - size.width, y: plot.y + Self.plotInset)
            }
            var columnStarts: [Double] = []
            var start = origin.x
            for width in columnWidths {
                columnStarts.append(start)
                start += width + Self.columnGap
            }
            var rowTops: [Double] = []
            var top = origin.y
            for height in rowHeights {
                rowTops.append(top)
                top += height + Self.rowGap
            }
            for (index, entry) in entries.enumerated() {
                let column = down ? index / rows : index % columnWidths.count
                let row = down ? index % rows : index / columnWidths.count
                let middle = rowTops[row] + rowHeights[row] / 2
                let x = columnStarts[column]
                if let bar = entry.style.bar {
                    append(bar, of: entry, x: x, top: middle - entry.height / 2, to: &primitives)
                    continue
                }
                if let stroke = entry.style.stroke {
                    primitives.append(.line(from: ChartPoint(x: x, y: middle), to: ChartPoint(x: x + entry.sampleLength, y: middle),
                                            ink: entry.style.ink, stroke: stroke))
                }
                let side = entry.style.side ?? Self.dot
                if let symbol = entry.style.symbol, side > 0 {
                    let center = x + (entry.style.stroke == nil ? side : entry.sampleLength) / 2
                    primitives.append(.symbol(symbol, center: ChartPoint(x: center, y: middle), side: side, ink: entry.style.ink))
                }
                primitives.append(.text(entry.style.name, position: ChartPoint(x: x + entry.textStart, y: middle),
                                        alignment: ChartPoint(x: 0, y: 0.5), ink: ChartLayout.labelInk))
            }
        }

        // Down the chart's side it runs from the top, half a label in, with its labels past its ticks.
        private func append(_ bar: ChartLegendBar, of entry: Entry, x: Double, top: Double, to primitives: inout [ChartPrimitive]) {
            let tickStroke = ChartStroke(lineWidth: 1)
            if down {
                let start = top + lineHeight / 2, tickStart = x + Self.barThickness, tickEnd = tickStart + Self.barTick
                primitives.append(.gradientBar(ChartRect(x: x, y: start, width: Self.barThickness, height: Self.barLength), stops: bar.stops, vertical: true))
                for tick in bar.ticks {
                    let y = start + tick.offset * Self.barLength
                    primitives.append(.line(from: ChartPoint(x: tickStart, y: y), to: ChartPoint(x: tickEnd, y: y), ink: Self.barTickInk, stroke: tickStroke))
                    primitives.append(.text(tick.label, position: ChartPoint(x: tickEnd + Self.barLabelGap, y: y), alignment: ChartPoint(x: 0, y: 0.5), ink: ChartLayout.labelInk))
                }
            } else {
                let start = x + entry.barStart, tickStart = top + Self.barThickness, tickEnd = tickStart + Self.barTick
                primitives.append(.gradientBar(ChartRect(x: start, y: top, width: Self.barLength, height: Self.barThickness), stops: bar.stops, vertical: false))
                for tick in bar.ticks {
                    let tickX = start + tick.offset * Self.barLength
                    primitives.append(.line(from: ChartPoint(x: tickX, y: tickStart), to: ChartPoint(x: tickX, y: tickEnd), ink: Self.barTickInk, stroke: tickStroke))
                    primitives.append(.text(tick.label, position: ChartPoint(x: tickX, y: tickEnd + Self.barLabelGap), alignment: ChartPoint(x: 0.5, y: 0), ink: ChartLayout.labelInk))
                }
            }
        }
    }
}
