// Sources/Drawing/ChartLayout+Lines.swift
/*
 Lines and areas, which join many marks into one shape.

 - A line or an area joins its points in data order, not by x. Marks with one series are one
   line, whatever {"by"} styles they wear, and without a series so are marks with the same ones,
   in the style of the first, drawn where that one is. A value that is
   not finite breaks it in two, and one point alone draws nothing. A line is 2 wide, an area is
   opaque, and stacked areas stack as bars do, each kind on its own. A start and end on an axis of
   categories run from edge to edge, as a bar's do.
 - On a line a symbol shows only where one is asked for, with its own mark's line width as its
   outline, its size unchanged, and it still shows on a line 0 wide. Its inside is a hole in that
   line alone, so the plot shows through and a later line crosses it; plus, cross and asterisk are
   solid. Each point has its own symbol, in the line's color, and a size {"by"} reaches it only
   where the symbol is a {"by"} too. A point on its own still has its symbol, and a line takes its
   dash but its symbols do not.
*/

extension ChartLayout {
    // The interpolation of the first mark, nearest modifier first.
    private func interpolation(_ mark: ChartMarkSpec) -> ChartInterpolation {
        for modifier in mark.modifiers {
            if case .interpolationMethod(let method) = modifier {
                return method
            }
        }
        return .linear
    }

    // A value that has no place on its axis breaks the line (measured on macOS 27, not a number on
    // either axis), and a piece of one point draws only its symbol.
    func line(_ indices: [Int], _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive? {
        let first = marks.instances[indices[0]]
        let method = interpolation(first.mark)
        var elements: [ChartPathElement] = []
        var piece: [ChartPoint] = []
        var symbols: [ChartLineSymbol] = []
        func endPiece() {
            if piece.count > 1 { elements += ChartCurves.elements(piece, method) }
            piece = []
        }
        for index in indices {
            let instance = marks.instances[index]
            if let px = position(instance, "x", x), let py = position(instance, "y", y) {
                let center = ChartPoint(x: px, y: py)
                piece.append(center)
                let (shape, side) = symbol(instance)
                // A size GSK cannot take costs this symbol, not the line.
                if let shape, Float(side).isFinite {
                    let lineWidth = max(self.stroke(instance, default: Self.defaultLine).lineWidth, 0)
                    symbols.append(ChartLineSymbol(symbol: shape, center: center, side: side, lineWidth: lineWidth))
                }
            } else {
                endPiece()
            }
        }
        endPiece()
        let stroke = stroke(first, default: Self.defaultLine)
        if !symbols.isEmpty {
            return .markedLine(elements, ink: ink, stroke: stroke, symbols: symbols)
        }
        return elements.isEmpty ? nil : .path(elements, ink: ink, stroke: stroke)
    }

    // Where an area's two edges are at one mark: nil where it has no place on an axis.
    private func areaEdges(_ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale) -> (upper: ChartPoint, lower: ChartPoint)? {
        if let stack {
            if stack.vertical {
                return position(instance, "x", x).map { (ChartPoint(x: $0, y: y.position(stack.high)), ChartPoint(x: $0, y: y.position(stack.low))) }
            }
            return position(instance, "y", y).map { (ChartPoint(x: x.position(stack.high), y: $0), ChartPoint(x: x.position(stack.low), y: $0)) }
        }
        if let px = position(instance, "x", x), let ys = span(instance, "yStart", "yEnd", y) {
            return (ChartPoint(x: px, y: ys.1), ChartPoint(x: px, y: ys.0))
        }
        if let py = position(instance, "y", y), let xs = span(instance, "xStart", "xEnd", x) {
            return (ChartPoint(x: xs.1, y: py), ChartPoint(x: xs.0, y: py))
        }
        return nil
    }

    func area(_ indices: [Int], _ stacks: [Int: Stacked], _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive? {
        let method = interpolation(marks.instances[indices[0]].mark)
        var elements: [ChartPathElement] = []
        var upper: [ChartPoint] = [], lower: [ChartPoint] = []
        // Along the top in data order, and back along the bottom, joined by straight ends. Both
        // edges take the method going forward (measured on macOS 27), so stacked areas share theirs.
        func endPiece() {
            if upper.count > 1 {
                elements += ChartCurves.elements(upper, method)
                for element in ChartCurves.elements(lower.reversed(), ChartCurves.backward(method)) {
                    if case .move(let point) = element {
                        elements.append(.line(point))
                    } else {
                        elements.append(element)
                    }
                }
            }
            upper = []
            lower = []
        }
        for index in indices {
            if let edges = areaEdges(marks.instances[index], stack: stacks[index], x, y) {
                upper.append(edges.upper)
                lower.append(edges.lower)
            } else {
                endPiece()
            }
        }
        endPiece()
        return elements.isEmpty ? nil : .fill(elements, ink: ink)
    }
}
