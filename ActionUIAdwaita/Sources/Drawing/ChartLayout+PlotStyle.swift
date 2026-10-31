// Sources/Drawing/ChartLayout+PlotStyle.swift
/*
 A chart's plot style.

 A plot style is a layer of its own, over the axes: its background hides the gridlines and any
 category labels on y, the marks draw on it, and its opacity, corner radius and clip shape take all
 of that together. Its border draws square around the layer, padding moves the plot and its axes in
 from the border, and a frame sets the plot's size, centered in its room.
*/

extension ChartLayout {
    /// What a chartPlotStyle asks of the plot, read as any view's properties are. Shadow, offset and
    /// foregroundStyle are not drawn.
    struct PlotStyle {
        private static let systemPadding = 16.0
        private let modifiers: BaseModifiers
        let background: ColorSpec?
        let border: (width: Double, ink: ChartInk)?
        private let radius: Double

        init(_ properties: [String: Any]) {
            modifiers = BaseModifiers(properties)
            background = ColorSpec.parse(modifiers.background)
            border = modifiers.border.map { border in
                (border.width, .color(ColorSpec.parse(border.color) ?? .named(.black)))
            }
            // A corner radius and a rounded clip shape both clip, so the larger shows.
            var radius = modifiers.cornerRadius ?? 0
            if case .roundedRectangle(let x, let y)? = modifiers.clipShape {
                radius = max(radius, min(x, y))
            }
            self.radius = max(radius, 0)
        }

        // The size a frame sets, centered in the plot's room even when larger than it. A minimum
        // or a maximum limits the room, and an ideal size changes nothing (measured on macOS 27).
        func framed(_ area: ChartRect) -> ChartRect {
            guard let frame = modifiers.frame else { return area }
            let width = Self.size(area.width, fixed: frame.width, lowest: frame.minWidth, highest: frame.maxWidth)
            let height = Self.size(area.height, fixed: frame.height, lowest: frame.minHeight, highest: frame.maxHeight)
            return ChartRect(x: area.x + (area.width - width) / 2, y: area.y + (area.height - height) / 2, width: width, height: height)
        }

        private static func size(_ room: Double, fixed: Double?, lowest: Double?, highest: Double?) -> Double {
            var size = fixed ?? room
            if let highest { size = min(size, highest) }
            if let lowest { size = max(size, lowest) }
            return size.isFinite && size >= 0 ? size : room
        }

        func padded(_ frame: ChartRect) -> ChartRect {
            var top = 0.0, leading = 0.0, bottom = 0.0, trailing = 0.0
            switch modifiers.padding {
            case nil:
                return frame
            case .system?:
                (top, leading, bottom, trailing) = (Self.systemPadding, Self.systemPadding, Self.systemPadding, Self.systemPadding)
            case .uniform(let all)?:
                (top, leading, bottom, trailing) = (all, all, all, all)
            case .edges(let edgeTop, let edgeLeading, let edgeBottom, let edgeTrailing)?:
                (top, leading, bottom, trailing) = (edgeTop, edgeLeading, edgeBottom, edgeTrailing)
            }
            // Padding past the frame leaves a point of plot, in the middle (measured on macOS 27).
            let width = max(frame.width - leading - trailing, 1), height = max(frame.height - top - bottom, 1)
            return ChartRect(x: frame.x + (frame.width - width + leading - trailing) / 2,
                             y: frame.y + (frame.height - height + top - bottom) / 2, width: width, height: height)
        }

        // nil when the marks need no layer, so a chart without a style draws as it always did.
        func layer(_ frame: ChartRect) -> ChartPlotLayer? {
            let opacity = min(max(modifiers.opacity ?? 1, 0), 1)
            // A corner radius of 0 clips too (measured on macOS 27).
            let clips = modifiers.clipShape != nil || modifiers.cornerRadius != nil
            guard background != nil || opacity < 1 || clips else { return nil }
            // The largest is half the short side, however large the radius.
            return ChartPlotLayer(rect: frame, radius: min(radius, min(frame.width, frame.height) / 2), opacity: opacity, clips: clips)
        }
    }
}
